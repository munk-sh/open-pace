# 截图证据刷新：A 色板 + 轨迹地图（14 张 + AX5/可及树 + commit 绑定）

归属项：`wi_intake_ef7a16bf35f35fb3`。本目录是这次重出界面证据的登记与日志落点：
14 张 PNG 逐图 sha、构建 head sha、命令、断言源、日志路径，以及和 2026-11-11 15:30 旧 12 张的 sha 对照。

**口径**：截图只证明素材与断言绿（地图卡在窗内、六屏 zh-Hans、确认层按钮可读），
**人肉眼验收待办**——排版观感、色彩观感与真机表现不在本目录的结论范围内。

## 1. 构建基线

| 项 | 实取值 |
|---|---|
| 构建 head sha（截图产出所在 commit） | `cbebc194872226951d0bd99f6450637e87b4811c` |
| 采集时工作树 | `git status --porcelain` 空输出（clean，采集开始时在脚本里取） |
| 设备 | iPhone 16，UDID `B3F00298-E08A-41E0-876E-6E8A75C730FD` |
| 系统 runtime | iOS 18.6（18.6 - 22G86，`com.apple.CoreSimulator.SimRuntime.iOS-18-6`） |
| 工具链 | Xcode 26.3（Build 17C529），`xcodegen 2.46.0` |
| 生成时间 | 2026-11-12 12:56–13:03（CST，单次 `scripts/capture-ios-screenshots.sh --stage all`） |

A 色板与轨迹地图必须在构建里（不许拿旧树的图冒充）：

```console
$ git merge-base --is-ancestor 67ff54b HEAD ; echo $?
0
$ git merge-base --is-ancestor 22b84ab HEAD ; echo $?
0
```

- `67ff54b` = `feat(design): 方向 A 石墨+竞速橙色板落地 + 轨迹几何纯逻辑 + 历史列表轻量索引`
- `22b84ab` = `feat(track): 新增唯一地图壳 TrackMapView + Stroke.track 与地图空态文案（wi_intake_7b9d19bc1e3be0ee）`

## 2. 命令（可复跑）

```bash
# 1) 生成工程 + 构建测试包（截图阶段用 test-without-building，不重复构建）
xcodegen generate --spec ios/project.yml --project ios
xcodebuild build-for-testing \
  -project ios/PurePace.xcodeproj \
  -scheme PurePace \
  -destination 'platform=iOS Simulator,id=B3F00298-E08A-41E0-876E-6E8A75C730FD' \
  -derivedDataPath .build/ios \
  CODE_SIGNING_ALLOWED=NO

# 2) 一次跑完 trees → screenshots → ax5（截图阶段内部按外观各调一次 xcodebuild）
bash scripts/capture-ios-screenshots.sh --stage all

# 3) 只读自检已入库证据（14 张命名、SHA 清单、旧 sha 零复用、可及树、AX5、README）
bash scripts/capture-ios-screenshots.sh --stage verify
```

截图阶段真正的两次调起（由脚本设好外观后分别执行，浅/深共用同一驱动）：

```bash
xcrun simctl ui <udid> appearance light
xcodebuild test-without-building -project ios/PurePace.xcodeproj -scheme PurePace \
  -destination 'platform=iOS Simulator,id=<udid>' -derivedDataPath .build/ios \
  -only-testing:PurePaceUITests/ScreenshotEvidenceUITests/testEvidenceScreensLight \
  -resultBundlePath .build/evidence/screenshots-light.xcresult CODE_SIGNING_ALLOWED=NO

xcrun simctl ui <udid> appearance dark
xcodebuild test-without-building ... \
  -only-testing:PurePaceUITests/ScreenshotEvidenceUITests/testEvidenceScreensDark \
  -resultBundlePath .build/evidence/screenshots-dark.xcresult CODE_SIGNING_ALLOWED=NO
```

- 断言源：`ios/PurePaceUITests/ScreenshotEvidenceUITests.swift`
- 采集脚本：`scripts/capture-ios-screenshots.sh`
- 运行原始结果包（不入库）：`.build/evidence/screenshots-light.xcresult`、`.build/evidence/screenshots-dark.xcresult`、`.build/evidence/trees-*.xcresult`、`.build/evidence/ax5-*.xcresult`

## 3. 日志

| 日志 | 内容 |
|---|---|
| `capture.log` | 脚本逐步叙事：构建 head sha、14 条 `shot:`/导出、逐条断言复核、`content_size: before=large after=accessibility-extra-extra-extra-large` 与 `content_size 还原: large` |
| `xcodebuild-light.log` | 浅色整轮 `xcodebuild test-without-building` 输出（含 `ScreenshotEvidenceUITests` 的断言打印与用例结果） |
| `xcodebuild-dark.log` | 深色整轮输出 |

测试进程内的证据标记（浅/深各一份，量取自真实可及树）：

- `evidence-map screen=run-finished identifier=run.mapPreview frame=(15.5, 489.1666666666667, 362.0, 96.99999999999994) visible=(0.0, 0.0, 393.0, 762.0)`
- `evidence-map screen=history-detail identifier=run.mapPreview frame=(0.0, 387.0, 393.0, 224.0) visible=(0.0, 0.0, 393.0, 713.0)`
- `evidence-discard sheet=discardRequest buttons=2 discard=丢弃本次跑步 cancel=取消`
- `ac-visible-copy-zh-hans screen=<6 屏> labels=… violations=0`（6 条 × 浅/深）

## 4. 14 张逐图 sha 与来源

浅色由 `testEvidenceScreensLight`、深色由 `testEvidenceScreensDark` 在同一驱动上产出（只有系统外观不同）；
取图前都先跑地图卡可见性断言与 zh-Hans 判定，断言绿才调 `XCUIScreen.main.screenshot()`，
附件名即最终文件名，导出到 `docs/screenshots/` 时不做裁切 / 改色 / 再编码 / 改名。

| # | 文件 | 屏 / 状态 | sha256 |
|---|---|---|---|
| 1 | `run-not-started.png` | Run 未开始（浅） | `af06a2bc504b70b0396921c6c3b7cf682b51f93632cf8296e39601de5f205fd0` |
| 2 | `run-not-started-dark.png` | Run 未开始（深） | `07b5b175c8b5c760515218bd0b7b99611a40886123b7281537801233cbd3f803` |
| 3 | `run-running.png` | 跑步中（浅） | `f9f38251c7bb3b2aa3648d07caf56754a73882242dcd841e73a472c7e97d3b66` |
| 4 | `run-running-dark.png` | 跑步中（深） | `143896f88c14477d259d0c0412fa59624cfe7274a264f43cc7411a62abb69074` |
| 5 | `run-finished.png` | 结束态总结（浅，地图卡断言后取图） | `c10554ea187349b2c48c49d0081d5a2120ec2bf5f9bf63d37338c408e4652677` |
| 6 | `run-finished-dark.png` | 结束态总结（深，同上） | `c5f31dad9f5f37bd96143ca1239a8fc8c330ebdbc614a41a9d42101436a681e9` |
| 7 | `discard-confirmation.png` | 结束态丢弃确认层（浅，`.sheet` 打开态） | `448eb7c933ed820daa0b415a55bd2cff5586ba4a8fc3be0b01a172906845b67d` |
| 8 | `discard-confirmation-dark.png` | 结束态丢弃确认层（深） | `1b62989ebe29f070a873e4c67815acaeaf9a5ba38b7594aab884ec8285621aae` |
| 9 | `history-list.png` | History 列表（浅） | `80028ad0e7d6e99005943d2e77906def51568b165fff8447aaa06f4a338d83b9` |
| 10 | `history-list-dark.png` | History 列表（深） | `adf7fee347e72a9205ebfb653886dae1c02dcc5b20ff92557a3f14228702085b` |
| 11 | `history-detail.png` | History 详情（浅，滚动到地图卡完整可见后取图） | `65dca19d8b8e503f83f0f8b40a10ad22b5d03ab7410eb58f5b74fe8134502a9a` |
| 12 | `history-detail-dark.png` | History 详情（深，同上） | `261a9c594245b1534dfcc634bc22fe0146823554528f6f6cc89a5ed310a67c17` |
| 13 | `settings.png` | Settings（浅） | `bb604f077c0631b460c0355fa726933a15e4121d2c03562be0c44eb1063692ae` |
| 14 | `settings-dark.png` | Settings（深） | `3be45b5ba7446c14e950ec6e2df37c041d6d36f7b8d6b90c19b5b2d09b1d8910` |

校验（仓库根）：`shasum -a 256 -c docs/screenshots/SHA256SUMS` → 14 行全 OK；
`docs/screenshots/SHA256SUMS` 头部登记了上面的构建 head sha。

## 5. 旧 / 新 sha 对照（ac-no-reuse-old）

生成前 `docs/screenshots/SHA256SUMS` 的 12 个旧 sha（2026-11-11 15:30 入库，随本批全部被替换）：

| 旧文件 | 旧 sha256 |
|---|---|
| `history-detail-dark.png` | `889aac39997dc423188e8ab130b6bd8c2a0a1b4ed70df91fc1ae3568a6378c53` |
| `history-detail.png` | `1f808ce83b01b1492693177b2cd1bb8f0e94d5f2b44653a327a9579ae32bb48e` |
| `history-list-dark.png` | `0e309280efbc0e44df27430827b6748aceb2eff79d4bab2708c5c73dab3a47e4` |
| `history-list.png` | `c1d7ff17266a9c89f9b186e9096222aa08b336b88ead42f136f568d28ec82c02` |
| `run-finished-dark.png` | `53d3c2a05fecf8d3bc35418ecdf8e4b8d11d28eb46b13b643c1dfc4136cb8283` |
| `run-finished.png` | `ec9aed68eaba8ee7278f9b94a5ee3e7f0b4077bb6f9ee4680e094d4764507790` |
| `run-not-started-dark.png` | `fa589aaac4d0304a87afa164c4bb98da0befc8311d4ac029d71e23c6b6cd5663` |
| `run-not-started.png` | `9f52fafdea201558e5793d85258108172cc4cef10901f93575783ac93486a124` |
| `run-running-dark.png` | `f44171a6121b06b287689907397cac99628ce814ac0c34fd747a4f91d75e5158` |
| `run-running.png` | `3b3c34925faee3bcee46dac5aab63ce1ca8950f9d15a0c76d7409368090d8a70` |
| `settings-dark.png` | `7166ae7db7f1d5846c8509cf49233e7deecacd7db02e66aa52b7dc7b1067aba9` |
| `settings.png` | `250cd35bed77b2483be0b8702102a749a919f48154bc59a6196a4a95f41be880` |

结论：新 14 张与上表 12 个旧 sha 的重合数为 **0**（脚本 `--stage verify` 逐张比对同一份旧 sha 清单）；
两张确认层截图是本批新增文件，不是旧图复制/改名（旧集合里没有 `discard-confirmation*`）。

## 6. 断言口径

- **地图卡**：结束态与详情共用唯一 `run.mapPreview`（`ios/PurePace/Track/TrackMapView.swift`）。
  截图前断言其 `exists`、frame 非空、且完整落在「窗口扣除底部固定主操作区（`run.save` / `runDetail.export`）」
  的可见区内；详情卡在惰性 `List` 下方，先在地图卡上方内容区拖拽滚动（≤4 次）再判，通过后才取图。
- **zh-Hans**：六屏逐屏把当前可及树非空 label 喂给 `VisibleTextPolicy.violations`，仅放行
  `/km`、`km`、`GPX`、`PurePace`；地图卡内部 MapKit 注记按「地图卡区域内且非地图卡本身」过滤
  （与 `RunFlowUITests.assertVisibleCopyZhHans` 同口径，未改那个用例）。
- **丢弃确认层**：仓内 `.sheet(` 只有一处（`grep -rn '\.sheet(' ios/PurePace` →
  `ios/PurePace/Run/RunView.swift:83:        .sheet(isPresented: $showsDiscardConfirmation) {`，共 1 处），
  即按 `ac-discard` 取「结束态丢弃确认」；截图前断言 sheet 同时含 `run.discard` 与 `run.discardCancel`
  且两者 label 非空。
- **浅/深同流程**：两版只由 `simctl ui appearance` 区分，同一驱动逐屏命中同一主操作 identifier
  （`run.start` / `run.pause` / `run.save` / `history.row` / `runDetail.export` / `settings.announcementToggle`）。

## 7. 可及树与 AX5（同构建重出）

- `docs/evidence/a11y/` 恰 6 棵（`01-run-not-started` … `06-settings`），由本轮
  `EvidenceCaptureUITests/testEvidenceTreesAndRealArchive` 重出，主操作 identifier 与 label 齐
  （`run.start` / `run.pause` / `run.save` / `history.row` / `runDetail.export` / `settings.announcementToggle`）；
  `03-run-finished` 与 `05-history-detail` 里现在含 `run.mapPreview`。
- `docs/evidence/evidence-freeze/ax5/` 4 张实拍 + 4 棵实测树由本轮
  `EvidenceCaptureUITests/testEvidenceAx5Layout` 重出；字号切换与还原见 `capture.log` 的
  `content_size: before=large after=accessibility-extra-extra-extra-large` / `content_size 还原: large`。

## 8. commit 绑定

| 绑定点 | commit |
|---|---|
| 构建 head sha（本批素材由该树产出，采集时工作树 clean） | `cbebc194872226951d0bd99f6450637e87b4811c` |
| 素材入库 commit（14 张 PNG + 6 棵可及树 + AX5 4+4 + 三份日志） | `2e150463c801df12277f7972b00aaa07f5028224` |

素材入库 commit 由 `git log --format=%H -1 -- docs/screenshots/run-finished.png` 等逐图实取
（14 张同一提交），登记进 `docs/screenshots/SHA256SUMS` 的头部注释区；
本 README 与两份 SHA 清单（`docs/screenshots/SHA256SUMS`、本目录 `SHA256SUMS`）同批入库，该提交只回填登记，不改图。

## 9. 边界

- 不改产品面：本项只动 `ios/PurePaceUITests/**`、`scripts/capture-ios-screenshots.sh`、`docs/**`、`README.md`，
  `ios/PurePace/**` 零 diff（无新 identifier、无 DesignTokens/布局/文案/启动参数变更），
  因此 `bash scripts/check-ios-shell.sh --self-test` 未跑（受管视图与 identifier 清单未改，self-test 的判据不涉及本项改动）。
- CI UI 腿仍为 13 条（RunFlow 6 + 取证/AX5/音频 7）：新增的 `ScreenshotEvidenceUITests` 只由本采集脚本
  显式 `-only-testing` 调起，不进 `scripts/test-ios.sh` 的 UI 腿数组。
- 不做分发 / ASC / ipa / TestFlight / tag / Release；不排真机验收；不对 UI 是否达标下结论。
