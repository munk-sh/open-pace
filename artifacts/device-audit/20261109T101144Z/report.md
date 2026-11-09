# 真机取证报告（audit）

- 口径：真机自动化取证（需真机连接）
- 阶段：`audit`，构建配置：`Release`
- 目标设备：iPhone 12 Pro Max（UDID `00008101-001C701E0A68001E`，iPhone13,4 / iOS 18.7.8 build 22H352）
- 起止时间：2026-11-09T10:11:44Z → 2026-11-09T10:12:15Z
- 用例：`PurePaceUITests/DeviceFlowUITests/testAuditFirstScreenAndTabs`
- 结论：机器断言通过

- 实际驱动构建：bundle com.chaxiu.purepace / version 0.1.0 / build 1 / 配置 Release / commit a45922265e38
- 候选包 zip：/Users/zhutao/Library/Application Support/Munk-AI/munk-auto/products/codebase_19e8ad47434ff059/artifacts/candidates/PurePace-Release-0.1.0-20261109T084100Z.zip（sha256 `7258d2e3f7984ef2557278bd1fcdd1eea5db1f34a4d549dc8071d7afcd5b9d8f`，407275 字节）
- 二进一致性：本脚本只驱动当前 worktree 的 xcodebuild 构建，未解包比对候选 zip 内 `.app` 二进制；若实际驱动构建与候选 zip 非同一二进制，报告按「实际驱动构建 ≠ 候选包二进制」口径记录，不宣称「候选包已验证」。

## 断言逐项

| 断言项 | 结果 | 证据 / 说明 |
|---|---|---|
| `audit-screenshot-audit-runview.png` | PASS | 截图 audit-runview.png 存在且非空 |
| `audit-screenshot-audit-run-tab.png` | PASS | 截图 audit-run-tab.png 存在且非空 |
| `audit-screenshot-audit-history.png` | PASS | 截图 audit-history.png 存在且非空 |
| `audit-screenshot-audit-settings.png` | PASS | 截图 audit-settings.png 存在且非空 |
| `audit-ax-audit-runview.ax.json` | PASS | 可及树 audit-runview.ax.json 存在且非空 |
| `audit-ax-audit-run-tab.ax.json` | PASS | 可及树 audit-run-tab.ax.json 存在且非空 |
| `audit-ax-audit-history.ax.json` | PASS | 可及树 audit-history.ax.json 存在且非空 |
| `audit-ax-audit-settings.ax.json` | PASS | 可及树 audit-settings.ax.json 存在且非空 |
| `audit-ax-audit-detail.ax.json` | PASS | 可及树 audit-detail.ax.json 存在且非空 |
| `audit-runview-five-metrics` | PASS | 五读数位: run.distance=PASS, run.elapsed=PASS, run.currentPace=PASS, run.averagePace=PASS, run.splits=PASS |
| `audit-three-tabs` | PASS | Run/History/Settings 逐项: run=PASS, history=PASS, settings=PASS |
| `audit-detail-gpx-entry` | PASS | runDetail.export exists=True hittable=True 归档可用=True |
| `audit-build-identity` | PASS | 实际驱动构建 bundle com.chaxiu.purepace / 配置 Release / commit a45922265e38；与候选 zip 的同一性未解包比对，按口径显式标注 |

## 失败项

- 无

## 证据文件

- `analysis.json`（3693 字节）
- `attachments-manifest.json`（818 字节）
- `audit-detail.ax.json`（9987 字节）
- `audit-detail.png`（173006 字节）
- `audit-history.ax.json`（10165 字节）
- `audit-history.png`（172055 字节）
- `audit-result.json`（757 字节）
- `audit-run-tab.ax.json`（3660 字节）
- `audit-run-tab.png`（114486 字节）
- `audit-runview.ax.json`（3660 字节）
- `audit-runview.png`（115353 字节）
- `audit-settings.ax.json`（3957 字节）
- `audit-settings.png`（107791 字节）

## pending: 待人现场（needs-you 单点）

- 锁屏态本版不验；如公司要求补，只由人在最终候选包上做一次「电源键 + 解锁」（≤ 30 秒），由公司另排，产品侧不得自行加进脚本或窗口。
- 人耳判定（≤ 2 条）随机器证据一次性交回公司负责人：播报是否听清；音乐 duck 后听感是否恢复。
