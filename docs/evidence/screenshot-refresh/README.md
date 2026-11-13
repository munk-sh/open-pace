# 截图证据刷新（V1.2 复评重出）：14 张浅/深 + 7 张并排对照

归属项：`wi_intake_85d08fa7106efc3f`（§1–§9 为上一批）；**最新一批见 §0（`wi_intake_a7e3a95c0d6f61bb`）**。
本目录是本轮复评证据的登记与日志落点：14 张 PNG 逐图 sha、构建 head/tree sha、7 张浅/深并排对照、断言实测行、本地门结论与 CI 回执位置。

## 0. 最新一批（2026-11-13，V1.2 配色终版）

归属项：`wi_intake_a7e3a95c0d6f61bb`（accent `#FF6B00` / danger `#F53A48` 双模式同色；`accentSoft` light 重算为 `#FFE3CF`）。

| 项 | 实取值 |
|---|---|
| 构建 head sha | `4d2e611af16bd4eebcf0aed282db29215b9e4ed1` |
| 构建 tree sha | `c45b36045e8eb8eaf33e210d99a93d1e93cfa6ff` |
| 采集时 HEAD（实取 `git rev-parse HEAD`；采集开始 `git status --porcelain` 空输出） | `4d2e611af16bd4eebcf0aed282db29215b9e4ed1` |
| 设备 / 工具链 | 同 §1（iPhone 16，UDID `B3F00298-E08A-41E0-876E-6E8A75C730FD`；iOS 18.6；Xcode 26.3） |
| 生成方式 / 时间 | 单次 `--stage all`，2026-11-13（CST） |

- 14 张 + 7 张并排逐图 sha 以 `docs/screenshots/SHA256SUMS`、`docs/screenshots/side-by-side/SHA256SUMS`
  与本目录 `SHA256SUMS` 为准（同批 `shasum -a 256` 实取，未猜未复制）；§1 的 head/tree/逐图 sha 仅代表上一批。
- **除色 token 外零布局 diff**：本批相对 §1 批次的产品面 diff 仅色 token 与其派生期望值，布局、间距、
  字号、圆角、identifier、文案均未改动；浅/深屏间排版一致，仅取色变化。
- `docs/evidence/palette-a-contrast.txt` 与本批同源重出（74 行），sha256 见
  `docs/evidence/palette-a-contrast.sha256`（绑定 commit `4d2e611`）。

**口径**：截图只证明素材与断言绿（B1 inline 胶囊单行化、C2 紧凑确认层、地图卡在窗内、
六屏 zh-Hans）；**人肉眼复评待办**——排版观感、色彩观感与真机表现不在本目录的结论范围内，
产品不得据此自判 UI 达标。

## 1. 构建基线

| 项 | 实取值 |
|---|---|
| 构建 head sha（证据绑定；产品面基线 main，14 张 + 7 张并排均绑定此 head/tree） | `a677e175ca56c113e13cf5d2f652781febeb1223` |
| 证据绑定 tree sha（产品面 tree） | `400c010454c56683ee53ec72f78f815e387cc1e3` |
| 采集时 HEAD（实取；与上述基线的差异仅 `scripts/`、`UITests`、`docs/`） | `2200ed7cbc3a80a4e0c084f874a8827c56f8bc4e`（tree `6871aadd37e6af71b18fbb7b76d7d7995a81796f`） |
| 产品面零 diff 依据 | `git diff --stat a677e17 -- ios/PurePace ios/RunCore` 空输出（截图与并排图所用的 App / RunCore 代码树未变，故绑定 a677e17 有效） |
| 采集时工作树 | `git status --porcelain` 空输出（clean，采集开始时脚本内实取） |
| 设备 | iPhone 16，UDID `B3F00298-E08A-41E0-876E-6E8A75C730FD` |
| 系统 runtime | iOS 18.6 |
| 工具链 | Xcode 26.3（Build 17C529），`xcodegen 2.46.0` |
| 生成时间 | 2026-11-12 22:52–23:00（CST，单次 `--stage all`） |

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
- 本轮实际执行的是 `--stage all`（trees → screenshots → ax5）：`docs/evidence/a11y/` 6 棵可及树与
  `docs/evidence/evidence-freeze/ax5/` 4 张实拍 + 4 棵实测树同为该构建重出，`capture.log`
  记录 `content_size: before=large after=accessibility-extra-extra-extra-large` 与还原 `large`。

## 3. 14 张截图（逐图 sha256）

| # | 文件（`docs/screenshots/`） | 屏幕 | sha256 |
|---|---|---|---|
| 1 | `run-not-started.png` | Run 未开始（浅） | `e31727e12da292c531487dccc10474deb07bda54618da550135fba5c8f966785` |
| 2 | `run-not-started-dark.png` | Run 未开始（深） | `46c00383776e2e793fd66009b515b895fd33efa2fd7b153016acc153b587e505` |
| 3 | `run-running.png` | 跑步中（浅） | `9a9ba019e1b3e964d648475c34b96390a6db03652c23cabcbbbe1bd3c72d3699` |
| 4 | `run-running-dark.png` | 跑步中（深） | `b42fb536cbab1972640a2d6b822af69c66a03a3ee3e58e896a3e0a499b8da996` |
| 5 | `run-finished.png` | 结束态总结（浅，B1 地图 hero 360 + 单行 inline 胶囊） | `6eef6ec004045eda379a0480e52b74bb0d95dce67f42e061bcc6ee3fcbffd67c` |
| 6 | `run-finished-dark.png` | 结束态总结（深，同上） | `9e2351b3803d9cf49e82ef04794e7e85d1bd359172bd7601b15948fde1f5b087` |
| 7 | `discard-confirmation.png` | 结束态丢弃确认层（浅，C2 紧凑确认层） | `e293771006e763e2cfdfae7d1ad759796a93cefe1dc1f2b64b54a82716c9706e` |
| 8 | `discard-confirmation-dark.png` | 结束态丢弃确认层（深） | `c608cb497fe642b0dc0f2359b79026c6457b7fd301f794bbb41e77ea8ec69c5b` |
| 9 | `history-list.png` | History 列表（浅） | `78bccb09e6eff1bf5c8a0f766a37c4d0db4efeeba5efbdbeae168b7b015acdee` |
| 10 | `history-list-dark.png` | History 列表（深） | `123097ddad46322e4635da45821676b0d3080f52146880d418ec180bcc536104` |
| 11 | `history-detail.png` | History 详情（浅，地图卡完整可见后取图） | `198ca8ca44dfb4eed7da9a01c5e2ad3996f62d270d567c2b1d1a5d0fd1485bb9` |
| 12 | `history-detail-dark.png` | History 详情（深，同上） | `1d89caa1cfb687befe71b9f5d473af1001d1534f369ba7751876df105e017e02` |
| 13 | `settings.png` | Settings（浅） | `0e5058badf7dbdb10f10fef5b841b8c0212cff610beee8f5a30bfcc35cf8e583` |
| 14 | `settings-dark.png` | Settings（深） | `e9df4e5e91ff58614a9055183f07c70240bff2a924ee11b2861b1557d4009cac` |

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
| `run-not-started-side-by-side.png` | `680008f0dbf6d7d08cb50a6ba78962fc21c6e300a63ef0ccb0ee4c529b6d99b9` |
| `run-running-side-by-side.png` | `bf49dd27afe0fc15c4854fde6d4323b9722447d113d4fdbb66bfe71c9cbc79f3` |
| `run-finished-side-by-side.png` | `fa311c38535f02efe540e48532ae06b69d2b4f9d0c5afd732760f965ad3d48ae` |
| `discard-confirmation-side-by-side.png` | `2ca972aa2bfc4cc7debd6435afa3d6bd0935cd15b01aea89ccba137187b2cd7a` |
| `history-list-side-by-side.png` | `740c40d8177527fb0bdbcad96f4d4cd43e163f863c6dc69665fe656c285301a6` |
| `history-detail-side-by-side.png` | `5ac6b067665a4ca2611f0515e484cdea41660a774328a845662b804896d24165` |
| `settings-side-by-side.png` | `3b00c26f75edf8f40cece9f35e4fc7b5f59a8a2bd2aa8cfd7a448773de78ead5` |

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
- `xcodebuild-light.log` / `xcodebuild-dark.log` 各含 7 条 `evidence-shot screen=` 行（浅色 7 屏 /
  深色 7 屏带 `-dark` 后缀），两份合计覆盖导出到 `docs/screenshots/` 的 14 张；每份日志另有
  `b1-finished` / `c2-discard` 两条附加证据附件行（单份共 9 条 `evidence-shot screen=`，本轮两份共 18 条）。

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

## 8. 证据批 1 收口回执：权威腿红在 main，非本项证据问题

**结论（原样口径）**：`ios.yml` 权威腿在基线 `main = a677e17` 上判红，红因是产品层「运行中 / 暂停
指标区未垂直居中」的真实布局问题，**不是本项证据问题**；本项 14 张截图 + 7 张并排仍按产品面
tree 绑定 `a677e17`（tree `400c010`，采集时 `ios/PurePace/**` 与 `ios/RunCore/**` 相对该 head 零 diff）。
本项不宣称「ios.yml 全绿」「可分发」「UI 达标」，也不改 80pt 阈值 / 采样口径 / allowlist / 断言换绿。
修红已另立 `wi_intake_caf0abdb2486d501`（只修居中，不动阈值与采样口径）。

**基线 `a677e17` 的 `ios.yml` run（2026-11-12 实查）**：

| 字段 | 实取值 |
|---|---|
| run id | `43234566773` |
| head sha | `a677e175ca56c113e13cf5d2f652781febeb1223` |
| status / conclusion | `completed` / `failure` |
| 失败步 | `test`（14:25:29Z–14:37:44Z，`test-logs` 成功、`build` skipped） |
| 断言行 1 | `ios/PurePaceUITests/RunFlowUITests.swift:890: error: -[PurePaceUITests.RunFlowUITests testRunPauseResumeFinishAndHistory] : XCTAssertTrue failed - 暂停 指标区未垂直居中（顶部留白 73.41666666666669pt，底部留白 81.33333333333337pt，最大空洞 81.5pt）：["底部留白 81.33333333333337pt > 80.0pt", "最大单一垂直空洞 81.5pt > 80.0pt"]` |
| 断言行 2 | `ios/PurePaceUITests/RunFlowUITests.swift:890: error: -[PurePaceUITests.RunFlowUITests testZhHansCopyDatesAndBottomAnchoredPrimaryAction] : XCTAssertTrue failed - 运行中 指标区未垂直居中（顶部留白 73.41666666666669pt，底部留白 81.33333333333337pt，最大空洞 81.5pt）：["底部留白 81.33333333333337pt > 80.0pt", "最大单一垂直空洞 81.5pt > 80.0pt"]` |

该失败发生在产品视图 / `RunFlowUITests` 的版式判据，本项改动面（`ScreenshotEvidenceUITests.swift`、
`scripts/**`、`docs/**`）不含该文件；按 ac-ci-no-weakening 原样记录失败腿原文，不伪造绿。

**证据 commit 回执（Delivery 实查，2026-11-12 14:59Z 首次查询）**：证据 commit 已随本项交付推送至 `main`，
合并提交 `8a6c2afe537cab0896804439e2b70e69e97ff1e0` 触发的 `ios.yml` run 为 `43242965553`，
查询时 `status=in_progress`、`conclusion` 为空（CI 未完成）；按 ac-ci-authoritative-green 口径
本会话不 watch / sleep 轮询，故**结论待 CI 跑完**，回执按实际查询结果记录，不预写绿。
即使该 run 跑完后为绿，也只是「证据 commit 的 CI 结论」；基线 `a677e17` 的红仍在（见上表）。
`a677e17` 的产品层版式修红在另立项 `wi_intake_caf0abdb2486d501`，本项不承担该修复。

**修红后需 rebind 的最小集合**（其余证据不受影响，按现脚本重出即可）：

| 类别 | 文件 |
|---|---|
| 重出截图 | `docs/screenshots/run-running.png`、`docs/screenshots/run-running-dark.png`（本轮 7 屏里无 `run-paused` 屏；暂停态只在该 UI 用例的断言里，不产独立截图） |
| 重出并排 | `docs/screenshots/side-by-side/run-running-side-by-side.png` |
| 重写清单 | `docs/screenshots/SHA256SUMS`、`docs/screenshots/side-by-side/SHA256SUMS`、`docs/evidence/screenshot-refresh/SHA256SUMS` |
| 重写回执 | `docs/evidence/screenshot-refresh/README.md`（head/tree 重绑修红合入后的 main）、`capture.log`、`xcodebuild-light.log`、`xcodebuild-dark.log` |
| 复核 | 新 2 张与上一轮同屏 sha 重合数，以及 14 张 / 7 张的集合完整性 |

## 9. 边界与人肉眼复评待办

- 不改产品面（视图 / token / 字号 / 间距 / 圆角 / 文案 / identifier / `VERSION` 一律不动）。
- 不碰 `docs/evidence/wi_intake_93f2857d51330b9d`、`shared/`、`android/`、`ios/Core`、`ios/RunCore`。
- 不新增门禁机制与阈值（`.munk/code-gates.json` 保持 22 门），不改 `.github/workflows/ios.yml`。
- 不做真机验收、不做分发（ipa / TestFlight / tag / Release / ASC）。
- 本项不承担 ac-ci-authoritative-green：基线 `a677e17` 的 `ios.yml` 红是产品层版式问题，
  已另立修红项 `wi_intake_caf0abdb2486d501`；本项不写「ios.yml 全绿 / 可分发 / UI 达标」，
  修红合入 main 后的 rebind 最小集合见 §8。
- **人肉眼复评待办**：本目录只证明素材可复跑与断言绿；B1/C2 的排版观感、浅/深配色观感、
  7 张并排对照的视觉一致性，均需人肉眼复评。产品不得自判 UI 达标。
