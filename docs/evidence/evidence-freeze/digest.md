# 证据冻结 digest（第 5 波 / evidence-freeze）

本文件只记录实测事实、路径、命令、sha256 与退出码。不对发布条件或无障碍水平下结论，也不含真机验收与分发动作。

采集日期：2026-11-11，本机时区（日志原文时间戳）。

## 0. 预算回执

- 开工预算：预计 25–30 分钟；门禁轮次上限 2 轮；期望收口：开工后 40 分钟内。
- 实际时间线（日志 / 文件 mtime 实测）：采集 `15:17:17` 开始（`trees-20261111151717.xcresult`）→ `15:22:34` 采集结束（`capture-log-3.txt` 收尾）；门禁首轮 22 门中 `check-shell-expansion` 退出码 1（脚本裸变量紧跟中文，见 §7），修复后 `15:25:39`–`15:26:27` 复跑全 22 门退出码 0。门禁轮次 2 轮，未超预算。

## 1. 环境与构建

- 模拟器：iPhone 16，UDID `B3F00298-E08A-41E0-876E-6E8A75C730FD`（唯一一台）。
- Runtime：`com.apple.CoreSimulator.SimRuntime.iOS-18-6`，version `18.6`，build `22G86`（唯一一个 runtime）。
- 宿主：macOS `15.6.1`；Xcode `26.3`（Build `17C529`）。
- 采集日志里出现的设备路径去重结果（`grep -oE '/Devices/[0-9A-Fa-f-]+' .build/evidence/capture-log-3.txt | sort -u`）：

```
/Devices/B3F00298-E08A-41E0-876E-6E8A75C730FD
```

- 同一日志中的 OS 取值去重（`grep -oE 'OS:[0-9.]+' ... | sort -u`）只有 `OS:18.6`；未出现第二台设备或第二个 runtime。
- 被测构建 commit SHA（采集前 `git rev-parse HEAD` 实取）：`e4f2fc1b8fa8c0fd0f93f7a89f1f5c7dda3cb607`。
- 构建命令（产物落在 `.build/ios`）：

```
xcodebuild build-for-testing -project ios/PurePace.xcodeproj -scheme PurePace \
  -destination "platform=iOS Simulator,id=B3F00298-E08A-41E0-876E-6E8A75C730FD" \
  -derivedDataPath .build/ios CODE_SIGNING_ALLOWED=NO
```

- 证据采集入口（日志 `.build/evidence/capture-log-3.txt`）：

```
bash scripts/capture-ios-screenshots.sh --stage all
```

## 2. 12 张截图

全部由 `xcrun simctl io <UDID> screenshot` 直接写入 `docs/screenshots/`，逐张分辨率 `1179 × 2556`（iPhone 16 原生竖屏）。目录内不存在中间编辑产物：`find .build/evidence -maxdepth 2 -name '*.png'` 计数为 0；sha256 由 `shasum -a 256` 对该文件实取，与 `docs/screenshots/SHA256SUMS` 同行一致（`shasum -a 256 -c docs/screenshots/SHA256SUMS` 退出码见 §7 后复核）。

| 文件 | sha256 | 像素 |
|---|---|---|
| `docs/screenshots/run-not-started.png` | `9f52fafdea201558e5793d85258108172cc4cef10901f93575783ac93486a124` | 1179×2556 |
| `docs/screenshots/run-not-started-dark.png` | `fa589aaac4d0304a87afa164c4bb98da0befc8311d4ac029d71e23c6b6cd5663` | 1179×2556 |
| `docs/screenshots/run-running.png` | `3b3c34925faee3bcee46dac5aab63ce1ca8950f9d15a0c76d7409368090d8a70` | 1179×2556 |
| `docs/screenshots/run-running-dark.png` | `f44171a6121b06b287689907397cac99628ce814ac0c34fd747a4f91d75e5158` | 1179×2556 |
| `docs/screenshots/run-finished.png` | `ec9aed68eaba8ee7278f9b94a5ee3e7f0b4077bb6f9ee4680e094d4764507790` | 1179×2556 |
| `docs/screenshots/run-finished-dark.png` | `53d3c2a05fecf8d3bc35418ecdf8e4b8d11d28eb46b13b643c1dfc4136cb8283` | 1179×2556 |
| `docs/screenshots/history-list.png` | `c1d7ff17266a9c89f9b186e9096222aa08b336b88ead42f136f568d28ec82c02` | 1179×2556 |
| `docs/screenshots/history-list-dark.png` | `0e309280efbc0e44df27430827b6748aceb2eff79d4bab2708c5c73dab3a47e4` | 1179×2556 |
| `docs/screenshots/history-detail.png` | `1f808ce83b01b1492693177b2cd1bb8f0e94d5f2b44653a327a9579ae32bb48e` | 1179×2556 |
| `docs/screenshots/history-detail-dark.png` | `889aac39997dc423188e8ab130b6bd8c2a0a1b4ed70df91fc1ae3568a6378c53` | 1179×2556 |
| `docs/screenshots/settings.png` | `250cd35bed77b2483be0b8702102a749a919f48154bc59a6196a4a95f41be880` | 1179×2556 |
| `docs/screenshots/settings-dark.png` | `7166ae7db7f1d5846c8509cf49233e7deecacd7db02e66aa52b7dc7b1067aba9` | 1179×2556 |

### 2.1 逐张生成命令

公共变量：`UDID=B3F00298-E08A-41E0-876E-6E8A75C730FD`，`BUNDLE=sh.munk.purepace`。每次启动前脚本都会先 `xcrun simctl terminate "$UDID" "$BUNDLE"`；跑步三屏与 AX5 前另执行 `rm -f <容器>/Library/Caches/active-run.jsonl`（只清中断态 checkpoint，不触碰 `Documents/Runs`）。

Run 首屏（浅 / 深）：

```
xcrun simctl ui    B3F00298-E08A-41E0-876E-6E8A75C730FD appearance light
xcrun simctl terminate B3F00298-E08A-41E0-876E-6E8A75C730FD sh.munk.purepace
xcrun simctl launch B3F00298-E08A-41E0-876E-6E8A75C730FD sh.munk.purepace -uiTestLocation
sleep 5
xcrun simctl io    B3F00298-E08A-41E0-876E-6E8A75C730FD screenshot docs/screenshots/run-not-started.png

xcrun simctl ui    B3F00298-E08A-41E0-876E-6E8A75C730FD appearance dark
xcrun simctl terminate B3F00298-E08A-41E0-876E-6E8A75C730FD sh.munk.purepace
xcrun simctl launch B3F00298-E08A-41E0-876E-6E8A75C730FD sh.munk.purepace -uiTestLocation
sleep 5
xcrun simctl io    B3F00298-E08A-41E0-876E-6E8A75C730FD screenshot docs/screenshots/run-not-started-dark.png
```

跑步中 + 结束总结（浅色，同一进程；`-screenshotRunFinished` 在真实采样 30s 后自动结束到待保存决策态）：

```
xcrun simctl ui    B3F00298-E08A-41E0-876E-6E8A75C730FD appearance light
xcrun simctl terminate B3F00298-E08A-41E0-876E-6E8A75C730FD sh.munk.purepace
xcrun simctl launch B3F00298-E08A-41E0-876E-6E8A75C730FD sh.munk.purepace -uiTestLocation -autoStartRecording -screenshotRunFinished
sleep 20
xcrun simctl io    B3F00298-E08A-41E0-876E-6E8A75C730FD screenshot docs/screenshots/run-running.png
sleep 25
xcrun simctl io    B3F00298-E08A-41E0-876E-6E8A75C730FD screenshot docs/screenshots/run-finished.png
```

跑步中 + 结束总结（深色，同一流程，`appearance dark`）：

```
xcrun simctl ui    B3F00298-E08A-41E0-876E-6E8A75C730FD appearance dark
xcrun simctl terminate B3F00298-E08A-41E0-876E-6E8A75C730FD sh.munk.purepace
xcrun simctl launch B3F00298-E08A-41E0-876E-6E8A75C730FD sh.munk.purepace -uiTestLocation -autoStartRecording -screenshotRunFinished
sleep 20
xcrun simctl io    B3F00298-E08A-41E0-876E-6E8A75C730FD screenshot docs/screenshots/run-running-dark.png
sleep 25
xcrun simctl io    B3F00298-E08A-41E0-876E-6E8A75C730FD screenshot docs/screenshots/run-finished-dark.png
```

History 列表 / 详情 / Settings（浅色）：

```
xcrun simctl ui    B3F00298-E08A-41E0-876E-6E8A75C730FD appearance light
xcrun simctl terminate B3F00298-E08A-41E0-876E-6E8A75C730FD sh.munk.purepace
xcrun simctl launch B3F00298-E08A-41E0-876E-6E8A75C730FD sh.munk.purepace -uiTestLocation -screenshotInitialTab history
sleep 6
xcrun simctl io    B3F00298-E08A-41E0-876E-6E8A75C730FD screenshot docs/screenshots/history-list.png

xcrun simctl terminate B3F00298-E08A-41E0-876E-6E8A75C730FD sh.munk.purepace
xcrun simctl launch B3F00298-E08A-41E0-876E-6E8A75C730FD sh.munk.purepace -uiTestLocation -screenshotInitialTab history -screenshotOpenRunDetail
sleep 6
xcrun simctl io    B3F00298-E08A-41E0-876E-6E8A75C730FD screenshot docs/screenshots/history-detail.png

xcrun simctl terminate B3F00298-E08A-41E0-876E-6E8A75C730FD sh.munk.purepace
xcrun simctl launch B3F00298-E08A-41E0-876E-6E8A75C730FD sh.munk.purepace -uiTestLocation -screenshotInitialTab settings
sleep 5
xcrun simctl io    B3F00298-E08A-41E0-876E-6E8A75C730FD screenshot docs/screenshots/settings.png
```

History 列表 / 详情 / Settings（深色，同一组命令，`appearance dark`，输出 `history-list-dark.png` / `history-detail-dark.png` / `settings-dark.png`）：

```
xcrun simctl ui    B3F00298-E08A-41E0-876E-6E8A75C730FD appearance dark
xcrun simctl terminate B3F00298-E08A-41E0-876E-6E8A75C730FD sh.munk.purepace
xcrun simctl launch B3F00298-E08A-41E0-876E-6E8A75C730FD sh.munk.purepace -uiTestLocation -screenshotInitialTab history
sleep 6
xcrun simctl io    B3F00298-E08A-41E0-876E-6E8A75C730FD screenshot docs/screenshots/history-list-dark.png

xcrun simctl terminate B3F00298-E08A-41E0-876E-6E8A75C730FD sh.munk.purepace
xcrun simctl launch B3F00298-E08A-41E0-876E-6E8A75C730FD sh.munk.purepace -uiTestLocation -screenshotInitialTab history -screenshotOpenRunDetail
sleep 6
xcrun simctl io    B3F00298-E08A-41E0-876E-6E8A75C730FD screenshot docs/screenshots/history-detail-dark.png

xcrun simctl terminate B3F00298-E08A-41E0-876E-6E8A75C730FD sh.munk.purepace
xcrun simctl launch B3F00298-E08A-41E0-876E-6E8A75C730FD sh.munk.purepace -uiTestLocation -screenshotInitialTab settings
sleep 5
xcrun simctl io    B3F00298-E08A-41E0-876E-6E8A75C730FD screenshot docs/screenshots/settings-dark.png
```

### 2.2 启动参数披露

- 使用了：`-uiTestLocation`（仅 DEBUG 的确定性测试定位源，产生真实采样与真实落盘距离）、`-autoStartRecording`（越过倒计时）、`-screenshotRunFinished`（仅 DEBUG 的自动结束门控）、`-screenshotInitialTab`、`-screenshotOpenRunDetail`。
- 未使用：`-uiTestResetArchive`（会清掉真实归档）、`-screenshotHistoryDemo`。
- `-screenshotRunFinished` 在 `ios/PurePace/Run/RunSessionViewModel.swift` 的 `#if DEBUG` 内（`scheduleScreenshotAutoFinishIfNeeded()`），Release 不编译该实现，故发布路径不可达。
- 演示注入计数（实取）：

```
$ grep -c -- '-screenshotHistoryDemo' .build/evidence/capture-log-3.txt
0
$ grep -o -- 'launch_app [^#]*' scripts/capture-ios-screenshots.sh | grep -c -- '-screenshotHistoryDemo'
0
```

（`-screenshotHistoryDemo` 字样只出现在脚本与用例的注释里：`scripts/capture-ios-screenshots.sh:7`、`ios/PurePaceUITests/EvidenceCaptureUITests.swift:7`，不在任何执行命令中。）

## 3. History 数据来源（真实归档）

- 真实链路：`EvidenceCaptureUITests/testEvidenceTreesAndRealArchive` 点击 `run.start` → 采样 31s → `run.finish` → `run.save` 落盘；随后从 History 列表进入详情。未使用 `-uiTestResetArchive`。
- 采集时容器归档路径（`.build/evidence/capture-log-3.txt` 原文）：

```
archive: /Users/zhutao/Library/Developer/CoreSimulator/Devices/B3F00298-E08A-41E0-876E-6E8A75C730FD/data/Containers/Data/Application/4FB7701A-19F2-4150-BBFD-BCBC33E0AADD/Documents/Runs
total 16
-rw-r--r--  1 zhutao  staff  4264 Nov 11 15:18 20261111T071728Z-C6987B5A-9BD5-4AEA-BA35-E83C6FEB3919.json
```

- 归档文件 sha256（该文件与采集快照 `.build/evidence/archive-snapshot/` 同名副本同哈希）：

```
dbdf7bd11b6e8f34b5b43f847308d401fa1d27127ba8c6068d6f4d04b2909ef9
```

- 归档记录实测值（JSON 原文）：`id = C6987B5A-9BD5-4AEA-BA35-E83C6FEB3919`，`startedAt = 1794381448.251955` = 2026-11-11 15:17:28，`distance = 310.2338453380304` m，`activeDuration = 31.00041103363037` s，`samples` 32 条（15:17:29.07 → 15:18:00.07）。
- 界面可见值（用例打印，采集日志原文）：

```
evidence-history-row label=2026年11月11日 15:17，0.31 km，00:31，1:40 /km
evidence-history-detail startedAt=2026年11月11日 15:17:28 distance=0.31 km elapsed=00:31
```

- 与归档逐项对齐：开始时间 `15:17:28`（列表截到分 `15:17`）、距离 `310.23 m → 0.31 km`、活动时长 `31.0004 s → 00:31`。
- 与既有演示注入判据对照：演示跑次固定 `5.12 km`、固定 `startedAt = 1_760_000_000`；本次归档为 `0.31 km` / `1794381448.25`，不是该固定组合。
- 说明：门禁里的 `test-ios` 会在模拟器上重装 App（采集之后），使容器路径变化、`Documents/Runs` 不再保留该文件；上面记录的是采集当时的容器路径与 `ls -l` 输出，同哈希文件仍保留在 `.build/evidence/archive-snapshot/`（`.build/` 为 gitignore）。

## 4. 六棵可及树与「一屏一主操作」

`docs/evidence/a11y/` 恰有六棵，全部由本次构建的 `testEvidenceTreesAndRealArchive` 导出（`XCTAttachment(string: app.debugDescription)`）：

| 树 | sha256 | 主操作 identifier | 主操作 label |
|---|---|---|---|
| `docs/evidence/a11y/01-run-not-started.txt` | `bb9342e5a8865d3ab35a8ae76e492883a975be70fd7eadd3c1a4296b8ef7e2e7` | `run.start` | 开始记录跑次 |
| `docs/evidence/a11y/02-run-running.txt` | `54959e6dc28385087f81fd868a3843075a04d1c2f4b6f6c67f66d42bdb2c2103` | `run.pause` | 暂停记录跑次 |
| `docs/evidence/a11y/03-run-finished.txt` | `b6ad1679889ad77d130d154bcd8f7ba93e9fe6839c0a1cd5bf0ef1d2199a0db4` | `run.save` | 保存本次跑步 |
| `docs/evidence/a11y/04-history-list.txt` | `9d1cbae5736bae2b59f34620833d2d5ed753d8f62f63191c515c9651a60631f8` | `history.row` | 2026年11月11日 15:17，0.31 km，00:31，1:40 /km |
| `docs/evidence/a11y/05-history-detail.txt` | `cc8cf2fdf32213fb5c043e56bbea3bad02cf35aeabd06e64012c7d4d3b92c486` | `runDetail.export` | 导出 GPX |
| `docs/evidence/a11y/06-settings.txt` | `ef9c97e4b55f83a87e7499fcc3621c08b6e8c54b8e44747114d69d85886e9cef` | `settings.announcementToggle` | 每公里语音播报 |

- 各树内 identifier 实取（`grep -o "identifier: '<id>'"`）与上表一致，无偏差；旧集合中不对应六屏的 `03-history-empty` / `06-tabs` 已从该目录移除（当前目录只有上面 6 个文件）。
- 主操作 label 非空：导出时用例同时断言 `identifier` 与 `label` 非空（`recordPrimaryAction`），六条 `evidence-primary` 打印见采集日志第 72/233/253/280/299/320 行。

## 5. AX5 最大辅助字号档实拍与 frame 实测

设置与读回（采集中实测）：

```
$ xcrun simctl ui B3F00298-E08A-41E0-876E-6E8A75C730FD content_size
large
$ xcrun simctl ui B3F00298-E08A-41E0-876E-6E8A75C730FD content_size accessibility-extra-extra-extra-large
$ xcrun simctl ui B3F00298-E08A-41E0-876E-6E8A75C730FD content_size
accessibility-extra-extra-extra-large
...
$ xcrun simctl ui B3F00298-E08A-41E0-876E-6E8A75C730FD content_size large   # 还原
$ xcrun simctl ui B3F00298-E08A-41E0-876E-6E8A75C730FD content_size
large
```

同档布局实测由 `EvidenceCaptureUITests/testEvidenceAx5Layout` 执行（`xcodebuild test-without-building ... -only-testing:PurePaceUITests/EvidenceCaptureUITests/testEvidenceAx5Layout`，结果包 `.build/evidence/ax5-20261111152032.xcresult`），实测行原文：

```
AX5-FIT screen=01-run-not-started window=(0.0, 0.0, 393.0, 852.0) primary=run.start primaryFrame=(16.0, 713.0, 361.0, 44.0) elements=18 outOfBounds=0 overlaps=0
AX5-FIT screen=03-run-finished window=(0.0, 0.0, 393.0, 852.0) primary=run.save primaryFrame=(16.0, 713.0, 287.0, 44.0) elements=21 outOfBounds=0 overlaps=0
AX5-FIT screen=05-history-detail window=(0.0, 0.0, 393.0, 852.0) primary=runDetail.export primaryFrame=(0.0, 560.0, 393.0, 68.0) elements=29 outOfBounds=0 overlaps=0
AX5-FIT screen=06-settings window=(0.0, 0.0, 393.0, 852.0) primary=settings.announcementToggle primaryFrame=(0.0, 218.66666666666666, 393.0, 100.33333333333334) elements=14 outOfBounds=0 overlaps=0
```

判定口径：内容元素集合 = 按钮 / 静态文本 / 开关 / 图片 / 链接 / 单元格 / 输入框；每个元素 frame 需落在 `window` 内（容差 1pt）；主操作 frame 与其它内容 frame 不相交（主操作自身与其被包含的子元素不计为「其它内容」）。四屏实测 `outOfBounds=0`、`overlaps=0`，用例断言全部通过。

AX5 实拍（同档、浅色，`xcrun simctl io <UDID> screenshot` 直接写入）：

| 文件 | sha256 | 像素 |
|---|---|---|
| `docs/evidence/evidence-freeze/ax5/ax5-run-not-started.png` | `5d23793acd998b1925ff00556d41cb20546622bbe93a9b3319613c0830cee4b9` | 1179×2556 |
| `docs/evidence/evidence-freeze/ax5/ax5-run-finished.png` | `aa590baa8dbbd1b5a473cbdc346f2dc0fc777907523fddb9534ec3c4fa9cf550` | 1179×2556 |
| `docs/evidence/evidence-freeze/ax5/ax5-history-detail.png` | `9346b93e945d0ef4b405cf358653aa84743b5adb8a8f3849ed877bb236e31b2f` | 1179×2556 |
| `docs/evidence/evidence-freeze/ax5/ax5-settings.png` | `0ac84f0128e7fbb1f353a39b808b7f18e364d4f0c7886c2570888371e6cdcf39` | 1179×2556 |

AX5 同档实测树：

| 文件 | sha256 |
|---|---|
| `docs/evidence/evidence-freeze/ax5/ax5-01-run-not-started.txt` | `b1b66358bdcd9322f97097a6642f3ddeac0b46d3cfa5e75a8358eec96b0da7f7` |
| `docs/evidence/evidence-freeze/ax5/ax5-03-run-finished.txt` | `4669617ac99f7ee0fa23edd092f86a254f6242dfe717ffdf7cb4cbeb0b054ec5` |
| `docs/evidence/evidence-freeze/ax5/ax5-05-history-detail.txt` | `e2f73de0820b4439d78d1425e526962c044723a96260446e7a79b800b3d81365` |
| `docs/evidence/evidence-freeze/ax5/ax5-06-settings.txt` | `690cd52f5131670fffd154489c5649d60e5eb1a5b49b09fd507e9e5ab9b9b40a` |

## 6. Dynamic Type 口径（如实记录）

- `ios/PurePace/Design/DesignTokens.swift` 的 `DesignTokens.Typography` 全部为固定 `Font.system(size:weight:)` 点值，字号阶梯 `sizes = [11, 12, 15, 20, 34, 56]`，不随 Dynamic Type 缩放。
- 因此 §5 的 AX5 证据只能说明：固定字号布局在系统最大辅助字号档下不截断、不重叠；它不能说明字号本身随系统字号放大。
- 本文件不给出无障碍方面的结论。

## 7. code_gates 全量退出码

按 `.munk/code-gates.json` 门顺序逐门执行（`version: 1`，共 22 门，`command` 为单一 argv）：

| # | gate id | 退出码 | 耗时 |
|---|---|---|---|
| 1 | `lint` | 0 | 0.0s |
| 2 | `lint-baseline` | 0 | 0.0s |
| 3 | `lint-ios-core` | 0 | 0.3s |
| 4 | `lint-ios-scripts` | 0 | 13.8s |
| 5 | `lint-ios-release` | 0 | 0.2s |
| 6 | `lint-ios-shell` | 0 | 2.5s |
| 7 | `lint-ios-workflow` | 0 | 1.5s |
| 8 | `lint-android` | 0 | 8.9s |
| 9 | `lint-android-workflow` | 0 | 0.7s |
| 10 | `lint-ios-run-core` | 0 | 0.3s |
| 11 | `build-ios-core` | 0 | 0.4s |
| 12 | `build-ios-run-core` | 0 | 0.4s |
| 13 | `build-ios` | 0 | 1.3s |
| 14 | `test-ios-core` | 0 | 0.5s |
| 15 | `test-ios-run-core` | 0 | 0.6s |
| 16 | `test-ios` | 0 | 12.1s |
| 17 | `build-android` | 0 | 0.5s |
| 18 | `test-android` | 0 | 3.2s |
| 19 | `test` | 0 | 0.1s |
| 20 | `check-shared` | 0 | 0.1s |
| 21 | `check-gpx-export` | 0 | 0.7s |
| 22 | `check-shell-expansion` | 0 | 0.1s |

- 门禁首轮实测：`check-shell-expansion` 退出码 1，失败原文为脚本 `scripts/capture-ios-screenshots.sh` 中裸变量紧跟非 ASCII 字节（如 `$file（`、`$udid）`、`$archive_snapshot（`）。修复为 `${file}` / `${udid}` / `${archive_snapshot}` 写法后复跑，上表 22 门全为 0。该修复只改字符串展开写法，不改变采集行为。
- 本项未改 `.munk/code-gates.json`（门列表与命令保持 22 门不变）。

## 8. commit 绑定

- 被测构建 commit SHA（采集前 `git rev-parse HEAD`）：`e4f2fc1b8fa8c0fd0f93f7a89f1f5c7dda3cb607`。
- 证据入库 commit SHA（`git log --format=%H -1 -- <file>` 对每个证据文件实取，结果一致）：`067b4ff1bb93318af277da721cd0e08efb89e651`。覆盖的 26 个文件：

```
docs/screenshots/run-not-started.png
docs/screenshots/run-not-started-dark.png
docs/screenshots/run-running.png
docs/screenshots/run-running-dark.png
docs/screenshots/run-finished.png
docs/screenshots/run-finished-dark.png
docs/screenshots/history-list.png
docs/screenshots/history-list-dark.png
docs/screenshots/history-detail.png
docs/screenshots/history-detail-dark.png
docs/screenshots/settings.png
docs/screenshots/settings-dark.png
docs/evidence/a11y/01-run-not-started.txt
docs/evidence/a11y/02-run-running.txt
docs/evidence/a11y/03-run-finished.txt
docs/evidence/a11y/04-history-list.txt
docs/evidence/a11y/05-history-detail.txt
docs/evidence/a11y/06-settings.txt
docs/evidence/evidence-freeze/ax5/ax5-run-not-started.png
docs/evidence/evidence-freeze/ax5/ax5-run-finished.png
docs/evidence/evidence-freeze/ax5/ax5-history-detail.png
docs/evidence/evidence-freeze/ax5/ax5-settings.png
docs/evidence/evidence-freeze/ax5/ax5-01-run-not-started.txt
docs/evidence/evidence-freeze/ax5/ax5-03-run-finished.txt
docs/evidence/evidence-freeze/ax5/ax5-05-history-detail.txt
docs/evidence/evidence-freeze/ax5/ax5-06-settings.txt
```

- 两列不同的成因：截图来自 `e4f2fc1` 的构建产物，证据文件本身在该构建之后另提交入库，因此「被测构建 SHA」与「证据入库 SHA」分列，不混用。
- `docs/screenshots/SHA256SUMS` 与 `docs/evidence/evidence-freeze/digest.md` 是清单与报告，同属本次入库提交；任何文件都无法内嵌承载自身的提交 SHA（自引用），其实取值用 `git log --format=%H -1 -- <file>` 实取，未写猜测值。

## 9. 本项改动范围

- 新增 / 更新：`docs/screenshots/**`、`docs/evidence/a11y/**`、`docs/evidence/evidence-freeze/**`、`README.md`（仅图集数量与描述）、`scripts/capture-ios-screenshots.sh`、`ios/PurePaceUITests/EvidenceCaptureUITests.swift`（前序提交引入的取证用例，本项只复用）。
- 未改：业务逻辑、`L10n` 键值、`DesignTokens` 取值、`.munk/code-gates.json`。
- 未做：ASC / ipa / TestFlight / tag / Release；真机项（锁屏定位、音频实听、授权弹窗观感）仍为 `pending: 待人现场`。
