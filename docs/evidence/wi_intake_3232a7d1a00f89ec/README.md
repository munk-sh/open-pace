# V1.2 运行态截图重出与证据重绑定（head = c122dbb1f38b3fd2bde9b23a93bfb67f7b8b3089）

归属项：`wi_intake_3232a7d1a00f89ec`。

本目录是本轮证据的登记与实取落点：14 张 PNG 逐图 sha、绑定四要素、7 张浅/深并排对照说明、
逐图断言来源文件路径、两份完整 `xcodebuild` 原始日志、采集前清单与像素差分析。

**口径（不得据此自判达标）**：本目录只证明「素材由 `c122dbb` 产品树实取、清单可校验、断言实测行在日志里」。
**不**证明「UI 达标」「可发布」「已验证真机」；排版与配色观感、真机表现均需人肉眼复评，不在本目录结论范围内。

## 1. 绑定四要素（全部实取）

| 字段 | 实取值 |
|---|---|
| 构建 head sha | `c122dbb1f38b3fd2bde9b23a93bfb67f7b8b3089`（完整 40 位） |
| 构建 tree sha | `bf32815bc8a5dd788f0735d975ae530cc1fa1588`（`git rev-parse c122dbb…^{tree}` 实取，与已知值一致） |
| 采集时 HEAD | `c122dbb1f38b3fd2bde9b23a93bfb67f7b8b3089`（tree `bf32815bc8a5dd788f0735d975ae530cc1fa1588`；采集窗口 2026-11-13 02:22–02:52 CST） |
| 归属项 | `wi_intake_3232a7d1a00f89ec` |
| 零 diff 声明 | 采集时 `ios/PurePace/**`、`ios/RunCore/**` 相对 c122dbb **零 diff** |

零 diff 命令与输出（工作树 clean，`git diff` 输出 0 行；原始空输出另存 `ios-zero-diff.txt`，该文件为 0 字节即实测结果）：

```
$ git rev-parse HEAD
c122dbb1f38b3fd2bde9b23a93bfb67f7b8b3089
$ git rev-parse c122dbb1f38b3fd2bde9b23a93bfb67f7b8b3089^{tree}
bf32815bc8a5dd788f0735d975ae530cc1fa1588
$ git diff --stat c122dbb1f38b3fd2bde9b23a93bfb67f7b8b3089 -- ios/PurePace ios/RunCore
（空输出）
$ git diff --stat c122dbb1f38b3fd2bde9b23a93bfb67f7b8b3089 -- ios/PurePace ios/RunCore ios/PurePaceUITests
（空输出）
$ git status --porcelain
?? .munk/changes/wi_intake_3232a7d1a00f89ec/     # 仅本项 change pack，未跟踪
```

因此采集时 HEAD 与构建 head 同为 `c122dbb`：不存在「HEAD 领先基线、靠零 diff 推断」的情况。

## 2. 采集环境与链路

| 项 | 实取值 |
|---|---|
| 设备 | iPhone 16，UDID `B3F00298-E08A-41E0-876E-6E8A75C730FD`（Booted） |
| 系统 runtime | iOS 18.6（与上一批证据同 runtime，非 iOS 26） |
| Xcode | 26.3（Build 17C529） |
| 工程生成 | `xcodegen generate --spec ios/project.yml --project ios`（`.xcodeproj` 为 gitignore 产物） |
| 构建 | `xcodebuild build-for-testing ... -derivedDataPath .build/ios CODE_SIGNING_ALLOWED=NO` → **TEST BUILD SUCCEEDED** |
| 浅色截图 | `xcrun simctl ui <udid> appearance light` + `xcodebuild test -only-testing:PurePaceUITests/ScreenshotEvidenceUITests/testEvidenceScreensLight -resultBundlePath .build/evidence/wi3232/light-final.xcresult` |
| 深色截图 | `... appearance dark` + `-only-testing:.../testEvidenceScreensDark -resultBundlePath .build/evidence/wi3232/dark-final.xcresult`，结束后 `appearance light` 复原 |
| 导出 | `xcrun xcresulttool export attachments --path <bundle> --output-path <staging>`；**附件名即文件名，不裁切、不重编码、不改名**，只把差异图落库 |
| 未使用 | 未运行 `scripts/capture-ios-screenshots.sh`（其 `refresh_dir` / 归属项硬编码为上一批与本项不符，且本项 `scripts/` 须零 diff）；按其内部同一组命令手动复刻 |

浅色截图腿 02:37:26–02:38:28；深色截图腿 02:40:46–02:41:43（`Test Suite 'Selected tests' passed`）。

图片尺寸实测：14 张原图均 1178×2556；7 张并排图均 2356×2556（= 2 × 1178 × 2556，等高）。

## 3. 其余 12 张逐张核对（三列对照）

「已入库 sha」= 采集前 `docs/screenshots/*.png` 的 sha（原清单，另存 `pre-collection-sha256.txt`）；
「本次实取 sha」= 本轮 `testEvidenceScreensLight` / `testEvidenceScreensDark` 附件字节；
「判定」= 一致（保留原文件、字节零改动） / 替换（落本次实取）。

**判定结果：14 张全部替换（0 张一致）**，故 `git diff --name-only` 中 14 张均为 `M`——这是逐张比对后的实际结论，不是主动重出全部。

| 文件 | 已入库 sha（采集前） | 本次实取 sha | 判定 | 字节变化原因（像素差实测，见 `pixel-diff-analysis.txt`） |
|---|---|---|---|---|
| `run-not-started.png` | `e31727e12da292c531487dccc10474deb07bda54618da550135fba5c8f966785` | `5c94295c72f6d008bcbc67f8ea7e3e70813d22313b2936e56be608c6491a4f7d` | 替换 | 布局：运行页指标区元素因居中修复重排（差异带 y611–1921，多个 ≈40px=20pt 高行带；位移相关性检验最小比值在 shift=0，即非整体平移）；另有状态栏时钟（y69–106） |
| `run-not-started-dark.png` | `46c00383776e2e793fd66009b515b895fd33efa2fd7b153016acc153b587e505` | `17127569ca4f36a47c2a1d294547fd5e66f7d6f2f732e3c2a1237beaa4047dda` | 替换 | 同上（深色） |
| `run-running.png` | `9a9ba019e1b3e964d648475c34b96390a6db03652c23cabcbbbe1bd3c72d3699` | `803e1ac2ba8b08080abbb8c1c2f642b9399380d33ae3b41141a243eece6ba835` | 替换 | 布局：运行中态指标区元素重排（差异带 y631–2047，多个 ≈40px=20pt 高行带；位移相关性最小比值在 shift=0）；采样读数（时长/距离/配速）随时间轴变化；状态栏时钟 |
| `run-running-dark.png` | `b42fb536cbab1972640a2d6b822af69c66a03a3ee3e58e896a3e0a499b8da996` | `0699f8b31ba7f644c7022f357a4f312242e85588b2121f26e394d6cde0f9f5bf` | 替换 | 同上（深色） |
| `run-finished.png` | `6eef6ec004045eda379a0480e52b74bb0d95dce67f42e061bcc6ee3fcbffd67c` | `13e838ec2eb620f9a33250fbe4bb038a60646ca675d179675db5309a05a5e0c2` | 替换 | 保存态指标区版式/数值（本轮采样读数不同：时长、距离、配速、分段），状态栏时钟 |
| `run-finished-dark.png` | `9e2351b3803d9cf49e82ef04794e7e85d1bd359172bd7601b15948fde1f5b087` | `4ee5b6e596a5c0b617e3fb210a5a6ed8cf817548480d775c5cfd91f6303a5d0d` | 替换 | 同上（深色） |
| `discard-confirmation.png` | `e293771006e763e2cfdfae7d1ad759796a93cefe1dc1f2b64b54a82716c9706e` | `87c80b21b326064af84b58ef48eb3912c117c9ba9c9e3b766747b7bc935117fb` | 替换 | 底层为结束待保存屏：随采样读数与指标区版式变化（band y769–1649 为确认层与主操作区）；另有时钟 |
| `discard-confirmation-dark.png` | `c608cb497fe642b0dc0f2359b79026c6457b7fd301f794bbb41e77ea8ec69c5b` | `042abee854ab60d854a775d97024b0e8b0bb2d6ef7f1c7d1cb7c787c2d6c9e05` | 替换 | 同上（深色） |
| `history-list.png` | `78bccb09e6eff1bf5c8a0f766a37c4d0db4efeeba5efbdbeae168b7b015acdee` | `db21ed92eb2c1e5d50eaf628ac5bfeb42284758dfb0cc70eb667e9a7bd5f948e` | 替换 | 相对时间/日期文案行（band y521–571、y615–648，本次跑次记录时间不同）；状态栏时钟 |
| `history-list-dark.png` | `123097ddad46322e4635da45821676b0d3080f52146880d418ec180bcc536104` | `a2c3e164f1c49bc13e97e06a5120ec19c6767b34969db37ee462207d9321a193` | 替换 | 同上（深色），另含底部 y2517–2531 一行 |
| `history-detail.png` | `198ca8ca44dfb4eed7da9a01c5e2ad3996f62d270d567c2b1d1a5d0fd1485bb9` | `116119fc3ae574bf0efeea8c5b814dda0312dc5bd41c9e35747ace6d1392007c` | 替换 | 地图轨道渲染（y9–292）与图表/分段读数区（y442–2069）随本次采样轨迹变化 |
| `history-detail-dark.png` | `1d89caa1cfb687befe71b9f5d473af1001d1534f369ba7751876df105e017e02` | `539efe460b68194aa578c99e3ca3c93f3a1db9b652653bccee87ba4c7ca672fd` | 替换 | 同上（深色） |
| `settings.png` | `0e5058badf7dbdb10f10fef5b841b8c0212cff610beee8f5a30bfcc35cf8e583` | `32cb467583052e97b52a51268fa32b50a4b56c96d6bd2ffabf396fe082cf296d` | 替换 | 状态栏时钟（y69–106）与底部说明行（y2517–2531） |
| `settings-dark.png` | `e9df4e5e91ff58614a9055183f07c70240bff2a924ee11b2861b1557d4009cac` | `d185b2bac9a2b45d9c2ec3b1f50b1de868839f4aef4f72ff4787251dc85349bc` | 替换 | 同上（深色） |

替换口径约束：**只换像素，不换判据**——两条 UI 断言腿（`RunFlowUITests` 的 80pt 阈值、采样口径、`VisibleTextPolicy` allowlist）
与 `ios/` 全部源码零改动；差异原因均为「布局修复后的实际位移 ± 采样/时钟等非布局视觉读数」，非断言换绿。

## 4. 逐图断言来源文件路径（全路径）

| 证据行 / 判据 | 来源文件（仓库内全路径） |
|---|---|
| `evidence-shot screen=<name>`（14 张截图的截图时点与附件名） | `ios/PurePaceUITests/ScreenshotEvidenceUITests.swift:180-187`（`capture(base:)`） |
| 截图驱动顺序与前置状态（六屏 + 确认层，浅/深各一腿） | `ios/PurePaceUITests/ScreenshotEvidenceUITests.swift:28-37`（`testEvidenceScreensLight` / `testEvidenceScreensDark`）、`:40-175`（`captureAllScreens`） |
| `evidence-primary screen=… identifier=… label=…`（主操作 identifier/label 非空） | `ios/PurePaceUITests/ScreenshotEvidenceUITests.swift:189-193` |
| `evidence-map screen=… identifier=run.mapPreview frame=… visible=…`（地图卡完整落在可见区） | `ios/PurePaceUITests/ScreenshotEvidenceUITests.swift:197-215` |
| `ac-visible-copy-zh-hans screen=… violations=0`（截图前 zh-Hans 文案判定） | `ios/PurePaceUITests/ScreenshotEvidenceUITests.swift:249-275`；策略实现 `ios/PurePaceUITests/VisibleTextPolicy.swift` |
| 可及树批采（快照采集，供上面各判定取样） | `ios/PurePaceUITests/AXSnapshotBatch.swift:16-74`（`AXSnapshotBatch.collect`，由 `ScreenshotEvidenceUITests.swift:340` 调用） |
| `ac-run-metrics-balanced 未开始/运行中/暂停/保存态`（top/bottom/largest ≤ 80） | `ios/PurePaceUITests/RunFlowUITests.swift:845-894`（`assertRunMetricsBalanced` 打印于 `:885`）；调用点 `:129`（暂停）、`:642`（未开始）、`:662`（运行中）、`:690`（保存态）、`:760`（保存态（无分段）） |
| `ac-visible-copy-zh-hans`（RunFlow 侧同源打印） | `ios/PurePaceUITests/RunFlowUITests.swift:789` |
| `ac-c2-filled-danger-primary`（深色日志中的已知红点，见 §5） | `ios/PurePaceUITests/RunFlowUITests.swift:1129-1146` |

## 5. 两份日志（完整 xcodebuild 原始输出）

`xcodebuild-light.log`（1514 行）与 `xcodebuild-dark.log`（1493 行）均为完整输出，按 host 段落拼接，段头以
`################ [section n/m]` 标注来源与命令，未截断任何 xcodebuild 输出。

| 日志 | 段落 | 结果 |
|---|---|---|
| light | 1/3 截图腿 `testEvidenceScreensLight` | `** TEST SUCCEEDED **`（exit 0），9 条 `evidence-shot screen=` 行（= 7 屏 + `b1-finished` + `c2-discard` 两条附加附件行，7 屏全覆盖） |
| light | 2/3 `testRunPauseResumeFinishAndHistory`（暂停态） | `** TEST SUCCEEDED **`（exit 0） |
| light | 3/3 `testZhHansCopyDatesAndBottomAnchoredPrimaryAction`（未开始/运行中/保存态） | `** TEST SUCCEEDED **`（exit 0） |
| dark | 1/4 截图腿 `testEvidenceScreensDark` | `** TEST SUCCEEDED **`（exit 0），9 条 `evidence-shot screen=` 行（7 屏带 `-dark` 后缀全覆盖） |
| dark | 2/4 `testRunPauseResumeFinishAndHistory`（暂停态） | `** TEST SUCCEEDED **`（exit 0） |
| dark | 3/4 `testZhHansCopyDatesAndBottomAnchoredPrimaryAction`（深色外观） | `** TEST FAILED **`（exit 65）——见下方说明；仍打印未开始/运行中实测行 |
| dark | 4/4 `testSavedStateWithoutSplitsKeepsMapFloorAndBalance`（保存态（无分段）） | `** TEST SUCCEEDED **`（exit 0） |

`ac-run-metrics-balanced` 三态实测行（各态 top / bottom / largest 均 ≤ 80）：

| 外观 | 态 | top | bottom | largest | 日志行 |
|---|---|---|---|---|---|
| 浅色 | 未开始 | 72.5 | 72.333 | 72.667 | `xcodebuild-light.log:1162` |
| 浅色 | 运行中 | 79.417 | 79.333 | 79.5 | `xcodebuild-light.log:1234` |
| 浅色 | 暂停 | 79.417 | 79.333 | 79.5 | `xcodebuild-light.log:765` |
| 浅色 | 保存态 | 27.5 | 37.667 | 48.167 | `xcodebuild-light.log:1420` |
| 深色 | 未开始 | 72.5 | 72.333 | 72.667 | `xcodebuild-dark.log:1090` |
| 深色 | 运行中 | 79.417 | 79.333 | 79.5 | `xcodebuild-dark.log:1162` |
| 深色 | 暂停 | 79.417 | 79.333 | 79.5 | `xcodebuild-dark.log:702` |
| 深色 | 保存态（无分段） | 27.5 | 37.667 | 48.167 | `xcodebuild-dark.log:1474` |

**深色 section 3 的红（如实记录，不在本项修复范围）**：

```
ios/PurePaceUITests/RunFlowUITests.swift:1145: error: -[PurePaceUITests.RunFlowUITests
testZhHansCopyDatesAndBottomAnchoredPrimaryAction] : XCTAssertLessThanOrEqual failed:
("0.5607843137254902") is greater than ("0.00784313725490196") - 确认丢弃不是 danger 实心填充
```

原因：该断言把确认按钮左缘采样与 `DesignTokens.Colors.palette["danger"]?.light`（浅色 token）比对
（`RunFlowUITests.swift:1129-1146`），在深色外观下按钮用深色 token，故必然判红。该用例在浅色外观（CI 口径）通过。
本项 `ios/` 必须零 diff，不修改该断言/阈值；故深色日志的「保存态」实测行由同一判据的
`testSavedStateWithoutSplitsKeepsMapFloorAndBalance`（`RunFlowUITests.swift:760`，输出 `保存态（无分段）`）提供，
浅色日志的三态行则全部来自 PRD 指定的两个用例。此为测试侧外观局限的事实记录，不构成产品达标结论。

## 6. 浅/深并排对照（7 张）

`docs/screenshots/side-by-side/` 由 `bash scripts/compose-ios-screenshots-side-by-side.sh` 实跑重建（exit 0），
左半 = 浅色原图、右半 = 深色原图、1:1 像素、无缩放、无分隔线、等高；每张实测 2356×2556。
脚本自带逐像素回归（左半/右半与对应原图逐字节一致）与编码确定性校验，运行无失败输出。

因 14 张原图本轮**全部字节变化**，7 张并排图 sha 也全部变化（不存在「原图未变而并排字节变」的异常）：

| 并排图 | 采集前 sha | 本轮 sha |
|---|---|---|
| `run-running-side-by-side.png` | `bf49dd27afe0fc15c4854fde6d4323b9722447d113d4fdbb66bfe71c9cbc79f3` | `e55b2c5dd86d651ffea4b0c513663b7aa41e89ddae57931f6838cd34872cc532` |
| `run-not-started-side-by-side.png` | `680008f0dbf6d7d08cb50a6ba78962fc21c6e300a63ef0ccb0ee4c529b6d99b9` | `9de1ec5642bd79a50c3d1294994c310530d5f08f43d61888782d839fce546429` |
| `run-finished-side-by-side.png` | `fa311c38535f02efe540e48532ae06b69d2b4f9d0c5afd732760f965ad3d48ae` | `c5bdccea93143fb32b540dc89cede2236bdd80a98ea7334ebc8883c0cdacc7fd` |
| `discard-confirmation-side-by-side.png` | `2ca972aa2bfc4cc7debd6435afa3d6bd0935cd15b01aea89ccba137187b2cd7a` | `decb2b928b7ebc821c7d69f1abdb9e2022b227050df48cd86d5811202dafa183` |
| `history-list-side-by-side.png` | `740c40d8177527fb0bdbcad96f4d4cd43e163f863c6dc69665fe656c285301a6` | `3dca83156a3e6f7e865376fae66553761c53b0f74fc0b39f28e947dc7624f12a` |
| `history-detail-side-by-side.png` | `5ac6b067665a4ca2611f0515e484cdea41660a774328a845662b804896d24165` | `8a7aecbe624a1a8717abfd3c782b3f4df3c9ccb43f650e49afd64511b6dda990` |
| `settings-side-by-side.png` | `3b00c26f75edf8f40cece9f35e4fc7b5f59a8a2bd2aa8cfd7a448773de78ead5` | `c0c4f9058756d1133ccad741c6bd772d427438b9c0fa60d66c88a013aff2aed8` |

并排图 `SHA256SUMS` 头部已按口径补齐四要素与零 diff 声明（未改脚本）。

## 7. 校验结果（本目录 / 本项实跑）

| 校验 | 命令 | 结果 |
|---|---|---|
| 截图清单 | `shasum -a 256 -c docs/screenshots/SHA256SUMS` | exit 0，14/14 `OK` |
| 并排清单 | `shasum -a 256 -c docs/screenshots/side-by-side/SHA256SUMS` | exit 0，7/7 `OK` |
| 本目录清单 | `cd docs/evidence/wi_intake_3232a7d1a00f89ec && shasum -a 256 -c SHA256SUMS` | exit 0（见 `SHA256SUMS`） |
| 范围纯度 | `git diff --stat c122dbb… -- ios scripts .github android shared .munk/code-gates.json` | 空输出 |
| 新图非复用 | `run-running.png` 新 sha `803e1ac2ba8b08080abbb8c1c2f642b9399380d33ae3b41141a243eece6ba835` ≠ 采集前 `9a9ba019e1b3e964d648475c34b96390a6db03652c23cabcbbbe1bd3c72d3699`；`run-running-dark.png` 新 sha `0699f8b31ba7f644c7022f357a4f312242e85588b2121f26e394d6cde0f9f5bf` ≠ 采集前 `b42fb536cbab1972640a2d6b822af69c66a03a3ee3e58e896a3e0a499b8da996`；两张互不相同 | 通过 |

## 8. 边界

- 只改 `docs/screenshots/**`、`docs/evidence/**`（以及本项 `.munk/changes/wi_intake_3232a7d1a00f89ec/**`）。
- `ios/`、`scripts/`、`.github/`、`android/`、`shared/`、`.munk/code-gates.json` 零 diff；未改 UI / token / 阈值 / identifier / 文案。
- 未跑真机、未做分发（ipa / TestFlight / tag / Release / ASC）、未重跑 CI、未改门禁。
- 未重建 `docs/evidence/screenshot-refresh/`、`docs/evidence/wi_intake_93f2857d51330b9d/` 等既往批次。
- 本目录不写「UI 达标」「可发布」「已验证真机」类结论。

## 9. 目录内容

| 文件 | 说明 |
|---|---|
| `README.md` | 本文件 |
| `SHA256SUMS` | 本目录文件清单（在本目录执行 `shasum -a 256 -c SHA256SUMS`） |
| `xcodebuild-light.log` | 浅色三段完整 xcodebuild 输出 |
| `xcodebuild-dark.log` | 深色四段完整 xcodebuild 输出 |
| `ios-zero-diff.txt` | 采集时 `git diff --stat c122dbb… -- ios/PurePace ios/RunCore ios/PurePaceUITests` 原始输出（0 字节即空输出） |
| `pre-collection-sha256.txt` | 采集前 14 张截图 + 7 张并排图入库 sha，与采集前 `git status --porcelain` |
| `pixel-diff-analysis.txt` | 旧图（`git show HEAD:…`）与新图逐像素差分析：总差异像素数与行带区间 |
