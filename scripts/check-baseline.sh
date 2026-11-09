#!/usr/bin/env bash
# 仓库协作基线结构断言（.munk/code-gates.json 的 test 门真实执行体）。
# 逐条校验本项验收项；任一条失败即非零退出，不用 echo / true 冒充。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/check-baseline.sh [--help]

对仓库协作基线做结构断言并打印逐条结果：
  - 根 VERSION 单一真源（单行、无 BOM、x.y.z）
  - scripts/version.sh 真实读取 VERSION（含沙箱内改值后输出随之改变）
  - README.md / scripts/*.sh 无版本字面值
  - AGENTS.md 四节齐全且正文非空、测试金字塔落点与命令齐全
  - AGENTS.md skill 路由表与 .agents/skills/ 磁盘内容双向一致
  - 至少 1 个 iOS/SwiftUI 与 1 个 Android 对应 skill
  - .munk/code-gates.json 的 lint / test 门为单一 argv，test 门指向本脚本

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
    echo "check-baseline: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "check-baseline: 只接受一个参数（使用 --help 查看用法）" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

CHECKS=0
FAILURES=0

pass() {
  CHECKS=$((CHECKS + 1))
  printf '[PASS] %s\n' "$1"
}

fail() {
  CHECKS=$((CHECKS + 1))
  FAILURES=$((FAILURES + 1))
  printf '[FAIL] %s: %s\n' "$1" "$2"
}

# 取 AGENTS.md 中命中关键词的那个标题下的正文（到下一个非代码块内的标题为止）。
section_body() {
  awk -v kw="$2" '
    {
      line = tolower($0)
      fenced = in_fence
      if ($0 ~ /^[ \t]*```/) { in_fence = !in_fence }
      if (!found && !fenced && line ~ /^#+[ \t]/ && index(line, kw) > 0) { found = 1; next }
      if (found && !fenced && line ~ /^#+[ \t]/) { exit }
      if (found && $0 ~ /[^ \t]/) { print }
    }
  ' "$1"
}

# ---------------------------------------------------------------- VERSION
version_value=""
if [ ! -f VERSION ]; then
  fail "ac-version-file-single-source" "仓库根缺少 VERSION 文件"
else
  problems=""
  bom_hex="$(head -c 3 VERSION | od -An -tx1 | tr -d ' \n')"
  [ "$bom_hex" != "efbbbf" ] || problems="$problems 含 BOM;"
  if grep -q "$(printf '\r')" VERSION 2>/dev/null; then
    problems="$problems 含 CR;"
  fi
  if [ "$(wc -l < VERSION | tr -d ' ')" != "1" ]; then
    problems="$problems 不是恰好单行（需以单个换行结尾）;"
  fi
  version_value="$(tr -d '\r\n' < VERSION)"
  if [ -z "$version_value" ]; then
    problems="$problems 内容为空;"
  elif ! grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' <<< "$version_value"; then
    problems="$problems 不匹配 ^[0-9]+\.[0-9]+\.[0-9]+$;"
  fi
  if [ -z "$problems" ]; then
    pass "ac-version-file-single-source (VERSION=$version_value)"
  else
    fail "ac-version-file-single-source" "$problems"
  fi
fi

# ------------------------------------------------------ scripts/version.sh
if [ ! -f scripts/version.sh ]; then
  fail "ac-version-script-reads-file" "缺少 scripts/version.sh"
else
  problems=""
  if ! bash scripts/version.sh --help >/dev/null 2>&1; then
    problems="$problems --help 未退出 0;"
  fi
  if [ -n "$version_value" ]; then
    actual="$(bash scripts/version.sh 2>/dev/null || printf '<非零退出>')"
    [ "$actual" = "$version_value" ] || problems="$problems 输出 '$actual' 与 VERSION '$version_value' 不一致;"
  else
    problems="$problems VERSION 不可用，无法比对;"
  fi

  # 沙箱改值：复制 version.sh 与一个不同值的 VERSION，输出必须随之改变。
  sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-baseline.XXXXXX")"
  trap 'rm -rf "$sandbox"' EXIT
  mkdir -p "$sandbox/scripts"
  cp scripts/version.sh "$sandbox/scripts/version.sh"
  printf '%s\n' "99.99.99" > "$sandbox/VERSION"
  sandbox_out="$(bash "$sandbox/scripts/version.sh" 2>/dev/null || printf '<非零退出>')"
  [ "$sandbox_out" = "99.99.99" ] || problems="$problems 沙箱改值后输出为 '$sandbox_out'，疑似缓存或写死;"
  printf '%s\n' "not-a-version" > "$sandbox/VERSION"
  if bash "$sandbox/scripts/version.sh" >/dev/null 2>&1; then
    problems="$problems 非法 VERSION 未触发非零退出;"
  fi

  if [ -z "$problems" ]; then
    pass "ac-version-script-reads-file"
  else
    fail "ac-version-script-reads-file" "$problems"
  fi
fi

# --------------------------------------------------- 无硬编码版本字面值
if [ -z "$version_value" ]; then
  fail "ac-no-hardcoded-version" "VERSION 不可用，无法校验字面值"
else
  hits="$(grep -Fn -- "$version_value" README.md scripts/*.sh 2>/dev/null || true)"
  if [ -z "$hits" ]; then
    pass "ac-no-hardcoded-version"
  else
    fail "ac-no-hardcoded-version" "出现版本字面值 '$version_value': $(printf '%s' "$hits" | tr '\n' ' ')"
  fi
fi

if [ -f scripts/version.sh ]; then
  if grep -q 'VERSION' scripts/version.sh \
    && ! grep -Eq 'git describe|git rev-parse|MARKETING_VERSION|versionName|CURRENT_PROJECT_VERSION' scripts/version.sh; then
    pass "ac-version-source-only-version-file"
  else
    fail "ac-version-source-only-version-file" "scripts/version.sh 未以 VERSION 文件为唯一版本来源"
  fi
else
  fail "ac-version-source-only-version-file" "缺少 scripts/version.sh"
fi

# ------------------------------------------------------------- AGENTS.md
if [ ! -f AGENTS.md ]; then
  fail "ac-agents-four-sections" "仓库根缺少 AGENTS.md"
else
  missing=""
  for kw in "技术栈" "目录约定" "测试金字塔" "skill 路由"; do
    case "$kw" in
      "skill 路由") probe="skill 路由" ;;
      *) probe="$kw" ;;
    esac
    body="$(section_body AGENTS.md "$(printf '%s' "$probe" | tr 'A-Z' 'a-z')")"
    if [ -z "$body" ]; then
      missing="$missing '$probe';"
    fi
  done
  if [ -z "$missing" ]; then
    pass "ac-agents-four-sections"
  else
    fail "ac-agents-four-sections" "缺少标题或正文为空:$missing"
  fi
fi

if [ ! -f AGENTS.md ]; then
  fail "ac-test-pyramid-doc" "仓库根缺少 AGENTS.md"
else
  problems=""
  pyramid="$(printf '%s' "$(section_body AGENTS.md '测试金字塔')")"
  if [ -z "$pyramid" ]; then
    problems="$problems 测试金字塔节为空;"
  else
    for needle in "ios/Core" "swift test" "android/app/src/test" "PurePaceUITests" "XCUITest" "swift test --filter" "xcodebuild test -only-testing:" "./gradlew testDebugUnitTest --tests" "scripts/test-ios.sh" "scripts/test-android.sh"; do
      if ! grep -Fq -- "$needle" <<< "$pyramid"; then
        problems="$problems 缺少 '$needle';"
      fi
    done
    if ! grep -Eqi 'junit' <<< "$pyramid"; then
      problems="$problems 缺少 JUnit 说明;"
    fi
    if ! grep -Eqi 'robolectric|compose ui test' <<< "$pyramid"; then
      problems="$problems 缺少 Robolectric 或 Compose UI test 说明;"
    fi
  fi
  if [ -z "$problems" ]; then
    pass "ac-test-pyramid-doc"
  else
    fail "ac-test-pyramid-doc" "$problems"
  fi
fi

# -------------------------------------- skill 路由表 ⇔ 磁盘双向一致
if [ ! -f AGENTS.md ]; then
  fail "ac-skill-routing-matches-disk" "仓库根缺少 AGENTS.md"
else
  routed="$(grep -o '\.agents/skills/[A-Za-z0-9._-]*' AGENTS.md 2>/dev/null | sed 's|.*/||' | sort -u || true)"
  on_disk=""
  if [ -d .agents/skills ]; then
    on_disk="$(find .agents/skills -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort -u)"
  fi
  problems=""
  if [ -z "$routed" ]; then
    problems="$problems AGENTS.md 路由表未登记任何 .agents/skills/<name>;"
  fi
  for name in $routed; do
    if [ ! -s ".agents/skills/$name/SKILL.md" ]; then
      problems="$problems 路由项 '$name' 在磁盘上不存在或 SKILL.md 为空;"
    fi
  done
  for name in $on_disk; do
    if ! grep -Fxq -- "$name" <<< "$routed"; then
      problems="$problems 磁盘 skill '$name' 未在 AGENTS.md 路由表登记;"
    fi
  done
  if [ -z "$problems" ]; then
    pass "ac-skill-routing-matches-disk"
  else
    fail "ac-skill-routing-matches-disk" "$problems"
  fi
fi

# --------------------------------------------- iOS + Android skill 存在
ios_ok=0
android_ok=0
if [ -d .agents/skills ]; then
  for skill_md in .agents/skills/*/SKILL.md; do
    [ -s "$skill_md" ] || continue
    if grep -Eqi 'swiftui|swift|ios' "$skill_md"; then
      ios_ok=1
    fi
    if grep -Eqi 'android' "$skill_md" && grep -Eqi 'kotlin|gradle|compose' "$skill_md"; then
      android_ok=1
    fi
  done
fi
problems=""
[ "$ios_ok" -eq 1 ] || problems="$problems 缺少 iOS/SwiftUI 对应 skill;"
[ "$android_ok" -eq 1 ] || problems="$problems 缺少 Android 对应 skill;"
if [ -z "$problems" ]; then
  pass "ac-skills-ios-android"
else
  fail "ac-skills-ios-android" "$problems"
fi

# ------------------------------------------------------- 不在全局安装
if [ -d "$HOME/.agents/skills" ]; then
  leaked=""
  for name in swiftui-pro android-cli; do
    if [ -e "$HOME/.agents/skills/$name" ]; then
      leaked="$leaked $name"
    fi
  done
  if [ -z "$leaked" ]; then
    pass "ac-skills-not-global"
  else
    fail "ac-skills-not-global" "在 ~/.agents/skills 发现本仓 skill:$leaked"
  fi
else
  pass "ac-skills-not-global"
fi

# ------------------------------------------------------------ README.md
if [ ! -f README.md ]; then
  fail "readme-entry-points" "仓库根缺少 README.md"
else
  problems=""
  for needle in "VERSION" "AGENTS.md" "scripts/"; do
    if ! grep -Fq -- "$needle" README.md; then
      problems="$problems 缺少 '$needle';"
    fi
  done
  if [ -z "$problems" ]; then
    pass "readme-entry-points"
  else
    fail "readme-entry-points" "$problems"
  fi
fi

# ------------------------------------------------- .munk/code-gates.json
if ! command -v node >/dev/null 2>&1; then
  fail "ac-code-gates-test-real" "缺少 node，无法校验 .munk/code-gates.json"
elif [ ! -f .munk/code-gates.json ]; then
  fail "ac-code-gates-test-real" "缺少 .munk/code-gates.json"
else
  gate_error="$(node -e '
    const fs = require("fs");
    const bad = (m) => { console.error(m); process.exit(1); };
    let cfg;
    try { cfg = JSON.parse(fs.readFileSync(".munk/code-gates.json", "utf8")); }
    catch (e) { bad("JSON 解析失败: " + e.message); }
    if (cfg.version !== 1) bad("version 必须为 1");
    if (!Array.isArray(cfg.gates) || cfg.gates.length === 0) bad("gates 必须是非空数组");
    const ids = cfg.gates.map((g) => g.id);
    for (const need of ["lint", "test"]) {
      if (ids.indexOf(need) === -1) bad("缺少 " + need + " 门");
    }
    for (const g of cfg.gates) {
      if (typeof g.command !== "string" || g.command.trim() === "") bad("门 " + g.id + " 的 command 为空");
      if (/[&|;<>`]|\n/.test(g.command)) bad("门 " + g.id + " 的 command 含 shell 分隔符或重定向: " + g.command);
      if (/^\s*(echo|true|:)\b/.test(g.command)) bad("门 " + g.id + " 是占位/空转命令: " + g.command);
    }
    const testGate = cfg.gates.filter((g) => g.id === "test")[0];
    if (!/scripts\/check-baseline\.sh/.test(testGate.command)) bad("test 门未执行 scripts/check-baseline.sh");
  ' 2>&1)" && gate_ok=1 || gate_ok=0
  if [ "$gate_ok" -eq 1 ]; then
    pass "ac-code-gates-test-real"
  else
    fail "ac-code-gates-test-real" "$(printf '%s' "$gate_error" | tr '\n' ' ')"
  fi
fi

printf '\n%d 项断言，%d 项失败\n' "$CHECKS" "$FAILURES"
if [ "$FAILURES" -ne 0 ]; then
  exit 1
fi
printf 'baseline OK (VERSION=%s)\n' "$version_value"
