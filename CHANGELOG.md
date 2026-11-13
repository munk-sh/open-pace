# Changelog

本仓的版本变更记录在此。格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号口径遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)；版本号的唯一真源仍是仓库根 [`VERSION`](./VERSION)，本文件首条与 README 版本表首行只镜像该值，三者不一致时 `scripts/check-baseline.sh` 判红。

## [0.1.0] - 2026-11-14

状态：**未发布（候选）**。本条目只陈述已交付事实，不构成任何发布声明。

### Added

- V1 跑步闭环：一键开跑 → 后台记录 → 每公里语音播报（不打断音乐）→ 结束保存 → 历史 → GPX 1.1 导出与系统分享。
- 本地优先的数据口径：无账号、无广告、无社交，跑次数据与导出文件只留在本机。
- iOS 分发归档与静态门：`scripts/archive-ios.sh` 支持 `DRY_RUN=1` 脱敏预演，`scripts/check-ios-release.sh` 校验归档契约与 Runbook。
- Android 骨架工程：Gradle wrapper + Compose，JVM 单测腿真实执行 `testDebugUnitTest`。

### Known limitations

- 界面语言为 zh-Hans 单语，没有其它本地化版本。
- 真机项（锁屏记录、定位授权、人耳听感）`pending: 待人现场`，按 `docs/device-manual-acceptance.md` 执行。
- Dynamic Type 未跟随系统缩放：生产 `Typography.control` 为固定 20pt 档。
- 构建产物不可逐字节复现（主二进制内嵌 57 处派生数据路径字符串，`LC_UUID` 每次链接随机），验收只认 zip sha256 与包内 `Info.plist` 实际数组；详见 `docs/release/` 下 release notes 的 Build reproducibility 段。
