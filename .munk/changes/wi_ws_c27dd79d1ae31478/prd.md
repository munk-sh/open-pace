# 详情页 GPX 导出与系统分享

## 范围

在已有跑次详情页（`ios/PurePace/History/RunDetailView.swift`）上补齐"导出并分享"：

1. **导出目录归口**：`ios/PurePace/Run/RunStorage.swift` 新增导出目录构造（App 沙盒 `Documents/Exports/`），与归档/checkpoint 一致由 `FileManager` 推导，不写死绝对路径；提供可注入 `FileManager`/目录的入口，供 XCTest 指向临时目录。
2. **真实落盘导出**：详情页点击导出后，直接复用 RunCore 已交付的 `RunGPXExporter`（内部复用 `GPXCodec.write`）把**该跑次归档中的真实 `RunRecord.samples`** 写成 `.gpx` 文件；导出后校验目标文件在磁盘上真实存在且非空，再更新界面状态。禁止用夹具、内存字符串或网络冒充导出文件。
3. **系统分享**：落盘成功后才渲染 SwiftUI `ShareLink(item:)` 分享入口（不引入 UIKit / `UIActivityViewController`）；取消分享不删除文件，导出代码不注册任何清理动作。
4. **重复导出不覆盖**：沿用 `RunGPXExporter` / `RunRecordNaming` 的递增后缀命名，同一跑次多次导出产生不同文件，既有文件内容不被改写。
5. **失败态诚实**：采样为空或写盘失败时展示导出失败态，不提供分享入口、不伪造成功。
6. **门禁同步**：更新 `scripts/check-ios-shell.sh` 的源码清单、详情页稳定标识断言、测试落点清单与夹具禁令口径，并补 XCTest / XCUITest。

## 验收

- ac-export-writes-real-file: 以临时目录注入导出目录后，对含非空 `samples` 的 `RunRecord` 执行导出，返回 URL 在磁盘上真实存在、扩展名为 `.gpx`、字节数 > 0，且 `GPXCodec.read(from:)` 回读的点位数量与时间戳序列与 `record.samples` 完全一致。
- ac-export-no-overwrite: 同一 `RunRecord` 连续导出两次返回两个不同路径，两个文件同时存在，首次导出的文件内容回读仍与原始采样一致（未被覆盖）。
- ac-export-empty-samples-fails: `samples` 为空的记录导出抛错，且导出目录中不新增任何 `.gpx` 文件；详情页对应展示失败态标识 `runDetail.exportFailed` 且不出现 `runDetail.share`。
- ac-export-dir-documents-exports: 未注入目录时 `RunStorage` 构造的导出目录等于注入 `FileManager` 的 `Documents/Exports`（用临时目录伪造 `.documentDirectory` 断言），源码中不出现写死的绝对路径。
- ac-share-after-landing: 导出成功后详情页出现导出完成态 `runDetail.exported`（文本含导出文件名且以 `.gpx` 结尾）与分享入口 `runDetail.share`；未导出成功时这两个标识都不存在（分享入口严格晚于落盘）。
- ac-no-fixture-no-network: 导出链路不读取 `shared/fixtures`/内置样例、不用内存字符串直接当文件返回、不使用网络（App 源码无 `URLSession`/`Network` import）；App import 允许表不新增 UIKit。
- ac-shell-updated: `scripts/check-ios-shell.sh` 的源码清单包含新增导出源文件，详情页标识断言包含 `runDetail.export` / `runDetail.exported` / `runDetail.share`（失败态含 `runDetail.exportFailed`），单元测试落点清单包含导出测试文件，UI 测试标识清单同步扩展；原"App 源码出现 `.gpx` 即失败"的夹具断言收窄为仅禁止 `shared/fixtures`/样例引用（保留反例自检，不得退化为通配放宽），并新增"导出必须经 `RunGPXExporter` 且目录由 `RunStorage` 构造"的正向断言。
- ac-xcuitest-export: 真实跑次详情页点击 `runDetail.export` 后，`runDetail.exported` 出现且文件名以 `.gpx` 结尾、`runDetail.share` 存在；若系统分享面板出现则额外确认，不作为唯一判据（不使用固定 `sleep`）。
- ac-gates-green: `lint-ios-shell` / `build-ios` / `test-ios` / `test-ios-run-core` 全绿，现有 23 门不减少、`command` 保持单一 argv。

## 非目标

- 不做导出文件的**外部**解析验证（`xmllint` / 独立解析器）与模拟器容器内真实文件取证脚本——那是波 3「端到端脚本」子项的交付物，本项只保证 App 内 `GPXCodec` 回读一致。
- 不做导出文件列表页、导出历史、删除/清理导出文件、批量导出、iCloud 或 AirDrop 专门适配。
- 不引入 UIKit / `UIActivityViewController` / `UIDocumentPicker`，不替换成自定义分享 UI。
- 不改 RunCore 契约：`RunGPXExporter`、`RunRecordNaming`、`GPXCodec` 字段顺序与命名规则原样复用；不新增编码器、不在 App 侧重算或补造采样点。
- 不做地图、轨迹可视化、GPX 导入。
- 不做真机验证、不产出真机结论，不改 `.github/workflows/*`。
- 不改归档存储格式、历史列表/详情既有字段与空态语义。

## 实现约束

- **复用面**：导出必须走 `RunGPXExporter(directoryURL:).export(record)`；文件名/去重由 Core 的 `RunRecordNaming` 决定，App 侧不得自造命名规则。
- **注入点**：`RunStorage` 增加导出目录与导出器构造（含可注入 `FileManager`），`HistoryView` → `RunDetailView` 透传导出能力，`ContentView` 用 `RunStorage` 构造后注入；`check-ios-shell.sh` 现有 `RunDetailView(record:` 断言子串必须继续成立。
- **视图薄层**：导出动作与状态（成功文件 URL / 失败原因）放在可单测的小类型（如 `History/` 下新增的导出状态类型）或纯函数里，`RunDetailView` 只做按钮绑定、`ShareLink` 渲染与状态展示；不得在 View 内拼 GPX 内容。
- **标识契约**：新增 `runDetail.export`（按钮）、`runDetail.exported`（成功态文本，含文件名）、`runDetail.share`（`ShareLink`）、`runDetail.exportFailed`（失败态）；已有 `runDetail.*` 标识一律保留。
- **测试落点**：新 XCTest 放 `ios/PurePaceTests/`（临时目录 + 真实文件 + `GPXCodec.read` 回读），新断言并入 `ios/PurePaceUITests/RunFlowUITests.swift` 的既有真实流程（结束→历史→详情→导出），不新增固定 sleep，不依赖网络。
- **门禁口径**：`check-ios-shell.sh` 只做精确收窄 + 正向新增，必须保留反例自检（其它目录出现 CoreLocation/AVFoundation 仍判失败等既有反例），不得改成通配允许表。
- **证据口径**：结论只写「模拟器链路通过」「导出逐字段对齐通过（App 内回读）」，不写"真机已验证"；外部解析与容器取证明确标注留待波 3。
