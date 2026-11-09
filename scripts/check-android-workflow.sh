#!/usr/bin/env bash
# Android GitHub Actions workflow 结构断言（.munk/code-gates.json 的 lint-android-workflow 门真实执行体）。
# 校验 .github/workflows/android.yml 的 YAML 解析、push 触发、ubuntu-latest 单 job、JDK 21 /
# Android SDK 前置、步骤顺序、scripts/ 命令复用与 blocked 失败口径；并用人为破坏的副本
# 自测断言确实会非零退出。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/check-android-workflow.sh [--help]

对 .github/workflows/android.yml 做结构断言并打印逐条结果：
  - 文件存在，YAML 可解析（ruby -ryaml 优先，回退 python3 + PyYAML；两者都不可用即失败）
  - 顶层含非空 name / on / jobs
  - on 含 push 且未被 branches/tags 白名单限制（推任意分支即触发），并含 workflow_dispatch
  - 仅一个 job，runs-on 为 ubuntu-latest，permissions.contents 为 read
  - install 阶段显式装 JDK 21（setup-java + temurin）与 Android SDK，安装
    platforms;android-36 / build-tools;36.0.0，并显式校验 java 主版本 21 与 ANDROID_HOME 目录
  - steps 中 install、lint、test、build 按序出现且每步 run 非空
  - lint 独立调用 scripts/check-baseline.sh、scripts/check-android.sh
  - test/build 复用 scripts/test-android.sh、scripts/build-android.sh，且对 blocked: 输出显式 exit 1
  - workflow 内无 gradlew 直连调用、无根 VERSION 字面值、无不实措辞
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
    echo "check-android-workflow: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "check-android-workflow: 只接受一个参数（使用 --help 查看用法）" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

WORKFLOW=".github/workflows/android.yml"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-android-workflow.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

# YAML → JSON：优先 ruby（-ryaml），回退 python3（PyYAML）；Psych/PyYAML 按 YAML 1.1
# 会把裸 on 解析成布尔 true，这里统一归一化回字符串键 on。
yaml_to_json() {
  local path="$1"
  if command -v ruby >/dev/null 2>&1 && ruby -ryaml -e 'exit 0' >/dev/null 2>&1; then
    ruby -ryaml -rjson - "$path" <<'RUBY'
require 'yaml'
require 'json'
raw = File.read(ARGV[0], encoding: 'UTF-8')
doc = YAML.respond_to?(:unsafe_load) ? YAML.unsafe_load(raw) : YAML.load(raw)
if doc.is_a?(Hash) && !doc.key?('on') && doc.key?(true)
  doc['on'] = doc.delete(true)
end
puts JSON.generate(doc)
RUBY
    return $?
  fi
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
    python3 - "$path" <<'PY'
import json
import sys

import yaml

with open(sys.argv[1], encoding='utf-8') as fh:
    raw = fh.read()
doc = yaml.safe_load(raw)
if isinstance(doc, dict) and 'on' not in doc and True in doc:
    doc['on'] = doc.pop(True)
print(json.dumps(doc))
PY
    return $?
  fi
  echo "缺少 YAML 解析器：需要 ruby（-ryaml）或 python3（PyYAML）" >&2
  return 1
}

check_workflow_file() {
  local path="$1"
  if [ ! -f "$path" ]; then
    printf '[FAIL] ac-workflow-exists-and-parses: 缺少 %s\n' "$path"
    return 1
  fi

  local json_file="$tmp_dir/workflow.json"
  if ! yaml_to_json "$path" > "$json_file" 2> "$tmp_dir/yaml.err"; then
    printf '[FAIL] ac-workflow-exists-and-parses: YAML 解析失败或缺少解析器: %s\n' \
      "$(tr '\n' ' ' < "$tmp_dir/yaml.err")"
    return 1
  fi

  node - "$json_file" "$path" <<'NODE'
const fs = require('fs');

const doc = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const raw = fs.readFileSync(process.argv[3], 'utf8');
let failures = 0;

const isObj = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);
const report = (ok, name, detail = '') => {
  if (ok) {
    console.log(`[PASS] ${name}`);
  } else {
    console.log(`[FAIL] ${name}: ${detail}`);
    failures += 1;
  }
};

if (!isObj(doc)) {
  report(false, 'ac-workflow-exists-and-parses', '顶层不是映射');
  process.exit(1);
}

const on = doc.on;
const onObj = isObj(on) ? on : {};
const missingTop = [];
if (typeof doc.name !== 'string' || doc.name.trim() === '') missingTop.push('name');
if (!isObj(on) || Object.keys(onObj).length === 0) missingTop.push('on');
if (!isObj(doc.jobs) || Object.keys(doc.jobs).length === 0) missingTop.push('jobs');
report(missingTop.length === 0, 'ac-workflow-exists-and-parses',
  `顶层缺少或为空: ${missingTop.join(', ')}`);

const triggers = Object.keys(onObj);
const pushCfg = onObj.push;
const restrictedKeys = ['branches', 'branches-ignore', 'tags', 'tags-ignore', 'paths', 'paths-ignore'];
const pushRestricted = isObj(pushCfg) && Object.keys(pushCfg).some((key) => restrictedKeys.includes(key));
report(triggers.includes('push') && !pushRestricted && triggers.includes('workflow_dispatch'),
  'ac-workflow-push-trigger',
  `triggers=${triggers.join(',')} push_restricted=${pushRestricted}`);

const jobs = isObj(doc.jobs) ? doc.jobs : {};
const jobCount = Object.keys(jobs).length;
const job = jobCount === 1 ? Object.values(jobs)[0] : null;
const runsOn = isObj(job) ? job['runs-on'] : undefined;
const runsOnValue = Array.isArray(runsOn) ? runsOn.join(',') : String(runsOn ?? '');
const permissions = doc.permissions;
const contents = isObj(permissions) ? String(permissions.contents ?? '') : '';
report(jobCount === 1 && runsOnValue === 'ubuntu-latest' && contents === 'read',
  'ac-workflow-single-ubuntu-job',
  `job 数量 ${jobCount}，runs-on '${runsOnValue}'，permissions.contents '${contents}'`);

const steps = isObj(job) && Array.isArray(job.steps) ? job.steps : [];
const stepName = (step) => (isObj(step) ? String(step.name ?? '') : '');
const expected = ['install', 'lint', 'test', 'build'];
const ordered = steps.map(stepName).filter((name) => expected.includes(name));
const runs = {};
for (const name of expected) {
  const step = steps.find((candidate) => stepName(candidate) === name);
  runs[name] = isObj(step) ? String(step.run ?? '') : '';
}
const missingRuns = expected.filter((name) => runs[name].trim() === '');
report(JSON.stringify(ordered) === JSON.stringify(expected) && missingRuns.length === 0,
  'ac-workflow-step-order',
  `实际顺序 ${ordered.join(',')}；缺 run 的步骤: ${missingRuns.join(',')}`);

const installRun = runs.install;
const installMissing = [];
if (!raw.includes('actions/setup-java@v4')) installMissing.push('actions/setup-java@v4');
if (!/java-version:\s*['"]?21['"]?/.test(raw)) installMissing.push("java-version: '21'");
if (!raw.includes('temurin')) installMissing.push('temurin');
if (!raw.includes('actions/setup-android@v3')) installMissing.push('actions/setup-android@v3');
if (!installRun.includes('sdkmanager')) installMissing.push('sdkmanager');
if (!installRun.includes('platforms;android-36')) installMissing.push('platforms;android-36');
if (!installRun.includes('build-tools;36.0.0')) installMissing.push('build-tools;36.0.0');
if (!installRun.includes('java -version') || !installRun.includes('java_major') || !installRun.includes('21')) {
  installMissing.push('java 主版本 21 校验');
}
if (!installRun.includes('-d "$ANDROID_HOME"')) installMissing.push('ANDROID_HOME 目录校验');
report(installMissing.length === 0, 'ac-install-provisions-jdk21-and-sdk',
  `install 阶段缺少: ${installMissing.join('、')}`);

const lintRun = runs.lint;
const lintLines = lintRun.split('\n').map((line) => line.trim()).filter((line) => line !== '');
const requiredLint = ['scripts/check-baseline.sh', 'scripts/check-android.sh'];
const lintMissing = requiredLint.filter((cmd) => !lintLines.includes(`bash ${cmd}`));
const lintJoined = lintRun.includes('&&') || lintRun.includes(';');
report(lintMissing.length === 0 && !lintJoined, 'ac-lint-step-reuses-local-gates',
  `缺少独立命令: ${lintMissing.join(', ')}；含合并分隔符: ${lintJoined}`);

const testRun = runs.test;
const buildRun = runs.build;
const reuseOk = testRun.includes('bash scripts/test-android.sh') &&
  buildRun.includes('bash scripts/build-android.sh');
const secondGradle = /gradlew/.test(raw);
report(reuseOk && !secondGradle, 'ac-test-build-reuse-scripts',
  'test/build 未复用 scripts 或 workflow 内出现 gradlew 直连调用');

const blockedOk = testRun.includes('blocked:') && /exit\s+1/.test(testRun) &&
  buildRun.includes('blocked:') && /exit\s+1/.test(buildRun);
report(blockedOk, 'ac-ci-fails-on-blocked-degradation',
  'test/build 未对 blocked: 输出显式 exit 1');

const version = fs.existsSync('VERSION') ? fs.readFileSync('VERSION', 'utf8').trim() : '';
report(version === '' || !raw.includes(version), 'ac-no-version-literal',
  `workflow 出现根 VERSION 字面值 '${version}'`);

const fakeWords = ['CI 通过', 'CI 已通过', '真机已验证'].filter((word) => raw.includes(word));
report(fakeWords.length === 0, 'ac-no-fake-ci-wording',
  `出现无 run id 支撑的措辞: ${fakeWords.join(',')}`);

if (failures === 0) {
  console.log('workflow 结构断言通过');
  process.exit(0);
}
console.log(`${failures} 项断言失败`);
process.exit(1);
NODE
}

if out="$(check_workflow_file "$WORKFLOW")"; then
  rc=0
else
  rc=$?
fi
printf '%s\n' "$out"
if [ "$rc" -ne 0 ]; then
  echo "check-android-workflow: workflow 结构断言失败" >&2
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
  if [ "$rc" -ne 0 ] && grep -Fq -- "[FAIL] $expected_id" <<< "$out"; then
    printf '[PASS] ac-workflow-structural-gate (%s 被拒绝)\n' "$label"
  else
    printf '[FAIL] ac-workflow-structural-gate: %s 未被拒绝（rc=%s，期望失败项 %s）\n' \
      "$label" "$rc" "$expected_id"
    printf '%s\n' "$out"
    self_test_failures=$((self_test_failures + 1))
  fi
}

sed 's/runs-on: ubuntu-latest/runs-on: macos-latest/' "$WORKFLOW" > "$tmp_dir/wrong-runner.yml"
assert_rejected "改错 runs-on" "$tmp_dir/wrong-runner.yml" "ac-workflow-single-ubuntu-job"

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
  echo "check-android-workflow: 负向自测失败 $self_test_failures 项" >&2
  exit 1
fi

printf 'android workflow OK\n'
