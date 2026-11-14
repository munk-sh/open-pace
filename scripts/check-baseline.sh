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
  - README.md / scripts/*.sh 无版本字面值（README 版本表数据行是唯一受控豁免，表格外写入仍判红）
  - README「当前状态」段与版本表首行同时写「已推 tag」与「未分发」（含 tag sha / 日期 / 两次 CI run），并含三类反例判红自检
  - README 版本表首行 / CHANGELOG 首条 / VERSION 三源一致（版本与日期），表首行状态反例在沙箱判红
  - CHANGELOG 首条状态行同时写「已推 tag」「tag sha」「日期」「未分发」并保留非发布声明；与 README 版本表首行状态列及当前状态段交叉比对，含三类反例判红自检
  - docs/release/ 下 release notes 英文四节 + zh-CN 折叠段、已推 tag + 未分发口径、禁词零命中、三条已知限制、构建不可复现事实保留，并含三类反例判红自检
  - .github/workflows/release.yml 仅 workflow_dispatch、tag 由 VERSION 派生、无版本字面值、只 push tag、最小权限，并含三类反例判红自检
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

# ------------------------------------------------------------ 发布前语义断言
# 以下函数统一接受 root 参数，反例自检在 mktemp 副本上执行，不修改生产文件。

# README 版本表数据行（首行）：| 版本 | 日期 | 状态 | CHANGELOG |
readme_version_row() {
  grep -E '^\| *[0-9]+\.[0-9]+\.[0-9]+ *\|' "$1/README.md" 2>/dev/null | head -n 1 || true
}

# CHANGELOG 首条版本标题：## [x.y.z] - YYYY-MM-DD
changelog_version_heading() {
  grep -E '^## \[[0-9]+\.[0-9]+\.[0-9]+\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$1/CHANGELOG.md" 2>/dev/null | head -n 1 || true
}

# README 剔除版本表数据行后的正文（版本字面值只在该数据行上受控豁免）
readme_body_without_version_table() {
  awk '!/^\| *[0-9]+\.[0-9]+\.[0-9]+ *\|/' "$1"
}

# 表格外正文中命中根 VERSION 字面值的行（空输出即通过）
readme_version_literal_hits() {
  readme_body_without_version_table "$1" | grep -Fn -- "$version_value" 2>/dev/null || true
}

# README「当前状态」段：已推 tag（sha / 日期 / 两次 CI run）与未分发两事实必须同现
readme_status_problems() { # $1 = root；通过时静默返回 0，失败时打印问题并返回 1
  local root="$1"
  local problems=""
  local line
  if [ ! -f "$root/README.md" ]; then
    printf '%s' "缺少 README.md"
    return 1
  fi
  line="$(grep -E '^当前状态：' "$root/README.md" | head -n 1 || true)"
  if [ -z "$line" ]; then
    printf '%s' "README 缺少「当前状态：」段"
    return 1
  fi
  printf '%s' "$line" | tr -d '[:space:]' | grep -Fq '已推tag' || problems="${problems} 当前状态段缺已推 tag;"
  printf '%s' "$line" | tr -d '[:space:]' | grep -Fq '未分发' || problems="${problems} 当前状态段缺未分发;"
  printf '%s' "$line" | grep -Fq '501ba9e' || problems="${problems} 当前状态段缺 tag 指向 sha 501ba9e;"
  printf '%s' "$line" | grep -Fq '2026-11-14' || problems="${problems} 当前状态段缺 tag 日期 2026-11-14;"
  printf '%s' "$line" | grep -Fq '43599497314' || problems="${problems} 当前状态段缺 ios CI run 43599497314;"
  printf '%s' "$line" | grep -Fq '43599497253' || problems="${problems} 当前状态段缺 android CI run 43599497253;"
  printf '%s' "$line" | grep -Eq '已发布|已分发|可下载|已上架' && problems="${problems} 当前状态段出现肯定式发布口径;"

  if [ -z "$problems" ]; then
    return 0
  fi
  printf '%s' "$problems"
  return 1
}

# README 当前状态段判红自检：删去已推 tag / 删去未分发 / 注入已分发都必须非零退出
readme_status_red_selftest_problems() { # $1 = root
  local root="$1"
  local problems=""
  local ts case_tmp
  ts="$(mktemp -d "${TMPDIR:-/tmp}/purepace-readme-status.XXXXXX")"
  if ! cp "$root/README.md" "$ts/README.md" 2>/dev/null; then
    rm -rf "$ts"
    printf '%s' "无法复制 README.md 到沙箱"
    return 1
  fi
  case_tmp="$ts/README.case"
  readme_status_problems "$ts" >/dev/null || problems="${problems} 未改动副本未判绿;"

  sed -E 's/已推 tag//' "$root/README.md" > "$case_tmp" && mv "$case_tmp" "$ts/README.md"
  readme_status_problems "$ts" >/dev/null && problems="${problems} 删去已推 tag 后未判红;"

  sed -E 's/尚未分发//' "$root/README.md" > "$case_tmp" && mv "$case_tmp" "$ts/README.md"
  readme_status_problems "$ts" >/dev/null && problems="${problems} 删去未分发后未判红;"

  sed -E 's/但尚未分发/已分发/' "$root/README.md" > "$case_tmp" && mv "$case_tmp" "$ts/README.md"
  readme_status_problems "$ts" >/dev/null && problems="${problems} 注入已分发后未判红;"

  rm -rf "$ts"
  if [ -z "$problems" ]; then
    return 0
  fi
  printf '%s' "$problems"
  return 1
}

# 三源一致：README 表首行 / CHANGELOG 首条 / VERSION（版本与日期都比对）
version_tri_source_problems() { # $1 = root；通过时静默返回 0，失败时打印问题并返回 1
  local root="$1"
  local problems=""
  local version row cl_heading entry
  local row_version row_date row_status row_link
  local cl_version cl_date

  if [ ! -f "$root/VERSION" ]; then
    printf '%s' "缺少 VERSION"
    return 1
  fi
  version="$(tr -d '\r\n' < "$root/VERSION")"

  if [ ! -f "$root/README.md" ]; then
    printf '%s' "缺少 README.md"
    return 1
  fi
  if ! grep -Fq '| 版本 | 日期 | 状态 | CHANGELOG |' "$root/README.md"; then
    problems="${problems} README 缺少四列表头 '| 版本 | 日期 | 状态 | CHANGELOG |';"
  fi
  row="$(readme_version_row "$root")"
  if [ -z "$row" ]; then
    problems="${problems} README 版本表缺少数据行;"
  else
    IFS='|' read -r _ row_version row_date row_status row_link _ <<< "$row"
    row_version="$(printf '%s' "$row_version" | tr -d ' ')"
    row_date="$(printf '%s' "$row_date" | tr -d ' ')"
    row_status="$(printf '%s' "$row_status" | tr -d ' ')"
    row_link="$(printf '%s' "$row_link" | tr -d ' ')"
    [ "$row_version" = "$version" ] || problems="${problems} README 表首行版本 '$row_version' 与 VERSION '$version' 不一致;"
    # 状态列：已推 tag 与未分发两事实必须同现（空格归一后判定），且不得出现肯定式发布口径。
    printf '%s' "$row_status" | tr -d '[:space:]' | grep -Fq '已推tag' || problems="${problems} README 表首行状态缺已推 tag;"
    printf '%s' "$row_status" | tr -d '[:space:]' | grep -Fq '未分发' || problems="${problems} README 表首行状态缺未分发;"
    printf '%s' "$row_status" | grep -Eq '已发布|已分发|可下载|已上架' && problems="${problems} README 表首行状态出现肯定式发布口径;"
    [ "$row_link" = '[CHANGELOG](./CHANGELOG.md)' ] || problems="${problems} README 表首行 CHANGELOG 列不是 './CHANGELOG.md' 相对链接;"
  fi

  if [ ! -f "$root/CHANGELOG.md" ]; then
    problems="${problems} 缺少 CHANGELOG.md;"
  else
    grep -Fq '# Changelog' "$root/CHANGELOG.md" || problems="${problems} CHANGELOG 缺少 '# Changelog';"
    grep -Fqi 'keep a changelog' "$root/CHANGELOG.md" || problems="${problems} CHANGELOG 未声明 Keep a Changelog 风格;"
    cl_heading="$(changelog_version_heading "$root")"
    if [ -z "$cl_heading" ]; then
      problems="${problems} CHANGELOG 缺少 '## [x.y.z] - YYYY-MM-DD' 首条版本标题;"
    else
      cl_version="$(sed -E 's/^## \[([0-9.]+)\] - .*$/\1/' <<< "$cl_heading")"
      cl_date="$(sed -E 's/^## \[[0-9.]+\] - (.*)$/\1/' <<< "$cl_heading")"
      [ "$cl_version" = "$version" ] || problems="${problems} CHANGELOG 首条版本 '$cl_version' 与 VERSION '$version' 不一致;"
      if [ -n "${row_date:-}" ] && [ "$cl_date" != "$row_date" ]; then
        problems="${problems} CHANGELOG 首条日期 '$cl_date' 与 README 表首行日期 '$row_date' 不一致;"
      fi
      entry="$(awk -v start="$cl_heading" '
        $0 == start { inside = 1; print; next }
        inside && /^## / { exit }
        inside { print }
      ' "$root/CHANGELOG.md")"
      printf '%s' "$entry" | grep -Fq '未分发' || problems="${problems} CHANGELOG 首条未标注未分发;"
      if printf '%s' "$entry" | grep -Eq '已发布|已分发|可分发'; then
        problems="${problems} CHANGELOG 首条出现肯定式已发布口径;"
      fi
    fi
  fi

  if [ -z "$problems" ]; then
    return 0
  fi
  printf '%s' "$problems"
  return 1
}

# 三源一致判红自检：版本漂移 / 日期漂移必须在临时副本上非零退出，未改动副本必须判绿
version_tri_source_red_selftest_problems() { # $1 = root
  local root="$1"
  local problems=""
  local ts
  ts="$(mktemp -d "${TMPDIR:-/tmp}/purepace-tri-source.XXXXXX")"
  if ! cp "$root/VERSION" "$root/README.md" "$root/CHANGELOG.md" "$ts/" 2>/dev/null; then
    rm -rf "$ts"
    printf '%s' "无法复制三源文件到沙箱"
    return 1
  fi
  version_tri_source_problems "$ts" >/dev/null || problems="${problems} 未改动副本未判绿;"

  awk -v v="9.9.9" 'BEGIN { done = 0 } /^\| *[0-9]+\.[0-9]+\.[0-9]+ *\|/ && !done { sub(/\| *[0-9]+\.[0-9]+\.[0-9]+ *\|/, "| " v " |"); done = 1 } { print }' \
    "$ts/README.md" > "$ts/README.tmp" && mv "$ts/README.tmp" "$ts/README.md"
  version_tri_source_problems "$ts" >/dev/null && problems="${problems} README 表首行版本漂移未判红;"

  cp "$root/README.md" "$ts/README.md"
  sed -E 's/\| *已推 tag、未分发 *\|/| 已推 tag |/' "$root/README.md" > "$ts/README.tmp" && mv "$ts/README.tmp" "$ts/README.md"
  version_tri_source_problems "$ts" >/dev/null && problems="${problems} README 表首行状态删去未分发未判红;"
  cp "$root/README.md" "$ts/README.md"

  awk -v v="9.9.9" 'BEGIN { done = 0 } /^## \[[0-9]+\.[0-9]+\.[0-9]+\] - / && !done { sub(/^## \[[0-9]+\.[0-9]+\.[0-9]+\]/, "## [" v "]"); done = 1 } { print }' \
    "$ts/CHANGELOG.md" > "$ts/CHANGELOG.tmp" && mv "$ts/CHANGELOG.tmp" "$ts/CHANGELOG.md"
  version_tri_source_problems "$ts" >/dev/null && problems="${problems} CHANGELOG 首条版本漂移未判红;"

  cp "$root/CHANGELOG.md" "$ts/CHANGELOG.md"
  awk 'BEGIN { done = 0 } /^## \[[0-9]+\.[0-9]+\.[0-9]+\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$/ && !done { sub(/- [0-9]{4}-[0-9]{2}-[0-9]{2}$/, "- 1999-01-01"); done = 1 } { print }' \
    "$ts/CHANGELOG.md" > "$ts/CHANGELOG.tmp" && mv "$ts/CHANGELOG.tmp" "$ts/CHANGELOG.md"
  version_tri_source_problems "$ts" >/dev/null && problems="${problems} CHANGELOG 首条日期漂移未判红;"

  rm -rf "$ts"
  if [ -z "$problems" ]; then
    return 0
  fi
  printf '%s' "$problems"
  return 1
}

# CHANGELOG 首条状态行事实：已推 tag + tag sha + 日期 + 未分发 + 声明保留，全文禁词零命中
changelog_status_facts_problems() { # $1 = root；通过时静默返回 0，失败时打印问题并返回 1
  local root="$1"
  local problems=""
  local heading entry status_line cl_date tag_sha
  if [ ! -f "$root/CHANGELOG.md" ]; then
    printf '%s' "缺少 CHANGELOG.md"
    return 1
  fi
  heading="$(changelog_version_heading "$root")"
  if [ -z "$heading" ]; then
    printf '%s' "CHANGELOG 缺少 '## [x.y.z] - YYYY-MM-DD' 首条版本标题"
    return 1
  fi
  cl_date="$(sed -E 's/^## \[[0-9.]+\] - (.*)$/\1/' <<< "$heading")"
  entry="$(awk -v start="$heading" '
    $0 == start { inside = 1; print; next }
    inside && /^## / { exit }
    inside { print }
  ' "$root/CHANGELOG.md")"
  status_line="$(printf '%s\n' "$entry" | grep -F '状态：' | head -n 1 || true)"
  if [ -z "$status_line" ]; then
    printf '%s' "CHANGELOG 首条缺少状态行"
    return 1
  fi
  printf '%s' "$status_line" | tr -d ' ' | grep -Fq '已推tag' || problems="${problems} CHANGELOG 首条状态行缺已推 tag;"
  printf '%s' "$status_line" | tr -d ' ' | grep -Fq '未分发' || problems="${problems} CHANGELOG 首条状态行缺未分发;"
  printf '%s' "$status_line" | grep -Fq "$cl_date" || problems="${problems} CHANGELOG 首条状态行缺标题日期 ${cl_date};"
  tag_sha="$(printf '%s' "$status_line" | grep -Eo '[0-9a-f]{7,40}' | head -n 1 || true)"
  [ -n "$tag_sha" ] || problems="${problems} CHANGELOG 首条状态行缺 tag sha;"
  printf '%s' "$status_line" | grep -Fq '本条目只陈述已交付事实' || problems="${problems} CHANGELOG 首条状态行缺「只陈述已交付事实」声明;"
  printf '%s' "$status_line" | grep -Fq '不构成任何发布声明' || problems="${problems} CHANGELOG 首条状态行缺「不构成任何发布声明」声明;"
  if grep -Eiq '已发布|已分发|可分发|已上传 ?TestFlight|shipped|released to testflight' "$root/CHANGELOG.md"; then
    problems="${problems} CHANGELOG 全文出现肯定式发布禁词;"
  fi
  if [ -z "$problems" ]; then
    return 0
  fi
  printf '%s' "$problems"
  return 1
}

# README 版本表首行与 CHANGELOG 首条状态行同口径：两侧独立取证后交叉比对 tag sha 与日期
changelog_status_parity_problems() { # $1 = root；通过时静默返回 0，失败时打印问题并返回 1
  local root="$1"
  local problems=""
  local heading entry status_line cl_date cl_sha
  local row row_version row_date row_status row_link readme_status_line readme_date readme_status readme_sha
  local _unused
  if [ ! -f "$root/README.md" ] || [ ! -f "$root/CHANGELOG.md" ]; then
    printf '%s' "缺少 README.md 或 CHANGELOG.md"
    return 1
  fi
  heading="$(changelog_version_heading "$root")"
  if [ -z "$heading" ]; then
    printf '%s' "CHANGELOG 缺少 '## [x.y.z] - YYYY-MM-DD' 首条版本标题"
    return 1
  fi
  cl_date="$(sed -E 's/^## \[[0-9.]+\] - (.*)$/\1/' <<< "$heading")"
  entry="$(awk -v start="$heading" '
    $0 == start { inside = 1; print; next }
    inside && /^## / { exit }
    inside { print }
  ' "$root/CHANGELOG.md")"
  status_line="$(printf '%s\n' "$entry" | grep -F '状态：' | head -n 1 || true)"
  if [ -z "$status_line" ]; then
    printf '%s' "CHANGELOG 首条缺少状态行"
    return 1
  fi
  cl_sha="$(printf '%s' "$status_line" | grep -Eo '[0-9a-f]{7,40}' | head -n 1 || true)"

  row="$(readme_version_row "$root")"
  if [ -z "$row" ]; then
    printf '%s' "README 缺少版本表首行"
    return 1
  fi
  IFS='|' read -r _unused row_version row_date row_status row_link _unused <<< "$row"
  readme_date="$(printf '%s' "$row_date" | tr -d ' ')"
  readme_status="$(printf '%s' "$row_status" | tr -d ' ')"
  readme_status_line="$(grep -E '^当前状态：' "$root/README.md" | head -n 1 || true)"
  readme_sha="$(printf '%s' "$readme_status_line" | grep -Eo '[0-9a-f]{7,40}' | head -n 1 || true)"

  # CHANGELOG 侧事实
  printf '%s' "$status_line" | tr -d ' ' | grep -Fq '已推tag' || problems="${problems} CHANGELOG 状态行缺已推 tag;"
  printf '%s' "$status_line" | tr -d ' ' | grep -Fq '未分发' || problems="${problems} CHANGELOG 状态行缺未分发;"
  printf '%s' "$status_line" | grep -Fq "$cl_date" || problems="${problems} CHANGELOG 状态行缺标题日期 ${cl_date};"
  [ -n "$cl_sha" ] || problems="${problems} CHANGELOG 状态行缺 tag sha;"
  printf '%s' "$status_line" | grep -Eiq '已发布|已分发|可分发|已上传 ?TestFlight|shipped|released to testflight' && problems="${problems} CHANGELOG 状态行出现肯定式发布禁词;"

  # README 侧事实（独立取值，不复用 CHANGELOG 结果）
  printf '%s' "$readme_status" | grep -Fq '已推tag' || problems="${problems} README 表首行状态列缺已推 tag;"
  printf '%s' "$readme_status" | grep -Fq '未分发' || problems="${problems} README 表首行状态列缺未分发;"
  [ -n "$readme_sha" ] || problems="${problems} README 当前状态段缺 tag sha;"

  # 交叉比对
  [ "$readme_date" = "$cl_date" ] || problems="${problems} README 表首行日期 '${readme_date}' 与 CHANGELOG 标题日期 '${cl_date}' 不一致;"
  if [ -n "$cl_sha" ] && [ -n "$readme_sha" ] && [ "$cl_sha" != "$readme_sha" ]; then
    problems="${problems} CHANGELOG tag sha '${cl_sha}' 与 README '${readme_sha}' 不一致;"
  fi

  if [ -z "$problems" ]; then
    return 0
  fi
  printf '%s' "$problems"
  return 1
}

# 同口径判红自检：未改动副本必须判绿；三项反例必须判红
changelog_status_parity_red_selftest_problems() { # $1 = root
  local root="$1"
  local problems=""
  local ts readme_sha
  ts="$(mktemp -d "${TMPDIR:-/tmp}/purepace-changelog-parity.XXXXXX")"
  if ! cp "$root/README.md" "$root/CHANGELOG.md" "$ts/" 2>/dev/null; then
    rm -rf "$ts"
    printf '%s' "无法复制 README.md / CHANGELOG.md 到沙箱"
    return 1
  fi
  changelog_status_parity_problems "$ts" >/dev/null || problems="${problems} 未改动副本未判绿;"

  awk 'BEGIN { done = 0 } !done && index($0, "状态：") == 1 { print "状态：**未发布（候选）**。本条目只陈述已交付事实，不构成任何发布声明。"; done = 1; next } { print }' \
    "$ts/CHANGELOG.md" > "$ts/CHANGELOG.tmp" && mv "$ts/CHANGELOG.tmp" "$ts/CHANGELOG.md"
  changelog_status_parity_problems "$ts" >/dev/null && problems="${problems} 状态行改回未发布（候选）未判红;"

  cp "$root/CHANGELOG.md" "$ts/CHANGELOG.md"
  awk 'BEGIN { done = 0 } !done && index($0, "状态：") == 1 { sub(/状态：/, "状态：已分发 "); done = 1 } { print }' \
    "$ts/CHANGELOG.md" > "$ts/CHANGELOG.tmp" && mv "$ts/CHANGELOG.tmp" "$ts/CHANGELOG.md"
  changelog_status_parity_problems "$ts" >/dev/null && problems="${problems} 状态行注入已分发未判红;"

  cp "$root/CHANGELOG.md" "$ts/CHANGELOG.md"
  readme_sha="$(grep -E '^当前状态：' "$ts/README.md" | head -n 1 | grep -Eo '[0-9a-f]{7,40}' | head -n 1 || true)"
  if [ -z "$readme_sha" ]; then
    problems="${problems} README 未找到 tag sha，无法构造删 sha 反例;"
  else
    awk -v s="$readme_sha" '{ gsub(s, "", $0); print }' "$ts/README.md" > "$ts/README.tmp" && mv "$ts/README.tmp" "$ts/README.md"
    changelog_status_parity_problems "$ts" >/dev/null && problems="${problems} README 删去 tag sha 未判红;"
  fi

  rm -rf "$ts"
  if [ -z "$problems" ]; then
    return 0
  fi
  printf '%s' "$problems"
  return 1
}

# release notes：结构 / 未发布口径 / 三条已知限制 / Build reproducibility 事实保留
release_notes_section() { # $1 文件，$2 精确标题行
  awk -v heading="$2" '$0 == heading { inside = 1; next } inside && /^## / { exit } inside && /^<details>/ { exit } inside { print }' "$1"
}

release_notes_problems() { # $1 = root
  local root="$1"
  local problems=""
  local version notes limitations count zh zh_count covered
  version="$(tr -d '\r\n' < "$root/VERSION" 2>/dev/null || true)"
  notes="$root/docs/release/release-notes-${version}.md"
  if [ ! -f "$notes" ]; then
    printf '%s' "缺少 docs/release/release-notes-${version}.md"
    return 1
  fi

  local heading
  for heading in "What's in this release" "What's covered" "Privacy" "Known limitations"; do
    grep -Fxq "## ${heading}" "$notes" || problems="${problems} 缺少英文节 '## ${heading}';"
  done
  grep -Fq '<summary>简体中文</summary>' "$notes" || problems="${problems} 缺少 zh-CN 折叠段 <summary>简体中文</summary>;"

  # 英文 Status 段：已推 tag（sha / 日期 / 两次 CI run）与未分发两事实必须同现。
  local status_line
  status_line="$(grep -E '^> Status:' "$notes" | head -n 1 || true)"
  if [ -z "$status_line" ]; then
    problems="${problems} 缺少英文 '> Status:' 段;"
  else
    status_line="$(printf '%s' "$status_line" | tr -d '`')"
    printf '%s' "$status_line" | grep -Fqi "tag v${version}" || problems="${problems} Status 段缺 tag v${version};"
    printf '%s' "$status_line" | grep -Fq '501ba9e' || problems="${problems} Status 段缺 tag sha 501ba9e;"
    printf '%s' "$status_line" | grep -Fq '2026-11-14' || problems="${problems} Status 段缺 tag 日期 2026-11-14;"
    printf '%s' "$status_line" | grep -Fq '43599497314' || problems="${problems} Status 段缺 ios CI run 43599497314;"
    printf '%s' "$status_line" | grep -Fq '43599497253' || problems="${problems} Status 段缺 android CI run 43599497253;"
    printf '%s' "$status_line" | grep -Fqi 'not distributed' || problems="${problems} Status 段缺 not distributed;"
    printf '%s' "$status_line" | grep -Fqi 'no testflight' || problems="${problems} Status 段缺 no TestFlight;"
    printf '%s' "$status_line" | grep -Fqi 'no install package' || problems="${problems} Status 段缺 no install package;"
    printf '%s' "$status_line" | grep -Fqi 'no github release' || problems="${problems} Status 段缺 no GitHub Release;"
  fi

  # 禁词零命中：先剔除否定式，再要求肯定式零命中。
  local stripped
  stripped="$(sed -E \
    -e 's/[Nn]ot (yet )?(released|shipped|distributed|distributable)/NEG/g' \
    -e 's/尚未发布//g; s/未发布//g; s/尚未分发//g; s/未分发//g; s/不可分发//g; s/未上传//g; s/未提供安装包//g; s/未建 [Gg]it[Hh]ub [Rr]elease//g' \
    -e 's/未上架//g' "$notes")"
  if printf '%s' "$stripped" | grep -Eqi 'released|shipped|distributed|distributable|available for download|live on store|已发布|已分发|可下载|已上架|可分发'; then
    problems="${problems} 出现肯定式已发布 / 已分发 / 可下载 / 已上架口径;"
  fi

  limitations="$(release_notes_section "$notes" '## Known limitations')"
  count="$(printf '%s\n' "$limitations" | grep -Ec '^[0-9]+\. ' || true)"
  [ "$count" = "3" ] || problems="${problems} Known limitations 条目数为 ${count}（应为 3）;"
  printf '%s' "$limitations" | grep -Fq 'zh-Hans' || problems="${problems} Known limitations 缺 zh-Hans 单语限制;"
  printf '%s' "$limitations" | grep -Fq 'pending: 待人现场' || problems="${problems} Known limitations 缺 pending: 待人现场;"
  printf '%s' "$limitations" | grep -Fq 'docs/device-manual-acceptance.md' || problems="${problems} Known limitations 缺真机验收文档指针;"
  printf '%s' "$limitations" | grep -Fq '20pt' || problems="${problems} Known limitations 缺 Dynamic Type 固定 20pt 事实;"

  covered="$(release_notes_section "$notes" '## What'"'"'s covered')"
  printf '%s' "$covered" | grep -Fq 'Build reproducibility' || problems="${problems} What's covered 缺 Build reproducibility 段;"
  printf '%s' "$covered" | grep -Fq '57' || problems="${problems} Build reproducibility 段缺 57 处派生路径事实;"
  printf '%s' "$covered" | grep -Fq 'LC_UUID' || problems="${problems} Build reproducibility 段缺 LC_UUID 随机事实;"

  zh="$(sed -n '/<summary>简体中文<\/summary>/,$p' "$notes")"
  printf '%s' "$zh" | grep -Fq '已推 tag' || problems="${problems} zh-CN 段缺已推 tag 表述;"
  printf '%s' "$zh" | grep -Fq '尚未分发' || problems="${problems} zh-CN 段缺尚未分发表述;"
  printf '%s' "$zh" | grep -Fq '501ba9e' || problems="${problems} zh-CN 段缺 tag sha 501ba9e;"
  printf '%s' "$zh" | grep -Fq '2026-11-14' || problems="${problems} zh-CN 段缺 tag 日期 2026-11-14;"
  printf '%s' "$zh" | grep -Fq '43599497314' || problems="${problems} zh-CN 段缺 ios CI run 43599497314;"
  printf '%s' "$zh" | grep -Fq '43599497253' || problems="${problems} zh-CN 段缺 android CI run 43599497253;"
  printf '%s' "$zh" | grep -Fq '未上传 TestFlight' || problems="${problems} zh-CN 段缺未上传 TestFlight;"
  printf '%s' "$zh" | grep -Fq '未提供安装包' || problems="${problems} zh-CN 段缺未提供安装包;"
  printf '%s' "$zh" | grep -Fq '未建 GitHub Release' || problems="${problems} zh-CN 段缺未建 GitHub Release;"
  printf '%s' "$zh" | grep -Fq '隐私' || problems="${problems} zh-CN 段缺隐私节;"
  printf '%s' "$zh" | grep -Fq '已知限制' || problems="${problems} zh-CN 段缺已知限制节;"
  zh_count="$(printf '%s\n' "$zh" | grep -Ec '^[0-9]+\. ' || true)"
  [ "$zh_count" = "3" ] || problems="${problems} zh-CN 已知限制条目数为 ${zh_count}（应为 3）;"

  if [ -z "$problems" ]; then
    return 0
  fi
  printf '%s' "$problems"
  return 1
}

# release notes 口径判红自检：未改动副本必须判绿；注入肯定式 shipped / Released、
# 删去未分发事实三类反例必须非零退出
release_notes_wording_red_selftest_problems() { # $1 = root
  local root="$1"
  local version notes ts target case_tmp problems=""
  version="$(tr -d '\r\n' < "$root/VERSION" 2>/dev/null || true)"
  notes="$root/docs/release/release-notes-${version}.md"
  if [ ! -f "$notes" ]; then
    printf '%s' "缺少 release notes，无法自检"
    return 1
  fi
  ts="$(mktemp -d "${TMPDIR:-/tmp}/purepace-notes.XXXXXX")"
  mkdir -p "$ts/docs/release"
  target="$ts/docs/release/release-notes-${version}.md"
  case_tmp="$ts/notes.case"
  cp "$root/VERSION" "$ts/VERSION"

  cp "$notes" "$target"
  release_notes_problems "$ts" >/dev/null || problems="${problems} 未改动副本未判绿;"

  cp "$notes" "$target"
  printf '\nThis build was shipped.\n' >> "$target"
  release_notes_problems "$ts" >/dev/null && problems="${problems} 注入肯定式 shipped 后未判红;"

  cp "$notes" "$target"
  printf '\nReleased to TestFlight.\n' >> "$target"
  release_notes_problems "$ts" >/dev/null && problems="${problems} 注入 Released to TestFlight 后未判红;"

  sed -E -e 's/\*\*Not distributed\*\*:.*$//' -e 's/；\*\*尚未分发\*\*：.*$//' "$notes" > "$case_tmp" && mv "$case_tmp" "$target"
  release_notes_problems "$ts" >/dev/null && problems="${problems} 删去未分发事实后未判红;"

  rm -rf "$ts"
  if [ -z "$problems" ]; then
    return 0
  fi
  printf '%s' "$problems"
  return 1
}

# release.yml：存在性 + YAML 解析 + 顶层 name / on / jobs 非空
workflow_parse_problems() { # $1 = root
  local wf="$1/.github/workflows/release.yml"
  if [ ! -f "$wf" ]; then
    printf '%s' "缺少 .github/workflows/release.yml"
    return 1
  fi
  if ! command -v ruby >/dev/null 2>&1; then
    printf '%s' "缺少 ruby，无法解析 YAML（禁止跳过）"
    return 1
  fi
  local out
  out="$(ruby -ryaml - "$wf" <<'RUBY'
# encoding: utf-8
require 'yaml'
raw = File.read(ARGV[0], encoding: 'UTF-8')
doc = begin
  YAML.respond_to?(:unsafe_load) ? YAML.unsafe_load(raw) : YAML.load(raw)
rescue StandardError => e
  puts "YAML 解析失败: #{e.message}"
  exit 1
end
unless doc.is_a?(Hash)
  puts '顶层不是映射'
  exit 1
end
problems = []
problems << '顶层 name 为空' if doc['name'].to_s.strip.empty?
on_key = doc.key?('on') ? 'on' : (doc.key?(true) ? true : nil)
on_value = on_key.nil? ? nil : doc[on_key]
problems << '顶层 on 为空' unless on_value.is_a?(Hash) && !on_value.empty?
problems << '顶层 jobs 为空' unless doc['jobs'].is_a?(Hash) && !doc['jobs'].empty?
puts problems.join('; ')
exit(problems.empty? ? 0 : 1)
RUBY
)" && return 0
  printf '%s' "$out"
  return 1
}

# release.yml：on 只含 workflow_dispatch
workflow_trigger_problems() { # $1 = root
  local wf="$1/.github/workflows/release.yml"
  if [ ! -f "$wf" ]; then
    printf '%s' "缺少 .github/workflows/release.yml"
    return 1
  fi
  local out
  out="$(ruby -ryaml - "$wf" <<'RUBY'
# encoding: utf-8
require 'yaml'
raw = File.read(ARGV[0], encoding: 'UTF-8')
doc = begin
  YAML.respond_to?(:unsafe_load) ? YAML.unsafe_load(raw) : YAML.load(raw)
rescue StandardError => e
  puts "YAML 解析失败: #{e.message}"
  exit 1
end
on_key = doc.is_a?(Hash) && doc.key?('on') ? 'on' : (doc.is_a?(Hash) && doc.key?(true) ? true : nil)
on_value = on_key.nil? ? nil : doc[on_key]
triggers = on_value.is_a?(Hash) ? on_value.keys.map(&:to_s).sort : (on_value.is_a?(String) ? [on_value] : [])
exit 0 if triggers == ['workflow_dispatch']
puts "on 触发为 #{triggers.join(',')}，必须只含 workflow_dispatch"
exit 1
RUBY
)" && return 0
  printf '%s' "$out"
  return 1
}

# release.yml：tag 由 VERSION 派生、dispatch 可覆盖、形态校验、零版本字面值
workflow_tag_problems() { # $1 = root
  local wf="$1/.github/workflows/release.yml"
  local problems=""
  if [ ! -f "$wf" ]; then
    printf '%s' "缺少 .github/workflows/release.yml"
    return 1
  fi
  grep -Eq 'v\$\((bash )?scripts/version\.sh\)' "$wf" || problems="${problems} 缺 VERSION 派生（v + scripts/version.sh 输出）;"
  grep -Fq 'inputs.tag' "$wf" || problems="${problems} 缺 workflow_dispatch inputs.tag 覆盖;"
  grep -Fq '^v[0-9]+\.[0-9]+\.[0-9]+$' "$wf" || problems="${problems} 缺 tag 形态校验 ^v[0-9]+\.[0-9]+\.[0-9]+$;"
  local literal_hits
  literal_hits="$(grep -En '[0-9]+\.[0-9]+\.[0-9]+' "$wf" || true)"
  [ -z "$literal_hits" ] || problems="${problems} 出现版本字面值: ${literal_hits};"
  if [ -z "$problems" ]; then
    return 0
  fi
  printf '%s' "$problems"
  return 1
}

# release.yml：只 push tag refspec、最小权限、无凭据与分发调用
workflow_push_problems() { # $1 = root
  local wf="$1/.github/workflows/release.yml"
  local problems=""
  if [ ! -f "$wf" ]; then
    printf '%s' "缺少 .github/workflows/release.yml"
    return 1
  fi
  local bad_push flag_hits forbidden_hits
  bad_push="$(awk '/^[[:space:]]*#/ { next } /git push/ && $0 !~ /refs\/tags\// { print NR": "$0 }' "$wf")"
  [ -z "$bad_push" ] || problems="${problems} 存在非 tag refspec 的 push: ${bad_push};"
  grep -Fq 'git push origin "refs/tags/' "$wf" || problems="${problems} 缺显式 tag refspec push;"
  flag_hits="$(grep -En -- '--tags|--force|push -f' "$wf" || true)"
  [ -z "$flag_hits" ] || problems="${problems} 出现禁止的 push 参数: ${flag_hits};"
  forbidden_hits="$(grep -En 'secrets\.|TESTFLIGHT|fastlane|altool|app-store-connect|transporter|notarytool' "$wf" || true)"
  [ -z "$forbidden_hits" ] || problems="${problems} 出现凭据或分发调用: ${forbidden_hits};"
  local perm_out
  perm_out="$(ruby -ryaml - "$wf" <<'RUBY'
# encoding: utf-8
require 'yaml'
raw = File.read(ARGV[0], encoding: 'UTF-8')
doc = begin
  YAML.respond_to?(:unsafe_load) ? YAML.unsafe_load(raw) : YAML.load(raw)
rescue StandardError => e
  puts "YAML 解析失败: #{e.message}"
  exit 1
end
perms = doc.is_a?(Hash) ? doc['permissions'] : nil
exit 0 if perms.is_a?(Hash) && perms.size == 1 && perms['contents'].to_s == 'write'
puts "permissions 必须只含 contents: write，实际 #{perms.inspect}"
exit 1
RUBY
)" && perm_out=""
  [ -z "$perm_out" ] || problems="${problems} ${perm_out};"
  if [ -z "$problems" ]; then
    return 0
  fi
  printf '%s' "$problems"
  return 1
}

# release.yml 结构判红自检：删派生 / 注入字面值 / 加分支 push 三类反例必须判红
release_workflow_red_selftest_problems() { # $1 = root
  local root="$1"
  local wf="$1/.github/workflows/release.yml"
  local problems=""
  if [ ! -f "$wf" ]; then
    printf '%s' "缺少 .github/workflows/release.yml"
    return 1
  fi
  local ws probe
  ws="$(mktemp -d "${TMPDIR:-/tmp}/purepace-release-wf.XXXXXX")"
  mkdir -p "$ws/.github/workflows"
  probe="$ws/.github/workflows/release.yml"

  cp "$wf" "$probe"
  workflow_tag_problems "$ws" >/dev/null || problems="${problems} 未改动副本未判绿;"

  { grep -v 'scripts/version.sh' "$wf" || true; } > "$probe"
  workflow_tag_problems "$ws" >/dev/null && problems="${problems} 删除 VERSION 派生后未判红;"

  cp "$wf" "$probe"
  printf '%s\n' '          echo "9.9.9"' >> "$probe"
  workflow_tag_problems "$ws" >/dev/null && problems="${problems} 注入硬编码版本后未判红;"

  cp "$wf" "$probe"
  printf '%s\n' '          git push origin "refs/heads/main"' >> "$probe"
  workflow_push_problems "$ws" >/dev/null && problems="${problems} 加入分支 push 后未判红;"

  rm -rf "$ws"
  if [ -z "$problems" ]; then
    return 0
  fi
  printf '%s' "$problems"
  return 1
}

# --------------------------------------------------- 无硬编码版本字面值
if [ -z "$version_value" ]; then
  fail "ac-no-hardcoded-version" "VERSION 不可用，无法校验字面值"
else
  problems=""
  readme_hits="$(readme_version_literal_hits README.md)"
  [ -z "$readme_hits" ] || problems="${problems} README 版本表之外出现版本字面值 '$version_value': ${readme_hits};"
  script_hits="$(grep -Fn -- "$version_value" scripts/*.sh 2>/dev/null || true)"
  [ -z "$script_hits" ] || problems="${problems} scripts/*.sh 出现版本字面值 '$version_value': $(printf '%s' "$script_hits" | tr '\n' ' ');"
  # 反例自检：版本表数据行受控豁免，表格外写入字面值必须仍判红。
  literal_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-literal.XXXXXX")"
  cp README.md "$literal_sandbox/README.md"
  printf '\n版本字面值回归探针：%s\n' "$version_value" >> "$literal_sandbox/README.md"
  if [ -z "$(readme_version_literal_hits "$literal_sandbox/README.md")" ]; then
    problems="${problems} 表格外写入字面值未判红（豁免范围过宽）;"
  fi
  rm -rf "$literal_sandbox"
  if [ -z "$problems" ]; then
    pass "ac-no-hardcoded-version"
  else
    fail "ac-no-hardcoded-version" "$problems"
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

# -------------------------------------------------- README 当前状态段口径
if readme_status_out="$(readme_status_problems "$repo_root")"; then
  pass "ac-readme-status-tag-pushed-not-distributed"
else
  fail "ac-readme-status-tag-pushed-not-distributed" "$readme_status_out"
fi

if readme_status_red_out="$(readme_status_red_selftest_problems "$repo_root")"; then
  pass "ac-readme-status-red-selftest"
else
  fail "ac-readme-status-red-selftest" "$readme_status_red_out"
fi

# -------------------------------------------------- 版本三源一致与判红自检
if tri_out="$(version_tri_source_problems "$repo_root")"; then
  pass "ac-version-tri-source-consistency"
else
  fail "ac-version-tri-source-consistency" "$tri_out"
fi

if tri_red_out="$(version_tri_source_red_selftest_problems "$repo_root")"; then
  pass "ac-version-tri-source-status-red-selftest"
else
  fail "ac-version-tri-source-status-red-selftest" "$tri_red_out"
fi

# ------------------------------------------------ CHANGELOG 首条状态行与 README 同口径
if changelog_status_out="$(changelog_status_facts_problems "$repo_root")"; then
  pass "ac-changelog-status-tag-pushed-not-distributed"
else
  fail "ac-changelog-status-tag-pushed-not-distributed" "$changelog_status_out"
fi

if changelog_parity_out="$(changelog_status_parity_problems "$repo_root")"; then
  pass "ac-changelog-status-parity-with-readme"
else
  fail "ac-changelog-status-parity-with-readme" "$changelog_parity_out"
fi

if changelog_parity_red_out="$(changelog_status_parity_red_selftest_problems "$repo_root")"; then
  pass "ac-changelog-status-red-selftest"
else
  fail "ac-changelog-status-red-selftest" "$changelog_parity_red_out"
fi

# ------------------------------------------------------- release notes 口径
if notes_out="$(release_notes_problems "$repo_root")"; then
  pass "ac-release-notes-tag-pushed-not-distributed"
else
  fail "ac-release-notes-tag-pushed-not-distributed" "$notes_out"
fi

if notes_red_out="$(release_notes_wording_red_selftest_problems "$repo_root")"; then
  pass "ac-release-wording-red-selftest"
else
  fail "ac-release-wording-red-selftest" "$notes_red_out"
fi

# --------------------------------------------- .github/workflows/release.yml
if wf_parse_out="$(workflow_parse_problems "$repo_root")"; then
  pass "ac-release-workflow-exists-parses"
else
  fail "ac-release-workflow-exists-parses" "$wf_parse_out"
fi

if wf_trigger_out="$(workflow_trigger_problems "$repo_root")"; then
  pass "ac-release-workflow-dispatch-only"
else
  fail "ac-release-workflow-dispatch-only" "$wf_trigger_out"
fi

if wf_tag_out="$(workflow_tag_problems "$repo_root")"; then
  pass "ac-release-workflow-tag-derived"
else
  fail "ac-release-workflow-tag-derived" "$wf_tag_out"
fi

if wf_push_out="$(workflow_push_problems "$repo_root")"; then
  pass "ac-release-workflow-no-branch-push"
else
  fail "ac-release-workflow-no-branch-push" "$wf_push_out"
fi

if wf_red_out="$(release_workflow_red_selftest_problems "$repo_root")"; then
  pass "ac-release-workflow-structure-red-selftest"
else
  fail "ac-release-workflow-structure-red-selftest" "$wf_red_out"
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

# ----------------------------- 测试稳定性约定（iOS UI 腿）文本存在性防回归
if [ ! -f AGENTS.md ]; then
  fail "ac-agents-test-stability" "仓库根缺少 AGENTS.md"
else
  problems=""
  stability="$(printf '%s' "$(section_body AGENTS.md '测试稳定性约定')")"
  if [ -z "$stability" ]; then
    problems="$problems 测试稳定性约定节为空;"
  else
    for needle in "禁止墙钟依赖断言" "状态判据" "isHittable" "sleep" "≤600" "拆分≠放宽" "continue-on-error"; do
      if ! grep -Fq -- "$needle" <<< "$stability"; then
        problems="$problems 缺少 '$needle';"
      fi
    done
  fi
  if [ -z "$problems" ]; then
    pass "ac-agents-test-stability"
  else
    fail "ac-agents-test-stability" "$problems"
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
