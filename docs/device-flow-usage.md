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
| `--phase=audio` | Debug + `-uiTestLocation` | 跨一次公里边界 + 系统 Music 在播 + duck 遥测 | `audio-*.png`、`run-*.json`、`announcements-*.json`、`.gpx`、`sha256.txt` |
| `--phase=background` | Release | 开跑 → 起 Music → `press(.home)` → Mac 侧等 5–6 分钟 → 回前台结束保存/历史/导出 | `background-*.png`、`run-*.json`、`announcements-*.json`、`active-run.jsonl`、`.gpx`、`sha256.txt` |

`background` 为两段式：阶段一在设备端开跑并 `press(.home)` 后立即结束；6 分钟等待放 Mac 侧
（宿主 sleep + `devicectl` 只读读容器）；阶段二 `activate()` 回前台完成结束保存与导出。
**不在测试进程内 sleep 断言后台连续性。**

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
