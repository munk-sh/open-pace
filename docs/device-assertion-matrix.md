# PurePace 真机断言清单（device-assertion-matrix）

本清单只承载**核心闭环一条**：开跑 → 切后台连续记录 → 跨公里播报 + 音乐 duck → 结束保存 → 历史 → 导出 GPX，
外加候选包首屏审计三项。真机不承载 Info.plist 声明、单个开关、时间/配速格式化、状态机、四态、阈值等语义，
这些一律由单测 / 集成 / 模拟器 UI 层证明（见文末「不进真机场的语义」）。

- 证据目录：`artifacts/device-audit/<UTC 时间戳>/`，由 `scripts/verify-ios-device-flow.sh` 落盘。
- 证据来源列只取三档之一：**Debug 可断言** / **Release 候选包可断言** / **只能人耳**；每行同时写明构建身份。
- 人耳判定只允许出现在最后一批，总数 ≤ 2 条（见批次 C）。
- 背景语义（公司裁决 `owe_573178ee739c4d74`）：本版 background 只验「切后台连续记录」，
  **不是**「锁屏连续记录」；测试期间设备已关闭自动锁屏，运行期不主动锁屏。
- 阶段门：`--phase=audio` / `--phase=background` 正式场须待本清单经 PO 转公司确认后执行；
  当前状态 `pending: 待公司确认`（`--phase=audit` 为脚本第一产出，不受此门限制）。

## 构建身份与档位

- **(a) Debug UI-test 构建**：`xcodebuild test` 产出的 Debug 构建；`-uiTestLocation` 确定性源仅 `#if DEBUG` 可用。
  bundle id `sh.munk.purepace`，实际版本 / commit 以每次 `report.md`「构建身份」段为准。
- **(b) Release 候选包**：zip sha256 `7258d2e3f7984ef2557278bd1fcdd1eea5db1f34a4d549dc8071d7afcd5b9d8f`，
  commit `8db1a167`。若实际驱动的 Release 构建与候选 zip 非同一二进制，`report.md` 必须显式标注
  「实际驱动构建 ≠ 候选包二进制」，不得宣称「候选包已验证」。
- 同一结论表出现两种构建必须分行；本清单按阶段拆成 A1（Debug）/ A2（Release）/ B（Release）三张表。
- 后台结论依赖「设备不锁屏」前提，只准写「切后台后进程存活 + 持续采样」，**不得**外推为「锁屏亦成立」。

## 批次 A1：核心闭环 · Debug 可断言（`--phase=audio`）

证据来源类型统一为 **Debug 可断言**，构建身份统一为 **(a) Debug UI-test 构建**（bundle `sh.munk.purepace`，实际 commit 见 `report.md`）。

| 断言项 | 判点（通过条件） | 证据来源类型与构建身份 | 具体取值路径 |
|---|---|---|---|
| 开跑进入进行态 | `startedAt` 存在且 `startedAt < endedAt`；`run.start` 点击后 `run.finish` 出现 | Debug 可断言 / (a) Debug UI-test 构建 | 跑次 JSON `Documents/Runs/run-*.json` 的 `startedAt`、`endedAt`；`audio-start.png` 中 `run.finish` 元素 |
| 单次跑动有界且跨恰好一次公里边界 | 跑动时长 60–90 秒；`telemetry.announcements[]` 中 `splitIndex == 1` 的公里触发恰 1 条 | Debug 可断言 / (a) Debug UI-test 构建 | 跑次 JSON `activeDuration`、`telemetry.announcements[].splitIndex`、`.trigger` |
| 跨公里播报触发 | 至少 1 条 `telemetry.announcements[]`，`splitIndex == 1` 且 `text` 含「第 1 公里」 | Debug 可断言 / (a) Debug UI-test 构建 | 跑次 JSON `telemetry.announcements[].splitIndex`、`telemetry.announcements[].text` |
| 播报音频会话配置 | 播报条目含 `category`、`mode`、`categoryOptions`（含 `duckOthers`） | Debug 可断言 / (a) Debug UI-test 构建 | 跑次 JSON `telemetry.announcements[].category` / `.mode` / `.categoryOptions` |
| duck 应用与恢复 | `categoryOptions` 含 `duckOthers` 且 `duckRevoked == true`；`sessionActivated == true`、`sessionDeactivated == true` | Debug 可断言 / (a) Debug UI-test 构建 | 跑次 JSON `telemetry.announcements[].categoryOptions` / `.duckRevoked` / `.sessionActivated` / `.sessionDeactivated` |
| 他路音频在播取值 | `isOtherAudioPlaying` 为布尔并原样记录（true/false 都记录，不伪造 true） | Debug 可断言 / (a) Debug UI-test 构建 | 跑次 JSON `telemetry.announcements[].isOtherAudioPlaying`；`announcements-*.json` 同名字段 |
| 结束保存形成归档 | 结束时新增 1 条跑次 JSON；`formatVersion == 1`、`samples` 非空、`distance ≥ 0` | Debug 可断言 / (a) Debug UI-test 构建 | `Documents/Runs/*.json` 的 `formatVersion`、`samples`、`distance`、`endedAt` |
| 历史可见本次跑次 | `history.row` 数量 ≥ 1，且最新一行对应本次 `startedAt` | Debug 可断言 / (a) Debug UI-test 构建 | `audio-history.png`；AX dump 中 `history.row`；跑次 JSON `startedAt` |
| 导出 GPX 落盘且可校验 | `.gpx` 真实存在、字节数 > 0、实算 sha256 为 64 位十六进制并与 `sha256.txt` 一致 | Debug 可断言 / (a) Debug UI-test 构建 | `Documents/Exports/*.gpx`；`sha256.txt` |
| 导出与采样一致 | GPX `trkpt` 数与 `samples` 数差值 ≤ 1；GPX 时间跨度与记录区间绝对差 ≤ 1 秒 | Debug 可断言 / (a) Debug UI-test 构建 | `.gpx` 的 `trkpt` 数 / 首末 `trkpt/time`；跑次 JSON `samples[]` |
| 证据四类齐全 | 截图序列（起跑 / km 边界 / 结束）、跑次 JSON、`announcements-*.json`、`.gpx` + `sha256.txt` 均落盘非空 | Debug 可断言 / (a) Debug UI-test 构建 | `audio-*.png`、`run-*.json`、`announcements-*.json`、`*.gpx`、`sha256.txt` |

## 批次 A2：核心闭环 · Release 候选包可断言（`--phase=background`）

证据来源类型统一为 **Release 候选包可断言**，构建身份统一为 **(b) Release 候选包（sha256 `7258…` / commit `8db1a167`）**；
实际驱动构建非候选二进制时按 `report.md` 标注分行。

| 断言项 | 判点（通过条件） | 证据来源类型与构建身份 | 具体取值路径 |
|---|---|---|---|
| 切后台后进程存活 + 持续采样 | 首条样本时间早于 `press(.home)` 时刻；末条晚于后台窗口结束；相邻样本最大空洞 ≤ 60 秒；时间序列单调不减 | Release 候选包可断言 / (b) Release 候选包（sha256 `7258…` / commit `8db1a167`） | 跑次 JSON `samples[].timestamp`、`startedAt`、`endedAt`；checkpoint JSONL `recordedAt`、`lastSample.timestamp`；`background-stage1.json` 的 `pressedHomeAt` |
| `activeDuration` 与墙钟一致 | `activeDuration` 与「末样本时间 − 首样本时间」相对差 ≤ 5% | Release 候选包可断言 / (b) Release 候选包（sha256 `7258…` / commit `8db1a167`） | 跑次 JSON `activeDuration`、`samples[].timestamp` |
| 授权与后台能力如实记录 | `authorizationStatus.name` / `accuracyAuthorization.name` / `allowsBackgroundLocationUpdates` 原样落盘；WhenInUse 时结论标 `pending: 待人现场（needs-you 单点）` | Release 候选包可断言 / (b) Release 候选包（sha256 `7258…` / commit `8db1a167`） | 跑次 JSON `telemetry.authorizationStatus.*`、`telemetry.accuracyAuthorization.*`、`telemetry.allowsBackgroundLocationUpdates` |
| 结束保存形成归档 | 结束时新增 1 条跑次 JSON；`formatVersion == 1`、`samples` 非空、`distance ≥ 0`；锁屏/未解锁读不到最终 archive 时改读 checkpoint 并标注来源，不把 archive 断言写成通过 | Release 候选包可断言 / (b) Release 候选包（sha256 `7258…` / commit `8db1a167`） | `Documents/Runs/*.json` 的 `formatVersion`、`samples`、`distance`、`endedAt`；checkpoint JSONL |
| 历史可见本次跑次 | `history.row` 数量 ≥ 1，且最新一行对应本次 `startedAt` | Release 候选包可断言 / (b) Release 候选包（sha256 `7258…` / commit `8db1a167`） | `background-history.png`；AX dump 中 `history.row`；跑次 JSON `startedAt` |
| 导出 GPX 落盘且可校验 | `.gpx` 真实存在、字节数 > 0、实算 sha256 为 64 位十六进制并与 `sha256.txt` 一致 | Release 候选包可断言 / (b) Release 候选包（sha256 `7258…` / commit `8db1a167`） | `Documents/Exports/*.gpx`；`sha256.txt` |
| 导出与采样一致 | GPX `trkpt` 数与 `samples` 数差值 ≤ 1；GPX 时间跨度与记录区间绝对差 ≤ 1 秒 | Release 候选包可断言 / (b) Release 候选包（sha256 `7258…` / commit `8db1a167`） | `.gpx` 的 `trkpt` 数 / 首末 `trkpt/time`；跑次 JSON `samples[]` |
| 锁屏态只读观测 | 只记录 `lockState` 观测值，不据此宣称锁屏后连续采样 | Release 候选包可断言 / (b) Release 候选包（sha256 `7258…` / commit `8db1a167`） | `report.md` 的 `lockState` 观测行；`lockstate-*.json` |

## 批次 B：候选包首屏审计 · Release 候选包可断言（`--phase=audit`）

证据来源类型统一为 **Release 候选包可断言**，构建身份统一为 **(b) Release 候选包（sha256 `7258…` / commit `8db1a167`）**；
若实际只能驱动 Debug 构建，则整表改标 **(a) Debug UI-test 构建** 并写明候选包未被驱动，不得混标。

| 断言项 | 判点（通过条件） | 证据来源类型与构建身份 | 具体取值路径 |
|---|---|---|---|
| 首屏五个读数位 | 可及树同时存在 `run.distance` / `run.elapsed` / `run.currentPace` / `run.averagePace` / `run.splits` 五个标识；任一缺失即 FAIL 并列出缺失标识与截图文件名 | Release 候选包可断言 / (b) Release 候选包（sha256 `7258…` / commit `8db1a167`） | `audit-runview.ax.json` 中五个 identifier；`audit-runview.png` |
| 三 Tab 可切换且各有内容 | Run / History / Settings 均可切换，且分别存在 `run.distance` / `history.empty` 或 `history.row` / `settings.announcementToggle` | Release 候选包可断言 / (b) Release 候选包（sha256 `7258…` / commit `8db1a167`） | `audit-run-tab.png`、`audit-history.png`、`audit-settings.png` 与对应 `*.ax.json` |
| 详情页导出入口可用 | 有归档时进入详情页，`runDetail.export` 存在、可见、可点击；无归档时记 FAIL 并写明原因与证据 | Release 候选包可断言 / (b) Release 候选包（sha256 `7258…` / commit `8db1a167`） | `audit-detail.png`、`audit-detail.ax.json`、`audit-result.json` 的 `detailExport.exists` / `.hittable` |
| 构建身份诚实 | `report.md` 记录实际驱动构建（bundle id、版本、配置、commit）；与候选 zip 非同一二进制时显式标注差异 | Release 候选包可断言 / (b) Release 候选包（sha256 `7258…` / commit `8db1a167`） | `report.md` 的「构建身份」段；`xcrun devicectl device info apps` JSON |
| 审计产物布局 | 每次 audit 落盘 ≥ 1 张 `.png`、≥ 1 份 `*.ax.json`、1 份 `report.md`；所列文件真实存在且非空 | Release 候选包可断言 / (b) Release 候选包（sha256 `7258…` / commit `8db1a167`） | `artifacts/device-audit/<UTC>/` 下文件清单；`report.md` 证据段 |

## Release 候选包「公里播报 + 音乐 duck」结论行

| 断言项 | 判点（通过条件） | 证据来源类型与构建身份 | 具体取值路径 |
|---|---|---|---|
| 公里播报 + 音乐 duck（Release 候选包） | **Debug 可断言 + Release 机器证据来自显式 launch-arg 确定性源（非真实移动）**：Debug UI-test 构建由遥测证明同一条公里契约；Release 候选包用 `-releaseDeterministicLocation km-crossing` 产出同一份 `telemetry.announcements[]`；真实 CoreLocation 只能人耳 | Debug 可断言 + Release 候选包可断言（确定性源，非真实移动）/ (a) Debug UI-test 构建可断言；(b) Release 候选包（`7258…` / commit `8db1a167` 及更早无确定性源；本项起的候选包见 `artifacts/candidates/Release-candidate-*.txt`）机器证据来自显式 launch-arg 确定性源，真实 CoreLocation 仍只能人耳 | Debug：`telemetry.announcements[].splitIndex` / `.categoryOptions` / `.duckRevoked`；Release：同一路径下的 `simulated` 样本 |
| Release 确定性源门控 | **默认关 + 仅设备验证场 + 不计入真实 CoreLocation 判据**：仅显式 `-releaseDeterministicLocation km-crossing` 时构造确定性源；缺值、取值以 `-` 开头、场景未知一律 fail-closed 回真实源且构造次数 0；样本 `sampleSource=simulated`，真实 CoreLocation 判据不受影响 | 本地代码断言 + 结构门 / (b) Release 候选包（本项起） | `ios/PurePaceTests/ReleaseDeterministicLocationSourceTests.swift` 的默认路径/flag 路径/公里边界用例；`scripts/check-ios-shell.sh` 的 `ac-release-deterministic-source` 断言块 |

- 原因：真实 CoreLocation 在无人静止场无法保证跨公里，真实定位的公里播报仍只能人耳；
  Release 候选包的机器证据来自显式 launch-arg 确定性源（`-releaseDeterministicLocation km-crossing`，
  默认关），样本标记 `simulated`，**不计入真实 CoreLocation 判据**。
- 对外文案只准写「Debug 构建 + 遥测验证 / Release 确定性源机器证据」，禁止写「真机已验证公里播报」
  或「候选包已验证真实定位」。
- 影响面：确定性源随 Release 编译进包（包体略增），只有显式 launch-arg 才被构造，
  缺值/未知场景 fail-closed 回真实源，正常用户不可达。

## 批次 C：只能人耳（最后一批，总数 ≤ 2）

| 断言项 | 判点（通过条件） | 证据来源类型与构建身份 | 具体取值路径 |
|---|---|---|---|
| 播报是否听清 | 人耳确认「第 1 公里，用时…」可听懂 | 只能人耳 / (a) Debug UI-test 构建；(b) Release 候选包只能人耳 | 机器断言不了的原因：语音合成可懂度不落入 `telemetry.announcements[]`、AX 树或截图，只能由人听；随机器证据一次性交回公司负责人 |
| 音乐 duck 后听感是否恢复 | 人耳确认播报期间音乐被压低、播报结束后音量恢复且无中断 | 只能人耳 / (a) Debug UI-test 构建；(b) Release 候选包只能人耳 | 机器断言不了的原因：遥测只能证明 `categoryOptions` / `duckRevoked` 参数已下发，不能证明扬声器实际听感；随机器证据一次性交回公司负责人 |

## 不进真机场的语义（指向单测 / 集成 / 模拟器层）

- Info.plist 用途说明与 `UIBackgroundModes` 声明：`scripts/check-ios-shell.sh` 结构断言 + 工程配置审查。
- 每公里播报开关默认值/持久化：`PurePaceTests` 单测 + 模拟器 `RunFlowUITests.testAnnouncementTogglePersistsAcrossRelaunch`。
- 时间/配速/距离格式化：`ios/Core` 与 `ios/RunCore` 单元测试。
- 会话状态机与四态（ready/running/paused/finished）：`ios/RunCore` 单测。
- 阈值 / checkpoint 频率 / 分段连续性：`ios/RunCore` 单测。

## pending: 待人现场（needs-you 单点）清单

- 锁屏态本版不验；如公司要求补，只由人在**最终候选包**上做一次「电源键 + 解锁」（≤ 30 秒），
  由公司另排，产品侧不得自行加进脚本或窗口。
- 批次 C 的两条人耳判定随机器证据一次性交回公司负责人。
- `--phase=audio` / `--phase=background` 正式场待本清单经 PO 转公司确认后执行：`pending: 待公司确认`。
