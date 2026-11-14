#!/usr/bin/env bash
# TestFlight 内部测试者分配：ASC REST 只读解析 App 与内部 betaGroup，
# 必要时创建 betaTester，再把关系写入该内部组。
# 凭据只从 ASC_KEY_PATH / ASC_KEY_ID / ASC_ISSUER_ID 读取；JWT 只在内存，不落盘不打印。
# DRY_RUN=1 只回显脱敏步骤计划、不触碰网络；只读/权限失败即停手并原文报告 HTTP 状态与 errors。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/testflight-tester.sh [--help]

把 TESTFLIGHT_TESTER_EMAIL 加入该 App 的内部 TestFlight 测试组（不触发 Beta App Review、不外邀）：
  1. 只读 GET /v1/apps?filter[bundleId]=... 解析 App
  2. 只读 GET /v1/betaGroups?filter[app]=...&filter[isInternalGroup]=true 选中内部组
  3. 只读 GET /v1/betaTesters?filter[email]=... 判断测试者是否已存在
  4. 必要时 POST /v1/betaTesters 创建测试者
  5. POST /v1/betaGroups/{id}/relationships/betaTesters 建立关系

任一只读或权限请求非 2xx 立即停手，原文输出 HTTP 状态码与 errors[].code / title，不重试、不换端点、不写任何关系。

环境变量:
  ASC_KEY_PATH             App Store Connect API 私钥 .p8 绝对路径（必须放在仓库外）
  ASC_KEY_ID               API Key ID
  ASC_ISSUER_ID            API Issuer ID
  TESTFLIGHT_TESTER_EMAIL  要加入内部组的测试者邮箱
  BUNDLE_ID                App bundle id，缺省 sh.munk.purepace
  DRY_RUN=1                不要求凭据与邮箱，只回显脱敏步骤计划；不发起任何网络调用，退出 0

JWT 由 openssl 用私钥在内存签发，不打印、不落盘；脚本不写 .p8 / .env / 凭据文件。

选项:
  -h, --help   显示本帮助并退出 0

退出码:
  0  内部测试者分配完成，或 DRY_RUN=1 回显成功
  1  凭据缺失/私钥缺失、只读或权限失败、API 返回异常
  2  参数非法或 TESTFLIGHT_TESTER_EMAIL 缺失/非法
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
    echo "testflight-tester: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "testflight-tester: 只接受一个参数（使用 --help 查看用法）" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

dry_run="${DRY_RUN:-0}"
bundle_id="${BUNDLE_ID:-sh.munk.purepace}"
tester_email="${TESTFLIGHT_TESTER_EMAIL:-}"

if [ "$dry_run" = "1" ]; then
  cat <<'DRYRUN'
info: [DRY_RUN] GET  /v1/apps?filter[bundleId]=${BUNDLE_ID}（只读解析 App）
info: [DRY_RUN] GET  /v1/betaGroups?filter[app]=$APP_ID&filter[isInternalGroup]=true（只读选中内部组）
info: [DRY_RUN] GET  /v1/betaTesters?filter[email]=${TESTFLIGHT_TESTER_EMAIL}（只读判断是否存在）
info: [DRY_RUN] POST /v1/betaTesters（仅在测试者不存在时创建）
info: [DRY_RUN] POST /v1/betaGroups/$BETA_GROUP_ID/relationships/betaTesters（只写内部组关系）
info: [DRY_RUN] 凭据只从 $ASC_KEY_PATH / $ASC_KEY_ID / $ASC_ISSUER_ID 读取；JWT 只在内存且不打印
info: [DRY_RUN] 不触发 Beta App Review、不向外部组邀请
info: [DRY_RUN] 以上请求未执行（无网络访问）
DRYRUN
  exit 0
fi

missing_credentials=""
for var in ASC_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID; do
  if [ -z "$(printenv "$var" 2>/dev/null || true)" ]; then
    missing_credentials="$missing_credentials $var"
  fi
done
if [ -n "$missing_credentials" ]; then
  for var in $missing_credentials; do
    printf 'testflight-tester: 缺少环境变量 %s\n' "$var" >&2
  done
  exit 1
fi

if [ ! -f "$ASC_KEY_PATH" ]; then
  printf 'testflight-tester: 私钥文件不存在（ASC_KEY_PATH）\n' >&2
  exit 1
fi

case "$tester_email" in
  '')
    echo "testflight-tester: 缺少环境变量 TESTFLIGHT_TESTER_EMAIL" >&2
    exit 2
    ;;
  *[[:space:]]*)
    echo "testflight-tester: TESTFLIGHT_TESTER_EMAIL 含空白字符" >&2
    exit 2
    ;;
  *@*)
    ;;
  *)
    echo "testflight-tester: TESTFLIGHT_TESTER_EMAIL 不是合法邮箱" >&2
    exit 2
    ;;
esac

command -v python3 >/dev/null 2>&1 || {
  echo "testflight-tester: 缺少 python3，无法解析 ASC API 响应" >&2
  exit 1
}
command -v openssl >/dev/null 2>&1 || {
  echo "testflight-tester: 缺少 openssl，无法签发 ASC API JWT" >&2
  exit 1
}

api_base="https://api.appstoreconnect.apple.com"
response_dir="$(mktemp -d "${TMPDIR:-/tmp}/purepace-asc-response.XXXXXX")"
trap 'rm -rf "$response_dir"' EXIT

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

base64url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

issue_jwt() {
  local now exp header payload signing_input signature
  now="$(date +%s)"
  exp="$((now + 600))"
  header="$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$(json_escape "$ASC_KEY_ID")" | base64url)"
  payload="$(printf '{"iss":"%s","iat":%s,"exp":%s,"aud":"appstoreconnect-v1"}' \
    "$(json_escape "$ASC_ISSUER_ID")" "$now" "$exp" | base64url)"
  signing_input="$header.$payload"
  signature="$(printf '%s' "$signing_input" | openssl dgst -sha256 -sign "$ASC_KEY_PATH" | base64url)"
  printf '%s' "$signing_input.$signature"
}

jwt="$(issue_jwt)"

report_api_error() {
  local method="$1" path="$2" code="$3" body_file="$4"
  printf 'testflight-tester: %s %s 返回 HTTP %s，停手（不重试、不换端点）\n' "$method" "$path" "$code" >&2
  python3 - "$body_file" <<'PY' >&2
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        data = json.load(handle)
except Exception:
    print("响应体无法解析为 JSON")
    raise SystemExit(0)

errors = data.get("errors") or []
if not errors:
    print("响应体没有 errors[]")
    raise SystemExit(0)
for index, error in enumerate(errors):
    print("errors[%d].code=%s title=%s" % (index, error.get("code", ""), error.get("title", "")))
PY
}

# $1=GET|POST $2=path $3=body；成功时把响应体文件路径打到 stdout，非 2xx 停手。
asc_request() {
  local method="$1" path="$2" body="${3:-}" body_file code rc
  body_file="$(mktemp "$response_dir/response.XXXXXX")"
  if [ "$method" = "GET" ]; then
    if code="$(curl -g -sS -o "$body_file" -w '%{http_code}' \
      -H "Authorization: Bearer $jwt" \
      "$api_base$path")"; then
      rc=0
    else
      rc=$?
    fi
  else
    if code="$(curl -g -sS -o "$body_file" -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer $jwt" \
      -H 'Content-Type: application/json' \
      -d "$body" \
      "$api_base$path")"; then
      rc=0
    else
      rc=$?
    fi
  fi
  if [ "$rc" -ne 0 ]; then
    printf 'testflight-tester: %s %s 网络请求失败（curl 退出 %s），停手\n' "$method" "$path" "$rc" >&2
    exit 1
  fi
  case "$code" in
    2[0-9][0-9])
      printf '%s' "$body_file"
      ;;
    *)
      report_api_error "$method" "$path" "$code" "$body_file"
      exit 1
      ;;
  esac
}

encoded_email="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$tester_email")"

# 1. 只读解析 App。
apps_response="$(asc_request GET "/v1/apps?filter[bundleId]=$bundle_id")"
if ! app_id="$(python3 - "$apps_response" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
apps = data.get("data") or []
if not apps:
    raise SystemExit("empty")
print(apps[0]["id"])
PY
)"; then
  printf 'testflight-tester: 未解析到 bundle id %s 对应的 App 记录，停手\n' "$bundle_id" >&2
  exit 1
fi

# 2. 只读选中内部 betaGroup（isInternalGroup=true）。
groups_response="$(asc_request GET "/v1/betaGroups?filter[app]=$app_id&filter[isInternalGroup]=true")"
if ! group_info="$(python3 - "$groups_response" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
groups = data.get("data") or []
for group in groups:
    attributes = group.get("attributes") or {}
    if attributes.get("isInternalGroup") is True:
        print(group.get("id", ""), attributes.get("name", ""))
        break
else:
    raise SystemExit("no-internal-group")
PY
)"; then
  printf 'testflight-tester: 未找到 isInternalGroup=true 的内部测试组，停手（不向外部组写入）\n' >&2
  exit 1
fi
group_id="${group_info%% *}"
group_name="${group_info#* }"

# 3. 只读判断测试者是否已存在。
tester_response="$(asc_request GET "/v1/betaTesters?filter[email]=$encoded_email")"
tester_id="$(python3 - "$tester_response" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
testers = data.get("data") or []
print(testers[0]["id"] if testers else "")
PY
)"

# 4. 必要时创建 betaTester。
if [ -z "$tester_id" ]; then
  tester_body="$(python3 - "$tester_email" <<'PY'
import json
import sys

print(json.dumps({"data": {"type": "betaTesters", "attributes": {"email": sys.argv[1]}}}))
PY
)"
  created_response="$(asc_request POST "/v1/betaTesters" "$tester_body")"
  if ! tester_id="$(python3 - "$created_response" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
item = data.get("data") or {}
if not item.get("id"):
    raise SystemExit("no-tester-id")
print(item["id"])
PY
)"; then
    echo "testflight-tester: 创建 betaTester 后未返回 id，停手" >&2
    exit 1
  fi
fi

# 5. 只向内部组写关系。
relationship_body="$(python3 - "$tester_id" <<'PY'
import json
import sys

print(json.dumps({"data": [{"type": "betaTesters", "id": sys.argv[1]}]}))
PY
)"
relationship_response="$(asc_request POST "/v1/betaGroups/$group_id/relationships/betaTesters" "$relationship_body")"
rm -f "$relationship_response"

printf 'tester email: %s\n' "$tester_email"
printf 'betaGroup: %s (%s)\n' "$group_name" "$group_id"
printf 'info: 已完成内部测试者分配（只读先行、未触发 Beta App Review、未外邀）\n'
