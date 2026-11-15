# 分发人工门：一次性录入凭据

iOS 分发（归档 → 上传 App Store Connect → 分配 TestFlight 内部测试者）已脚本化。
人的动作只剩**一次性录入凭据**：在本机唯一落点 `~/.purepace-asc/asc.env` 写好四项变量，
之后全部由仓库脚本与分发任务读取。

分发任务的第一步与本手册口径一致：先 `. ~/.purepace-asc/asc.env`，再逐项校验四个变量存在；
任一缺失即停手，回到本节重新录入，不跳过、不猜值。

## 凭据落点（唯一口径）

- 唯一落点：`~/.purepace-asc/asc.env`，文件权限 `chmod 600`，目录与文件都在仓库之外。
- `~/.purepace-asc/asc.env` 只写四项变量；`.p8` 私钥文件也一律放进 `~/.purepace-asc/`。
- 不入仓、不贴聊天、不打印值、不进日志与 CI；不把变量临时 export 到某个 shell 当作录入完成。

## 需要录入的变量

| 变量 | 含义 | 约束 |
|---|---|---|
| `ASC_KEY_PATH` | App Store Connect API 私钥 `.p8` 的路径 | 指向 `~/.purepace-asc/` 下的 `.p8`（占位：`$HOME/.purepace-asc/AuthKey_<你的 Key ID>.p8`），必须放在仓库之外 |
| `ASC_KEY_ID` | API Key ID | 只写在 `~/.purepace-asc/asc.env`，不落仓 |
| `ASC_ISSUER_ID` | API Issuer ID | 只写在 `~/.purepace-asc/asc.env`，不落仓 |
| `TESTFLIGHT_TESTER_EMAIL` | 要加入内部测试组的测试者邮箱 | 只写内部组，不触发外部邀请 |

## 录入（占位符示例）

第一次录入时先在 `~/.purepace-asc/` 下放好 `.p8`，再把四行占位内容写进 `~/.purepace-asc/asc.env` 并填真实值；
值只留在本机该文件里：

```bash
mkdir -p ~/.purepace-asc
chmod 700 ~/.purepace-asc
# ~/.purepace-asc/asc.env 里写这四行（把 <...> 换成自己的值）：
# ASC_KEY_PATH=$HOME/.purepace-asc/AuthKey_<你的 Key ID>.p8
# ASC_KEY_ID=<你的 Key ID>
# ASC_ISSUER_ID=<你的 Issuer ID>
# TESTFLIGHT_TESTER_EMAIL=<测试者邮箱>
chmod 600 ~/.purepace-asc/asc.env
```

## 自检（复制即用，只判存在性，不打印值）

```bash
chmod 600 ~/.purepace-asc/asc.env
test -f ~/.purepace-asc/asc.env
( set -a; . ~/.purepace-asc/asc.env; set +a; test -f "$ASC_KEY_PATH" && test -n "$ASC_KEY_ID" && test -n "$ASC_ISSUER_ID" && test -n "$TESTFLIGHT_TESTER_EMAIL" && echo asc-env-ok )
```

成功时末行输出 `asc-env-ok`；任一项缺失则不输出，按缺失项回到录入步骤补齐。

## 加载口径（与分发任务首步一致）

先 `. ~/.purepace-asc/asc.env` 把四项导入当前 shell，再校验四项；缺失即停手：

```bash
. ~/.purepace-asc/asc.env
test -f "$ASC_KEY_PATH" && test -n "$ASC_KEY_ID" && test -n "$ASC_ISSUER_ID" && test -n "$TESTFLIGHT_TESTER_EMAIL" || echo "asc.env 不完整，停手" >&2
```

录入后按 `docs/release/testflight-runbook.md` 的脚本主路径执行；流程结束用
`unset ASC_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID TESTFLIGHT_TESTER_EMAIL` 清除当前 shell 的临时副本，
`~/.purepace-asc/asc.env` 仍保留在本机仓库之外。

## 人的动作只剩三项

1. **ASC App 记录**：`sh.munk.purepace` 的 App 记录由公司负责人授权的一次性操作创建 / 维护
   （见 `docs/release/stage4-prereqs.md`），仓库脚本不创建。
2. **签名**：Xcode 自动签名，由持有 Apple Developer 账号的人确认 Team 与证书可用。
3. **测试者 Apple ID**：确认要加入内部组的 Apple ID / 邮箱（即 `TESTFLIGHT_TESTER_EMAIL`）是本人可控的真实账号。

录入 ASC App 信息时，隐私政策 URL 一栏填 `https://munk.sh/privacy`。

## 安全边界

- 凭据不得进仓库：不提交 `.p8`、`.env`、导出文件或任何含 Key ID / Issuer ID / 私钥 / JWT 的文本。
- 凭据不得进日志与 CI：脚本只在内存签发 JWT，不打印、不落盘；CI 不承载分发，也不读取这些变量。
- 私钥文件必须在仓库之外，且只放在 `~/.purepace-asc/`；仓库脚本只读取 `ASC_KEY_PATH` 指向的路径。
- `~/.purepace-asc/asc.env` 权限固定 `chmod 600`，不共享、不复制到仓库或其他目录。
- Xcode Organizer / Transporter 只作 fallback，不再要求人手工上传或手工邀请测试者。
- 本文件只写占位符与路径约定，不含任何真实凭据值或本机用户目录绝对路径。
