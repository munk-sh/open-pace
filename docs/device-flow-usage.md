# 真机自动化取证使用说明

对应脚本：`scripts/verify-ios-device-flow.sh`（**需真机连接**）。
断言清单：`docs/device-assertion-matrix.md`。

## 用法

```bash
bash scripts/verify-ios-device-flow.sh --help
bash scripts/verify-ios-device-flow.sh --phase=audit
bash scripts/verify-ios-device-flow.sh --phase=audio
bash scripts/verify-ios-device-flow.sh --phase=background --candidate /path/to/PurePace-Release-*.zip
```

- 目标设备默认 `00008101-001C701E0A68001E`，可用 `--device <udid>` 或 `PUREPACE_DEVICE_UDID` 覆盖。
- 候选包用 `--candidate <zip>` 或 `PUREPACE_CANDIDATE_ZIP` 指定；缺省时匹配
  `artifacts/candidates/PurePace-Release-*.zip`。脚本不复制 zip 进仓库。
- 签名只在 `xcodebuild` 命令行临时传入（`-allowProvisioningUpdates DEVELOPMENT_TEAM=… CODE_SIGNING_ALLOWED=YES
  CODE_SIGN_STYLE=Automatic`），工程文件不落团队/证书配置。

## 三模式

| 模式 | 构建 | 做什么 | 主要证据 |
|---|---|---|---|
| `--phase=audit` | Release | 首屏审计：五个读数位 / 三 Tab / 详情导出入口 | `audit-*.png`、`audit-*.ax.json`、`audit-result.json`、`report.md` |
| `--phase=audio` | Debug + `-uiTestLocation` | 跨一次公里边界 + 音源在播（默认 runner 自播合成音）+ duck 遥测；同用例再跑一遍 `--music-strategy=none` 负对照 | `audio-*.png`、`run-*.json`、`announcements-*.json`、`music-source.json`、`.gpx`、`sha256.txt` |
| `--phase=background` | Release | 开跑 → 起音源 → `press(.home)` → Mac 侧等 5–6 分钟 → 回前台结束保存/历史/导出 | `background-*.png`、`run-*.json`、`announcements-*.json`、`active-run.jsonl`、`.gpx`、`sha256.txt` |

音源由 `--music-strategy` 决定，默认 `runner`：

| 取值 | 音源 | 说明 |
|---|---|---|
| `runner`（默认） | UITests runner 自播 `ios/PurePaceUITests/Fixtures/runner-music-loop.wav` | 无人操作、无需外部 App；对被测 App 即他路音频，`isOtherAudioPlaying` 可归因 |
| `app` | `--music-bundle-id` 指定的 App（默认 `com.apple.Music`） | 需人工/设备已登录该 App，起播失败如实记 `false` |
| `none` | 无音源（负对照） | `playerStarted == false`，duck 相关项记 `not-applicable`，不得记 pass |

`--music-bundle-id <id>` 仅对 `app` 策略生效。合成音源由 `scripts/gen-ios-test-audio.sh` 幂等生成
（纯 Python 标准库，无网络），产物 ≤ 200 KB 且入库。

`background` 为两段式：阶段一在设备端开跑并 `press(.home)` 后立即结束；6 分钟等待放 Mac 侧
（宿主 sleep + `devicectl` 只读读容器）；阶段二 `activate()` 回前台完成结束保存与导出。
**不在测试进程内 sleep 断言后台连续性。**

## Release 确定性源（仅设备验证场）

Release 候选包内置一条显式 launch-arg 门控的确定性定位源，用于在无人静止场跨过 1 km。**默认关**：

```bash
xcrun devicectl device process launch --device <udid> --terminate-existing sh.munk.purepace \
  -- -releaseDeterministicLocation km-crossing
```

- flag 语法：`-releaseDeterministicLocation <scenario>`；当前唯一场景为 `km-crossing`——
  经度固定、纬度每 1.0 s 推进 20 m，从跑步开始后的首个位置锚点起约 50 步跨过 1 km，
  因此 60–90 秒跑动内恰好跨一次公里边界。
- 默认关：参数缺省、缺少取值、取值以 `-` 开头或场景名未知时，一律回真实 `RunLocationSource()`，
  确定性源不会被构造；正常用户启动路径没有任何注入入口。
- 能力如实：样本 `sampleSource` 记为 `simulated`，授权快照为 `authorizedWhenInUse`，
  `allowsBackgroundLocationUpdates = false`、`pausesLocationUpdatesAutomatically = false`；
  不请求授权、不触碰系统定位管理器、不读写磁盘、不做播报。
- 判据边界：`simulated` 样本**不计入真实 CoreLocation 判据**。本场景只用于
  「跨公里播报 + 音乐 duck」的机器证据（`telemetry.announcements[]` 中 `splitIndex == 1`、
  `trigger == kilometerCompleted`），不证明真实移动、锁屏定位或后台连续性。
- 本项只提供「仅设备验证场」的确定性证据，不写「真机已验证」；真实移动结论仍以
  `--phase=background` 与人耳判定为准。

## 证据路径

- 每次运行：`artifacts/device-audit/<UTC 时间戳>/`
  - 截图序列（`.png`）、可及树（`*.ax.json`）、结果 JSON（`*-result.json`）
  - 容器跑次 JSON（`run-*.json`）、播报抽取（`announcements-*.json`）
  - 导出 GPX（`*.gpx`）与实算 `sha256.txt`
  - `report.md`：逐项 PASS/FAIL、构建身份、失败项、`pending` 清单
- 中间产物（result bundle、DerivedData、容器副本）只在 `.build/device-flow/`，已被 gitignore。

## 口径与边界

- 不做锁屏/解锁驱动；唯一前后台动作是 `press(.home)`。锁屏态本版不验。
- 背景结论只写「切后台后进程存活 + 持续采样」，不得写成「锁屏后仍出样本」；
  该结论依赖「设备不锁屏」前提，不外推。
- 人耳判定收敛到 ≤ 2 条，只出现在断言清单最后一批，随机器证据一次性交回公司负责人。
- 不修改业务源码、不改 `.munk/code-gates.json` 与 CI；本脚本不进 code_gates。
