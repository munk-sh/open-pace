# PurePace 0.1.0 Release Notes（双语草稿）

> 状态：V1 收口候选，**尚未发布**。本文件是候选阶段的 release notes 草稿，供交付评审与后续发布改写使用；任何对外发布动作都不在本文件范围内。

## 中文

### 本版是什么

这是 PurePace 的 V1 收口候选：核心跑步闭环已实现并跑通代码层门与模拟器门，真机终验仍由人按 `docs/device-manual-acceptance.md` 执行（`pending: 待人现场`）。当前尚未发布，候选身份为版本 `0.1.0(1)`。

### 闭环能力

一键开跑 → 后台记录 → 每公里语音播报不打断音乐 → 结束保存 → 历史 → GPX 导出/分享。

- 一键开跑：进入跑步页点「开始跑步」即开始记录，无需账号或联网。
- 后台记录：锁屏或切到后台后继续记录，回前台仍处同一记录的计时界面。
- 每公里语音播报：每公里播报距离 / 配速 / 用时，不打断正在播放的音乐，播报结束后音乐恢复。
- 结束保存：结束并保存本次记录。
- 历史：按时间列出跑次，可进详情查看本次记录。
- GPX 导出 / 分享：从跑次详情导出 GPX 1.1 文件，经系统分享面板保存或发送。

### 隐私

无账号、无广告、无社交，数据只留在本机。

### 已知限制（如实）

1. **界面语言只有简体中文**：UI 为 zh-Hans 单语，没有其他语言的本地化版本。
2. **真机终验待人现场**：agent 与 CI 只跑模拟器与代码层；真机锁屏、定位授权、人耳听感等项均 `pending: 待人现场`，按 `docs/device-manual-acceptance.md` 执行。
3. **Dynamic Type 未跟随系统缩放**：生产 `Typography.control` 是固定 20pt 档（`Font.system(size:)`，取自 `DesignTokens.Typography.titleSize = 20`），不随 Dynamic Type 缩放；AX5 仅由注入式几何断言（门断言）覆盖，属测试注入几何而非运行态实测，不得表述为「AX5 档已覆盖」。
4. **构建产物不可逐字节复现**：主二进制内嵌 57 处派生数据路径字符串，且 `LC_UUID` 每次链接随机、连带 CDHash / CMS 摘要变化，因此 exec sha 跨派生数据路径不可复现；本版不声明逐字节复现的构建属性，验收只认 zip sha256 + 包内 `Info.plist` 的 `UIBackgroundModes` 实际数组，exec sha 仅作辅助记录。

### 版本口径

- 本次验收候选 = `0.1.0(1)`（`CFBundleShortVersionString` 0.1.0 / `CFBundleVersion` 1）。
- 发布用版本号提升必须在新切点重出候选并重算 zip sha256：版本号变化即视为新候选，旧候选不能沿用。
- 旧包原样保留，不覆盖、不删除、不改名；在候选记录里注明其作废原因，供追溯。
- `VERSION` 文件是本仓版本唯一真源；本次收口对 `VERSION` 零改动。

## English

Draft release notes for the PurePace 0.1.0 V1 close-out candidate. **Not released yet.** This document exists for delivery review; it does not authorize any store submission.

### What this version is

This is the V1 close-out candidate: the core running loop is implemented and passes the code-level gates and the simulator gates. Final acceptance on a physical device is still performed by a person following `docs/device-manual-acceptance.md` (`pending: on-site human`). Nothing has been released; the acceptance candidate is version `0.1.0(1)`.

### Closed-loop capabilities

Start a run in one tap → background recording → per-kilometer voice announcements that do not interrupt music → finish and save → history → GPX export/share.

- One-tap start: tap "Start Run" on the run screen to begin recording; no account or network needed.
- Background recording: recording continues while the screen is locked or the app is in the background, and returning to the foreground shows the same run timer.
- Per-kilometer announcements: distance, pace, and elapsed time every kilometer, without cutting off the music that is playing; music resumes afterwards.
- Finish and save: end and save the current run.
- History: runs listed by time, with a detail view for each run.
- GPX export/share: export a GPX 1.1 file from the run detail and save or send it through the system share sheet.

### Privacy

No account, no ads, no social features; all data stays on the device.

### Known limitations (stated plainly)

1. **Simplified Chinese UI only**: the interface is zh-Hans mono-lingual with no other localization.
2. **Final physical-device acceptance is on-site pending**: agents and CI only cover the simulator and code levels; screen-lock behaviour, location permission, and human listening checks remain `pending: on-site human`, per `docs/device-manual-acceptance.md`.
3. **Dynamic Type does not scale**: the production `Typography.control` is a fixed 20pt step (`Font.system(size:)`, from `DesignTokens.Typography.titleSize = 20`) and does not follow Dynamic Type. AX5 is covered only by injected geometry assertions (gate assertions), which are injected test geometry rather than runtime measurements, so this must not be described as "AX5 supported".
4. **The build is not byte-for-byte reproducible**: the main binary embeds 57 derived-data path strings, and `LC_UUID` is random on every link (changing CDHash / CMS digests), so the exec sha is not reproducible across derived-data paths. This version claims no byte-for-byte reproducible build property; acceptance relies only on the zip sha256 plus the `UIBackgroundModes` array actually read from the packaged `Info.plist`, with the exec sha kept as an auxiliary record.

### Version policy

- Acceptance candidate = `0.1.0(1)` (`CFBundleShortVersionString` 0.1.0 / `CFBundleVersion` 1).
- Any release version bump requires a new cut, a rebuilt candidate, and a recomputed zip sha256; a version change means a new candidate and the previous one cannot be reused.
- Old packages are kept as-is: never overwritten, deleted, or renamed. The candidate record notes why a package became obsolete so history stays traceable.
- The root `VERSION` file is the single source of truth for the version; this close-out makes zero changes to it.
