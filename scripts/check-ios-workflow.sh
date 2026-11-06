#!/usr/bin/env bash
# iOS GitHub Actions workflow 结构断言（.munk/code-gates.json 的 lint-ios-workflow 门真实执行体）。
# 校验 .github/workflows/ios.yml 的 YAML 解析、push 触发、macos-latest 单 job、步骤顺序、
# scripts/ 命令复用与 blocked 降级失败口径；并用人为破坏的副本自测断言确实会非零退出。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/check-ios-workflow.sh [--help]

对 .github/workflows/ios.yml 做结构断言并打印逐条结果：
  - 文件存在，YAML 可解析（ruby -ryaml；裸 on 键按 YAML 1.1 布尔处理）
  - 顶层含非空 name / on / jobs
  - on 含 push 且未被 branches/tags 白名单限制（首次推任意分支即触发）
  - 仅一个 job，runs-on 为 macos-latest
  - steps 中 install、lint、test、build 按序出现且每步 run 非空
  - install 幂等安装 xcodegen 并准备 iPhone 16 + iOS 18.6 模拟器
  - lint 独立调用 scripts/check-baseline.sh、check-ios-core.sh、check-ios-scripts.sh、check-ios-shell.sh
  - test/build 复用 scripts/test-ios.sh、scripts/build-ios.sh，且对 blocked: 输出显式 exit 1
  - workflow 内无第二套 xcodebuild test/build、无根 VERSION 字面值、无不实措辞
  - 自测：改错 runs-on / 删除 test 步骤 / 去掉 push 触发 / 去掉 blocked 失败口径时脚本非零退出

选项:
  -h, --help   显示本帮助并退出 0

退出码:
  0  全部断言通过
  1  存在失败断言
  2  参数非法
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    echo "check-ios-workflow: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "check-ios-workflow: 只接受一个参数（使用 --help 查看用法）" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

WORKFLOW=".github/workflows/ios.yml"

check_workflow_file() {
  ruby -ryaml - "$1" <<'RUBY'
# encoding: utf-8
require 'yaml'

path = ARGV[0]
$failures = 0

def report(ok, name, detail = nil)
  if ok
    puts "[PASS] #{name}"
  else
    puts "[FAIL] #{name}: #{detail}"
    $failures += 1
  end
end

def load_yaml(raw)
  if YAML.respond_to?(:unsafe_load)
    YAML.unsafe_load(raw)
  else
    YAML.load(raw)
  end
end

unless File.file?(path)
  report(false, 'ac-workflow-exists-and-parses', "缺少 #{path}")
  exit 1
end

raw = File.read(path, encoding: 'UTF-8')

begin
  doc = load_yaml(raw)
rescue StandardError => e
  report(false, 'ac-workflow-exists-and-parses', "YAML 解析失败: #{e.message}")
  exit 1
end

unless doc.is_a?(Hash)
  report(false, 'ac-workflow-exists-and-parses', '顶层不是映射')
  exit 1
end

# YAML 1.1（Psych）会把裸 on 解析为布尔 true，两种键名都要认。
on_key = doc.key?('on') ? 'on' : (doc.key?(true) ? true : nil)
on_value = on_key.nil? ? nil : doc[on_key]

has_name = doc.key?('name') && !doc['name'].to_s.strip.empty?
has_jobs = doc.key?('jobs') && doc['jobs'].is_a?(Hash) && !doc['jobs'].empty?
has_on = !on_key.nil? && on_value.is_a?(Hash) && !on_value.empty?
missing_top = []
missing_top << 'name' unless has_name
missing_top << 'on' unless has_on
missing_top << 'jobs' unless has_jobs
report(missing_top.empty?, 'ac-workflow-exists-and-parses', "顶层缺少或为空: #{missing_top.join(', ')}")

triggers = on_value.is_a?(Hash) ? on_value.keys.map(&:to_s) : []
push_cfg = on_value.is_a?(Hash) ? on_value['push'] : nil
push_present = triggers.include?('push')
restricted_keys = %w[branches branches-ignore tags tags-ignore paths paths-ignore]
push_restricted = push_cfg.is_a?(Hash) && (push_cfg.keys.map(&:to_s) & restricted_keys).any?
report(push_present && !push_restricted, 'ac-workflow-push-trigger',
       "triggers=#{triggers.join(',')} push_restricted=#{push_restricted}")

jobs = doc['jobs']
job_count = jobs.is_a?(Hash) ? jobs.size : 0
job = jobs.is_a?(Hash) ? jobs.values.first : nil
runs_on = job.is_a?(Hash) ? job['runs-on'] : nil
runs_on_value = runs_on.is_a?(Array) ? runs_on.join(',') : runs_on.to_s
report(job_count == 1 && runs_on_value == 'macos-latest', 'ac-workflow-macos-latest',
       "job 数量 #{job_count}，runs-on '#{runs_on_value}'")

steps = job.is_a?(Hash) && job['steps'].is_a?(Array) ? job['steps'] : []
step_name = ->(s) { s.is_a?(Hash) ? s['name'].to_s : '' }
expected = %w[install lint test build]
ordered = steps.map(&step_name).select { |n| expected.include?(n) }
runs = {}
expected.each do |name|
  step = steps.find { |s| step_name.call(s) == name }
  runs[name] = step.is_a?(Hash) ? step['run'].to_s : ''
end
missing_runs = expected.select { |n| runs[n].strip.empty? }
report(ordered == expected && missing_runs.empty?, 'ac-workflow-step-order',
       "实际顺序 #{ordered.join(',')}；缺 run 的步骤: #{missing_runs.join(',')}")

install_run = runs['install']
install_missing = []
install_missing << 'command -v xcodegen' unless install_run.include?('command -v xcodegen')
install_missing << 'brew install xcodegen' unless install_run.include?('brew install xcodegen')
install_missing << 'iPhone 16' unless install_run.include?('iPhone 16')
install_missing << 'iOS 18.6' unless install_run.include?('18.6')
install_missing << 'simctl list devices' unless install_run.include?('simctl list devices')
install_missing << 'simctl create' unless install_run.include?('simctl create')
install_missing << 'downloadPlatform iOS' unless install_run.include?('downloadPlatform iOS')
report(install_missing.empty?, 'ac-install-provisions-xcodegen-and-simulator',
       "install 步骤缺少: #{install_missing.join('、')}")

lint_run = runs['lint']
lint_lines = lint_run.lines.map(&:strip).reject(&:empty?)
required_lint = %w[
  scripts/check-baseline.sh
  scripts/check-ios-core.sh
  scripts/check-ios-scripts.sh
  scripts/check-ios-shell.sh
]
lint_missing = required_lint.reject { |cmd| lint_lines.include?("bash #{cmd}") }
lint_joined = lint_run.include?('&&') || lint_run.include?(';')
report(lint_missing.empty? && !lint_joined, 'ac-lint-step-reuses-local-gates',
       "缺少独立命令: #{lint_missing.join(',')}；含合并分隔符: #{lint_joined}")

test_run = runs['test']
build_run = runs['build']
reuse_ok = test_run.include?('bash scripts/test-ios.sh') && build_run.include?('bash scripts/build-ios.sh')
second_xcodebuild = raw.match?(/xcodebuild\s+test\b/) || raw.match?(/xcodebuild\s+build\b/)
report(reuse_ok && !second_xcodebuild, 'ac-test-build-reuse-scripts',
       'test/build 未复用 scripts 或出现第二套 xcodebuild 调用')

blocked_ok = test_run.include?('blocked:') && test_run.match?(/exit\s+1/) &&
             build_run.include?('blocked:') && build_run.match?(/exit\s+1/)
report(blocked_ok, 'ac-ci-fails-on-blocked-degradation',
       'test/build 未对 blocked: 输出显式 exit 1')

version = File.file?('VERSION') ? File.read('VERSION').strip : ''
report(version.empty? || !raw.include?(version), 'ac-no-version-literal',
       "workflow 出现根 VERSION 字面值 '#{version}'")

fake_words = ['CI 通过', 'CI 已通过', '真机已验证'].select { |word| raw.include?(word) }
report(fake_words.empty?, 'ac-no-fake-ci-wording',
       "出现无 run id 支撑的措辞: #{fake_words.join(',')}")

if $failures.zero?
  puts 'workflow 结构断言通过'
  exit 0
else
  puts "#{$failures} 项断言失败"
  exit 1
end
RUBY
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

if out="$(check_workflow_file "$WORKFLOW")"; then
  rc=0
else
  rc=$?
fi
printf '%s\n' "$out"
if [ "$rc" -ne 0 ]; then
  echo "check-ios-workflow: workflow 结构断言失败" >&2
  exit 1
fi

# ---------------------------------------------------------------- 负向自测
self_test_failures=0

assert_rejected() {
  local label="$1"
  local file="$2"
  local expected_id="$3"
  local out rc
  if out="$(check_workflow_file "$file")"; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -Fq -- "[FAIL] $expected_id"; then
    printf '[PASS] ac-workflow-structural-gate (%s 被拒绝)\n' "$label"
  else
    printf '[FAIL] ac-workflow-structural-gate: %s 未被拒绝（rc=%s，期望失败项 %s）\n' "$label" "$rc" "$expected_id"
    printf '%s\n' "$out"
    self_test_failures=$((self_test_failures + 1))
  fi
}

sed 's/runs-on: macos-latest/runs-on: ubuntu-latest/' "$WORKFLOW" > "$tmp_dir/wrong-runner.yml"
assert_rejected "改错 runs-on" "$tmp_dir/wrong-runner.yml" "ac-workflow-macos-latest"

awk '
  /^      - name: test$/ { skip = 1 }
  skip && /^      - name: build$/ { skip = 0 }
  !skip { print }
' "$WORKFLOW" > "$tmp_dir/missing-test.yml"
assert_rejected "删除 test 步骤" "$tmp_dir/missing-test.yml" "ac-workflow-step-order"

sed '/^  push:$/d' "$WORKFLOW" > "$tmp_dir/no-push.yml"
assert_rejected "去掉 push 触发" "$tmp_dir/no-push.yml" "ac-workflow-push-trigger"

sed 's/blocked:/blocked-removed:/g' "$WORKFLOW" > "$tmp_dir/no-blocked.yml"
assert_rejected "去掉 blocked 失败口径" "$tmp_dir/no-blocked.yml" "ac-ci-fails-on-blocked-degradation"

if [ "$self_test_failures" -ne 0 ]; then
  echo "check-ios-workflow: 负向自测失败 $self_test_failures 项" >&2
  exit 1
fi

printf 'ios workflow OK\n'
