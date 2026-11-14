# 分发人工门：一次性录入凭据

iOS 分发（归档 → 上传 App Store Connect → 分配 TestFlight 内部测试者）已脚本化。
人的动作只剩**一次性录入凭据**：把下列值临时导入当前 shell 环境，之后全部由仓库脚本执行。
凭据不得写入仓库、脚本、日志、CI secrets 文件或 shell history 之外的地方。

## 需要录入的变量

| 变量 | 含义 | 约束 |
|---|---|---|
| `ASC_KEY_PATH` | App Store Connect API 私钥 `.p8` 的绝对路径 | 必须放在仓库之外（例如 `~/keys/AuthKey_$ASC_KEY_ID.p8`），文件权限自行收紧 |
| `ASC_KEY_ID` | API Key ID | 只存在于本机环境，不落仓 |
| `ASC_ISSUER_ID` | API Issuer ID | 只存在于本机环境，不落仓 |
| `TESTFLIGHT_TESTER_EMAIL` | 要加入内部测试组的测试者邮箱 | 只写内部组，不触发外部邀请 |

## 录入步骤（占位符示例）

```bash
export ASC_KEY_PATH="$HOME/keys/AuthKey_$ASC_KEY_ID.p8"
export ASC_KEY_ID="<你的 Key ID>"
export ASC_ISSUER_ID="<你的 Issuer ID>"
export TESTFLIGHT_TESTER_EMAIL="<测试者邮箱>"

# 只判断存在性，不打印值
test -f "$ASC_KEY_PATH"
test -n "$ASC_KEY_ID"
test -n "$ASC_ISSUER_ID"
test -n "$TESTFLIGHT_TESTER_EMAIL"
```

录入后按 `docs/release/testflight-runbook.md` 的脚本主路径执行；流程结束用
`unset ASC_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID TESTFLIGHT_TESTER_EMAIL` 清除本机临时环境变量。

## 安全边界

- 凭据不得进仓库：不提交 `.p8`、`.env`、导出文件或任何含 Key ID / Issuer ID / 私钥 / JWT 的文本。
- 凭据不得进日志与 CI：脚本只在内存签发 JWT，不打印、不落盘；CI 不承载分发，也不读取这些变量。
- 私钥文件必须在仓库之外；`.p8` 仅由本机人持有，仓库脚本只读取其路径。
- Xcode Organizer / Transporter 只作 fallback，不再要求人手工上传或手工邀请测试者。
- 本文件只写占位符与路径约定，不含任何真实凭据值或本机用户目录绝对路径。
