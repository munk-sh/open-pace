# PurePace Release Notes (0.1.0)

> Status: V1 close-out candidate. **Not released yet.** This document is a draft for delivery review; it authorizes no tag, no store submission, and no distribution.

## What's in this release

PurePace is a running timer and calorie log that does not interrupt you: no account, no ads, no social features.

- One-tap start: tap "Start Run" to begin recording; no account or network needed.
- Background recording: recording continues while the screen is locked or the app is in the background; returning to the foreground shows the same run timer.
- Per-kilometer voice announcements: distance, pace, and elapsed time every kilometer without cutting off the music that is playing; music resumes afterwards.
- Finish and save: end and save the current run.
- History: runs listed by time, each with a detail view.
- GPX export/share: export a GPX 1.1 file from the run detail and hand it to the system share sheet.

## What's covered

Verification for this candidate covers the code layer and the simulator layer:

- Local L1 gates: shell and static contract assertions, `swift build` / `swift test` for `ios/Core` and `ios/RunCore`, and Android `assembleDebug` + `testDebugUnitTest`.
- Simulator layer: the authoritative full unit + UI leg runs in `.github/workflows/ios.yml` on push.
- Acceptance candidate identity: `CFBundleShortVersionString` 0.1.0 / `CFBundleVersion` 1, derived from the root `VERSION` file.

### Build reproducibility

The build is not byte-for-byte reproducible: the main binary embeds 57 derived-data path strings, and `LC_UUID` is random on every link (which also changes CDHash / CMS digests), so the exec sha does not reproduce across derived-data paths. This release claims no byte-for-byte reproducible build property; acceptance relies only on the zip sha256 plus the `UIBackgroundModes` array actually read from the packaged `Info.plist`, with the exec sha kept as an auxiliary record.

## Privacy

No account, no ads, no social features; all run data and exported files stay on the device.

## Known limitations

1. **Simplified Chinese UI only**: the interface is zh-Hans mono-lingual with no other localization.
2. **Physical-device checks are on-site pending**: agents and CI only cover the simulator and code layers; screen-lock recording, location permission, and human listening checks remain `pending: 待人现场`, per `docs/device-manual-acceptance.md`.
3. **Dynamic Type does not scale**: production `Typography.control` is a fixed 20pt step (`Font.system(size:)`, from `DesignTokens.Typography.titleSize = 20`) and does not follow Dynamic Type. AX5 is covered only by injected geometry assertions, which are injected test geometry rather than runtime measurements, so this must not be described as "AX5 supported".

<details>
<summary>简体中文</summary>

### 本版是什么

PurePace 的 V1 收口候选：核心跑步闭环已实现并跑通代码层门与模拟器门。**尚未发布**，本文档是交付评审草稿，不授权任何 tag、商店提交或分发动作。

### 闭环能力

一键开跑 → 后台记录 → 每公里语音播报（不打断音乐）→ 结束保存 → 历史 → GPX 1.1 导出与系统分享。

### 验收覆盖

本地 L1 门（shell 与结构断言、`ios/Core` 与 `ios/RunCore` 的 `swift build` / `swift test`、Android `assembleDebug` + `testDebugUnitTest`）与模拟器层；全量单测 + UI 权威腿在 `.github/workflows/ios.yml` 的 push 上执行。构建产物不可逐字节复现（主二进制内嵌 57 处派生数据路径字符串、`LC_UUID` 每次链接随机），验收只认 zip sha256 与包内 `Info.plist` 的 `UIBackgroundModes` 实际数组。

### 隐私

无账号、无广告、无社交，跑次数据与导出文件只留在本机。

### 已知限制（如实）

1. 界面语言只有简体中文（zh-Hans 单语），没有其它本地化版本。
2. 真机终验 `pending: 待人现场`：锁屏记录、定位授权、人耳听感等项由人按 `docs/device-manual-acceptance.md` 执行。
3. Dynamic Type 未跟随系统缩放：`Typography.control` 固定 20pt 档，不随系统缩放；AX5 仅由注入式几何断言覆盖，属测试注入几何而非运行态实测。

</details>
