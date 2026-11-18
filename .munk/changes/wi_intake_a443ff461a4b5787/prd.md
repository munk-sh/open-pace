# 补两条定位失败断言的变异红证与矩阵回填（证据项，不改产品行为）

## 范围

- 针对 main `90bb205a` 引入的 `testLocationFailureAndServicesOffSetUnavailableAndExposeCopy` 与 `testRecoveryAfterLocationFailureReturnsReady`（`ios/PurePaceTests/RunPermissionAndDiagnosticsTests.swift`），补「变异必红」证据：把仓库复制到 /tmp 后，分别 (a) 去掉 `start()` 里的 `servicesEnabled` 前置检查、(b) 断开 `locationManagerDidFail` 到 `lastLocationErrorCode` 的转发、(c) 让 `resolve` 不在恢复时清空错误码，跑同一断言须如实红；仓库零改动（`git status` 为空），红/绿日志绑 commit 落 `docs/evidence/wi_intake_<本项id>/`。
- `docs/verification-matrix.md` 中「定位失败 / 定位服务关闭」对应行回填：断言名 + 反例（上述三种变异）+ 证据路径 + 归属项。
- 不改任何生产代码、不加新断言、不动文案与 identifier。

## 验收

- ac-mutation-red: 三种变异各自在 /tmp 副本内使对应断言红，日志含失败断言原文与 `XCTAssert` 位置；仓库 `git status --porcelain` 为空、HEAD 未变。
- ac-mutation-green: 同一 commit 未变异时两条断言绿，日志含执行用例数与 0 failures。
- ac-matrix-row: `docs/verification-matrix.md` 对应行不再是 pending/缺口，归属项为本项 id，证据路径与上面日志一致。
- ac-no-prod-change: `git diff --stat` 相对 `90bb205a` 只含 `docs/` 与 `.munk/` 下证据与矩阵文件，无 `ios/` 源码改动。

## 非目标

- 不改产品行为、不修 `resolve` 的判定顺序（denied + 服务关闭会被压成 unavailable 已知局限，另项再议）、不动 VERSION、不碰 CI 工作流、不做真机。

## 实现约束

- 变异只在 /tmp 副本内做，仓库内不得出现临时改动；日志与断言原文直接粘贴，不写「已验证」这类无证据结论。
- 矩阵断言只写结构不变量，不写死行数/接缝总数。

## 本单执行约束（不 fold）

- 预算 ≤1M token / ≤25 分钟墙钟；到点交未闭合回执。
- 只许写 `docs/`、`.munk/` 与 `.munk/changes/**`，禁改 `ios/`。
- commit 按面拆：fold（矩阵 / 证据文档）与 prd 不得同 commit。
- 回执列实际命令与结果；不建卡、不派直装、不做上传。
