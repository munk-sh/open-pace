# 截图证据刷新（V1.2 复评重出）：14 张浅/深 + 7 张并排对照

归属项：`wi_intake_85d08fa7106efc3f`。本目录是本轮复评证据的登记与日志落点：
14 张 PNG 逐图 sha、构建 head/tree sha、7 张浅/深并排对照、断言实测行、本地门结论与 CI 回执位置。

**口径**：截图只证明素材与断言绿（B1 inline 胶囊单行化、C2 紧凑确认层、地图卡在窗内、
六屏 zh-Hans）；**人肉眼复评待办**——排版观感、色彩观感与真机表现不在本目录的结论范围内，
产品不得据此自判 UI 达标。

## 1. 构建基线

| 项 | 实取值 |
|---|---|
| 构建 head sha（14 张 + 7 张并排均绑定此 commit） | `18049604470a611d8b13e12a9212c61e3af73b4c` |
| 构建 tree sha（`git rev-parse HEAD^{tree}`） | `5b902cb447996458a3967dab9b5ceeb855229cda` |
| 采集时工作树 | `git status --porcelain` 空输出（clean，采集开始时脚本内实取） |
| 设备 | iPhone 16，UDID `B3F00298-E08A-41E0-876E-6E8A75C730FD` |
| 系统 runtime | iOS 18.6 |
| 工具链 | Xcode 26.3（Build 17C529），`xcodegen 2.46.0` |
| 生成时间 | 2026-11-12 22:29–22:31（CST，`--stage screenshots` 单次跑完浅/深） |

head/tree sha 由采集脚本 `git rev-parse` 实取并同时写进
`docs/screenshots/SHA256SUMS`、`docs/screenshots/side-by-side/SHA256SUMS` 与本 README，
三处同值；`--stage verify` 校验三处一致。

## 2. 命令（可复跑）

```bash
# 0) 生成工程 + 构建测试包（截图阶段用 test-without-building，不重复构建）
xcodegen generate --spec ios/project.yml --project ios
xcodebuild build-for-testing \
  -project ios/PurePace.xcodeproj \
  -scheme PurePace \
  -destination 'platform=iOS Simulator,id=B3F00298-E08A-41E0-876E-6E8A75C730FD' \
  -derivedDataPath .build/ios CODE_SIGNING_ALLOWED=NO

# 1) 重出 14 张浅/深截图（内部按外观各调一次 xcodebuild，结束时重写 SHA256SUMS 与 7 张并排）
bash scripts/capture-ios-screenshots.sh --stage screenshots

# 2) 只读自检已入库证据（14 张 / 14 行 SHA / 旧 sha 零复用 / 7 张并排 / 可及树 / AX5 / README）
bash scripts/capture-ios-screenshots.sh --stage verify
```

- 采集脚本：`scripts/capture-ios-screenshots.sh`
- 并排合成脚本：`scripts/compose-ios-screenshots-side-by-side.sh`
  （系统 Swift + CoreGraphics/ImageIO，零第三方依赖；同一输入两次运行字节相同）
- 断言源：`ios/PurePaceUITests/ScreenshotEvidenceUITests.swift`（浅/深各一条用例）
- 运行原始结果包（不入库）：`.build/evidence/screenshots-light.xcresult`、`.build/evidence/screenshots-dark.xcresult`

## 3. 14 张截图（逐图 sha256）

| # | 文件（`docs/screenshots/`） | 屏幕 | sha256 |
|---|---|---|---|
| 1 | `run-not-started.png` | Run 未开始（浅） | `4f2bff0156afb299b4c26fc11e7330e661cc5c70041670772661df9951009d8c` |
| 2 | `run-not-started-dark.png` | Run 未开始（深） | `61453190f6548448710f5ed2e36cb15d9efa7d3680c98a034e3c67703a8bde35` |
| 3 | `run-running.png` | 跑步中（浅） | `2bd39f1ad9ae3751b0f6f7208b25cf53b57e96726d6117905d52001ba291fa2e` |
| 4 | `run-running-dark.png` | 跑步中（深） | `f4809c41beef2cf1a5fcde18a2a3cbd5a343be6da96c10be71534b0f5d57eb16` |
| 5 | `run-finished.png` | 结束态总结（浅，B1 地图 hero 360 + 单行 inline 胶囊） | `c7c285a2f1d694a7b92465d959d3fb1f287a8bdac7bc43cf01edc3a81eb7b936` |
| 6 | `run-finished-dark.png` | 结束态总结（深，同上） | `079ebd6334b155c2cde2819cefce73fc0722e952a99d038155307b29abacd8e5` |
| 7 | `discard-confirmation.png` | 结束态丢弃确认层（浅，C2 紧凑确认层） | `7108b3ca07f0f6e18cb390e651ecfed4fe45a978a91dfd0b5f4d78e5abfbdde0` |
| 8 | `discard-confirmation-dark.png` | 结束态丢弃确认层（深） | `c2c7431d0f4dd0b6345c9c6660472b03dd5386940218b6c371ecc0f0cafb9395` |
| 9 | `history-list.png` | History 列表（浅） | `de5bbc8f85985262986af7675bf9b08d4c171a7f29101699d5b38267a607c539` |
| 10 | `history-list-dark.png` | History 列表（深） | `a697916c719c60e3d4fd4a040c9245ca5dd34de914afd32598895e7cdc7630c3` |
| 11 | `history-detail.png` | History 详情（浅，地图卡完整可见后取图） | `daa9ce76daf2d29276fffeb24c441b636d3939c6cc571b8b1da1059417c7769d` |
| 12 | `history-detail-dark.png` | History 详情（深，同上） | `2e025eea94aba819add719f9deac4f6315ac2bb4c72ef5daec7934e47dc732ce` |
| 13 | `settings.png` | Settings（浅） | `f8102080ae7ab51befabd7c07701a3997e75810d85a5a4af7d31624d98e93314` |
| 14 | `settings-dark.png` | Settings（深） | `dc992befb8482b401c2efd99907a1db8ca0c00b3a2a0071b046f926b074ba434` |

- 目录顶层恰 14 张 PNG，文件名集合 = `{run-not-started, run-running, run-finished,
  discard-confirmation, history-list, history-detail, settings} × {<base>.png, <base>-dark.png}`。
- 逐图 sha 由 `shasum -a 256 docs/screenshots/*.png` 实取写入 `docs/screenshots/SHA256SUMS`；
  `shasum -a 256 -c docs/screenshots/SHA256SUMS` → 14 行全 OK（2026-11-12 实跑）。
- 导出链无裁切 / 改色 / 再编码 / 改名：`ScreenshotEvidenceUITests` 的 `XCTAttachment`
  附件名即最终文件名，`xcresulttool export attachments` 直出后原样复制到 `docs/screenshots/`。
- `docs/evidence/screenshot-refresh/capture.log` 逐张登记 14 条
  `shot: docs/screenshots/<name>.png（1178 2556 px）` 行（14 张均为 1178×2556）。

## 4. 7 张浅/深并排对照（`docs/screenshots/side-by-side/`）

| 文件 | sha256 |
|---|---|
| `run-not-started-side-by-side.png` | `4f63da6236102c4e2c8c6fb98c18323472117988b29958ad1dfb8f25b8bb8801` |
| `run-running-side-by-side.png` | `9df9cee5dac81b77c945d016292ab8beb22210c97c540fd61f4b6fcf36b0ad42` |
| `run-finished-side-by-side.png` | `e42a0b6993a5e2895c1d897a7aa686eaacaf536112b72a49062160631ad3a8c7` |
| `discard-confirmation-side-by-side.png` | `13c466bfdba01ff30609cc83102ac4b34b0b3212842eba7fd05a356a98cbc27b` |
| `history-list-side-by-side.png` | `5bd1d7590cf9e6fb3b0d6260f13eaddccc8c4e493cefe3c9cac71e80b2a616a2` |
| `history-detail-side-by-side.png` | `41e197718b3ab43105d45bdc53920554fc7e3ebc8318a9067d1fc47eb53bfb93` |
| `settings-side-by-side.png` | `7236acc50c461ca8cb725e14d8dfa6e6d3274da015ea767a79ed2da4539ed7e4` |

- 尺寸：每张 `2356×2556` = 2 × 1178（浅/深原图宽）× 2556（原图高），**等高、1:1 像素、无缩放**。
- 构图：左半 = 浅色原图、右半 = 深色原图、不插分隔线；合成脚本在写盘前逐像素比对
  左半 == 浅色原图、右半 == 深色原图（同一解码口径、逐字节），不一致直接失败。
- 确定性：`bash scripts/compose-ios-screenshots-side-by-side.sh` 连续运行两次，7 张逐图 sha 一致
  （脚本内也对同一合成图二次 PNG 编码做字节相等校验）。
- 零第三方依赖：仅系统 `swift` + CoreGraphics / ImageIO / UniformTypeIdentifiers。
- `docs/screenshots/side-by-side/SHA256SUMS` 恰 7 行哈希，`shasum -a 256 -c` 全 OK。

## 5. 与上一轮 14 张 sha 对照（ac-no-reuse-prev-batch）

生成前 `docs/screenshots/SHA256SUMS` 的 14 个旧 sha 来自上一轮 `cbebc19` 批次：

| 旧文件 | 旧 sha256 |
|---|---|
| `discard-confirmation-dark.png` | `1b62989ebe29f070a873e4c67815acaeaf9a5ba38b7594aab884ec8285621aae` |
| `discard-confirmation.png` | `448eb7c933ed820daa0b415a55bd2cff5586ba4a8fc3be0b01a172906845b67d` |
| `history-detail-dark.png` | `261a9c594245b1534dfcc634bc22fe0146823554528f6f6cc89a5ed310a67c17` |
| `history-detail.png` | `65dca19d8b8e503f83f0f8b40a10ad22b5d03ab7410eb58f5b74fe8134502a9a` |
| `history-list-dark.png` | `adf7fee347e72a9205ebfb653886dae1c02dcc5b20ff92557a3f14228702085b` |
| `history-list.png` | `80028ad0e7d6e99005943d2e77906def51568b165fff8447aaa06f4a338d83b9` |
| `run-finished-dark.png` | `c5f31dad9f5f37bd96143ca1239a8fc8c330ebdbc614a41a9d42101436a681e9` |
| `run-finished.png` | `c10554ea187349b2c48c49d0081d5a2120ec2bf5f9bf63d37338c408e4652677` |
| `run-not-started-dark.png` | `07b5b175c8b5c760515218bd0b7b99611a40886123b7281537801233cbd3f803` |
| `run-not-started.png` | `af06a2bc504b70b0396921c6c3b7cf682b51f93632cf8296e39601de5f205fd0` |
| `run-running-dark.png` | `143896f88c14477d259d0c0412fa59624cfe7274a264f43cc7411a62abb69074` |
| `run-running.png` | `f9f38251c7bb3b2aa3648d07caf56754a73882242dcd841e73a472c7e97d3b66` |
| `settings-dark.png` | `3be45b5ba7446c14e950ec6e2df37c041d6d36f7b8d6b90c19b5b2d09b1d8910` |
| `settings.png` | `bb604f077c0631b460c0355fa726933a15e4121d2c03562be0c44eb1063692ae` |

结论：新 14 张与该 14 个旧 sha 的逐张重合数 = **0**（2026-11-12 实跑 `comm -12` 为 0 行；
`--stage verify` 逐张比对同一份旧 sha 清单，同判零复用）。

## 6. 截图前断言实测（浅/深各一份，两版一致）

- **B1 inline 权限胶囊**（`run-finished` 取图前断言，`RunFinishedSummaryLayoutPolicy.meetsInlineHint`）：
  `evidence-inline-hint hint=(72.67, 679.33, 248.0, 23.67) maxHeight=32.0 contentWidth=361.0`
  → 高 23.67 ≤ 32、宽 248.0 < 内容宽 361.0（内容宽 = 窗口 393 − 2 × `Spacing.cardGap` 16），
  单行胶囊不占满整行；旧整行 39.33pt 形态会被同一判据判红。
- **C2 确认层**（`discard-confirmation` 取图前断言）：
  `evidence-c2-discard screenHeight=852.0 sheetTop=682.33 sheetHeight=169.67 title=(68,690.33,125,24) confirm=(16,750,235.67,44) cancel=(263.67,750,113.33,44)`
  → `run.discard` 44pt（±1）、`run.discardCancel` 同行（midY 差 0 ≤ 2）、
  顶边由 `标题.frame.minY − Spacing.xs` 推导 = 682.33 ≥ 852×70% = 596.4、高度 169.67 ≤ 200。
  确认层判据不用 `app.sheets`（`grep -c 'app.sheets' ... == 0`）。
- **地图卡**（`run.mapPreview`）：`run-finished` / `history-detail` 各一条 `evidence-map` 行，地图卡完整落在
  「窗口扣除底部固定主操作区」的可见区内。
- **zh-Hans**：六屏 × 浅/深各一条 `ac-visible-copy-zh-hans screen=<screen> labels=… violations=0`
  （共 12 条），白名单口径不变（仅放行 `/km`、`km`、`GPX`、`PurePace`）。
- `xcodebuild-light.log` / `xcodebuild-dark.log` 各含 14 个 `evidence-shot screen=` 行
  （本轮共 18 条含 `b1-finished` / `c2-discard` 附加证据附件；导出到 `docs/screenshots/` 的仍是 14 张）。

## 7. 本地门（2026-11-12 实跑）

| 门 | 命令 | 结果 |
|---|---|---|
| iOS 结构与标识符 self-test | `bash scripts/check-ios-shell.sh --self-test` | 100 项断言，0 项失败 |
| iOS 结构与标识符冻结 | `bash scripts/check-ios-shell.sh` | 33 项断言，0 项失败 |
| 单测腿 | `bash scripts/test-ios.sh --unit-only` | PurePaceTests 265/0；RunCore 173/0 |
| 脚本契约 | `bash scripts/check-ios-scripts.sh` | 34 项断言，0 项失败（含 `ac-ui-suite-coverage-guard`） |
| 证据自检 | `bash scripts/capture-ios-screenshots.sh --stage verify` | OK（14 张 + 14 行 SHA + 旧 sha 零复用 + 7 张并排 + 6 棵可及树 + AX5 4+4） |

产品面零改动：本项只动 `ios/PurePaceUITests/ScreenshotEvidenceUITests.swift`、`scripts/**`、`docs/**`；
`ios/PurePace/**` 零 diff（identifier 42 / 33 两套冻结计数、token、字号、间距、圆角、文案、
`VERSION` 与 `0.1.0(1)` 均不变），`.munk/code-gates.json` 仍 22 门，
`scripts/test-ios.sh` 的 `ui_call` 仍 4 段且预算/阈值不变，`.github/workflows/ios.yml` 零 diff。

## 8. CI 权威腿回执（待推送后回填）

证据 commit（本 README / 14 张 PNG / 7 张并排 / 三份日志所在 commit）由本仓库推送后在
`ios.yml` 上跑权威腿，回执字段如下（**不得伪造**；推送由 Delivery 阶段执行，本 coding
会话无 `git push` / `gh auth` 权限）：

| 回执字段 | 取值 |
|---|---|
| head sha | 待推送后实取（构建 head sha 为 `18049604470a611d8b13e12a9212c61e3af73b4c`） |
| run id | 待 `gh run list --workflow=ios.yml --commit <sha>` 实取 |
| status / conclusion | 待回填（要求 `completed` / `success`） |
| 4 段 UI 腿覆盖 | 待回填（要求覆盖 `RunFlowUITests`、`EvidenceCaptureUITests`、`Ax5ScrollAuditCounterexampleTests`、`MusicSourceSelfCheckUITests`、`ScreenshotEvidenceUITests` 浅/深） |
| 各腿耗时 | 待回填 |

红线：为换绿不得提高 timeout、删腿、加 `continue-on-error` 或放宽断言；若 `ios.yml` 判红，
按失败腿原文（run id + 断言行 + 日志片段）作为阻塞上报，不得伪造绿。

## 9. 边界与人肉眼复评待办

- 不改产品面（视图 / token / 字号 / 间距 / 圆角 / 文案 / identifier / `VERSION` 一律不动）。
- 不碰 `docs/evidence/wi_intake_93f2857d51330b9d`、`shared/`、`android/`、`ios/Core`、`ios/RunCore`。
- 不新增门禁机制与阈值（`.munk/code-gates.json` 保持 22 门），不改 `.github/workflows/ios.yml`。
- 不做真机验收、不做分发（ipa / TestFlight / tag / Release / ASC）。
- **人肉眼复评待办**：本目录只证明素材可复跑与断言绿；B1/C2 的排版观感、浅/深配色观感、
  7 张并排对照的视觉一致性，均需人肉眼复评。产品不得自判 UI 达标。
