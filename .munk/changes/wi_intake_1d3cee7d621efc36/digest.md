# A 项（wi_intake_1d3cee7d621efc36）Digest（事实回填）

> 本文件由 B 项（wi_intake_7b9d19bc1e3be0ee）补事实，只记录可复核事实，不重写 A 的 `prd.md` 结论。

## 实现与合并 commit

- 实现 commit：`67ff54baa6d6ff8e9487c6d8abf9f15f7d91ae2d` — `feat(design): 方向 A 石墨+竞速橙色板落地 + 轨迹几何纯逻辑 + 历史列表轻量索引`。
- 合并 commit：`f907fafa42d333720d1c4b0e6db1461e06d7990a` — `merge: 方向 A 色板 + 轨迹几何纯逻辑 + 历史列表轻量索引（wi_intake_1d3cee7d621efc36）`。
- 复核方式：`git cat-file -t <sha>` 返回 `commit`，`git show --stat --oneline <sha>` 可读。

## A 的改动路径（`git show --stat 67ff54b` 原文摘录）

- `ios/PurePace/Design/DesignTokens.swift`（+65/− 改动）
- `ios/PurePace/Design/ContrastPolicy.swift`
- `ios/RunCore/Sources/PurePaceRunCore/TrackGeometry.swift`（新文件 192 行）
- `ios/RunCore/Sources/PurePaceRunCore/RunArchiveStore.swift`（+226，含 `RunRecordSummary` / `listSummaries()` / `record(withID:)`）
- `docs/design/palette-a.md`（新文件）
- `docs/evidence/palette-a-contrast.txt`（新文件 97 行）
- 基线同步：`.munk/baseline/design/foundations.md`、`.munk/baseline/domains/design-palette-a/product.md`、`.munk/baseline/domains/ios-track-render/product.md` 等

## A 的测试与门脚本路径

- `ios/PurePaceTests/DesignTokensTests.swift`（+219）
- `ios/PurePaceTests/ContrastPolicyTests.swift`
- `ios/RunCore/Tests/PurePaceRunCoreTests/TrackGeometryTests.swift`（新文件 156 行，8 个用例）
- `ios/RunCore/Tests/PurePaceRunCoreTests/RunArchiveStoreTests.swift`（+72）
- `scripts/check-ios-shell.sh`（+41：palette hex 复核与 identifier 冻结口径）

## 现场可复核结论（B 项执行时实测）

- `swift test --package-path ios/RunCore`：173 个用例 0 失败（含 `DocsVerificationMatrixTests` 与 `TrackGeometryTests`）。
- `bash scripts/check-ios-shell.sh`：29 项断言 0 失败，`ac-design-tokens` 实测 identifier 计数 42（冻结 33 + 新增 9），`demo/示例入口: 0`；`ac-built-plist-readback` 因无 `.build/ios` 模拟器产物 SKIP。
- 既有阈值事实：`TrackGeometry.simplificationEpsilonMeters == 3.0`、`maxSegmentGapSeconds == 60`、相机 padding 合法区间 0.08–0.12，均由 A 落地且 B 未改动。

## 已知偏差

- `EvidenceCaptureUITests/testEvidenceAx5Layout` 存在顺序依赖（C 项取证套件遗留），A/B 均未修，仅如实标注。
- 真机项一律 `pending: 待人现场`。
- A 的 `prd.md` 中引用的「digest §3 方向 A 表 / §3.4 禁区」在 A 目录下当时没有 digest 文件；本文件只补 commit、路径、测试与门禁事实，不补写色表内容。
