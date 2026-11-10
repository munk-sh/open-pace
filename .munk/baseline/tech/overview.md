# Tech overview

Thin technical baseline (SSOT).

- 会话恢复与锁屏接缝的 additive 口径（`RunSessionOrchestrator.init(restoring:)`、`RunSessionViewModel.makeRestored`、`duplicateSampleCount`、`protected-data` 只观察不驱动会话）见 `domains/ios-run-resilience/product.md` 的实现约束；不给既有 public 契约加必填参数、不接生产启动流程。
