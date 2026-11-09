# 真机取证报告（audit）

- 口径：真机自动化取证（需真机连接）
- 阶段：`audit`，构建配置：`Release`
- 目标设备：iPhone 12 Pro Max（UDID `00008101-001C701E0A68001E`，iPhone13,4 / iOS 18.7.8 build 22H352）
- 起止时间：2026-11-09T10:07:05Z → 2026-11-09T10:07:36Z
- 用例：`PurePaceUITests/DeviceFlowUITests/testAuditFirstScreenAndTabs`
- 结论：存在失败项

- 实际驱动构建：bundle com.chaxiu.purepace / version 0.1.0 / build 1 / 配置 Release / commit a45922265e38
- 候选包 zip：/Users/zhutao/Library/Application Support/Munk-AI/munk-auto/products/codebase_19e8ad47434ff059/artifacts/candidates/PurePace-Release-0.1.0-20261109T084100Z.zip（sha256 `7258d2e3f7984ef2557278bd1fcdd1eea5db1f34a4d549dc8071d7afcd5b9d8f`，407275 字节）
- 二进一致性：本脚本只驱动当前 worktree 的 xcodebuild 构建，未解包比对候选 zip 内 `.app` 二进制；若实际驱动构建与候选 zip 非同一二进制，报告按「实际驱动构建 ≠ 候选包二进制」口径记录，不宣称「候选包已验证」。

## 断言逐项

| 断言项 | 结果 | 证据 / 说明 |
|---|---|---|
| `audit-screenshot-audit-runview.png` | FAIL | 截图 audit-runview.png 缺失或为空 |
| `audit-screenshot-audit-run-tab.png` | FAIL | 截图 audit-run-tab.png 缺失或为空 |
| `audit-screenshot-audit-history.png` | FAIL | 截图 audit-history.png 缺失或为空 |
| `audit-screenshot-audit-settings.png` | FAIL | 截图 audit-settings.png 缺失或为空 |
| `audit-ax-audit-runview.ax.json` | FAIL | 可及树 audit-runview.ax.json 缺失或为空 |
| `audit-ax-audit-run-tab.ax.json` | FAIL | 可及树 audit-run-tab.ax.json 缺失或为空 |
| `audit-ax-audit-history.ax.json` | FAIL | 可及树 audit-history.ax.json 缺失或为空 |
| `audit-ax-audit-settings.ax.json` | FAIL | 可及树 audit-settings.ax.json 缺失或为空 |
| `audit-ax-audit-detail.ax.json` | FAIL | 可及树 audit-detail.ax.json 缺失或为空 |
| `audit-runview-five-metrics` | FAIL | 五读数位: run.distance=MISSING, run.elapsed=MISSING, run.currentPace=MISSING, run.averagePace=MISSING, run.splits=MISSING；缺失: run.distance, run.elapsed, run.currentPace, run.averagePace, run.splits |
| `audit-three-tabs` | FAIL | Run/History/Settings 逐项: run=FAIL, history=FAIL, settings=FAIL |
| `audit-detail-gpx-entry` | FAIL | runDetail.export exists=None hittable=None 归档可用=None |
| `audit-build-identity` | PASS | 实际驱动构建 bundle com.chaxiu.purepace / 配置 Release / commit a45922265e38；与候选 zip 的同一性未解包比对，按口径显式标注 |

## 失败项

- 无

## 证据文件

- `analysis.json`（3804 字节）
- `attachments-manifest.json`（1247 字节）
- `audit-detail.ax_0_CB141DFC-5EA2-4B56-BCBE-8C356EAB4559.json`（9987 字节）
- `audit-detail_0_30E1022C-B75D-4504-8B43-25CB15BA37C0.png`（172967 字节）
- `audit-history.ax_0_C5B5E147-0CE8-4690-BF49-D2D415099985.json`（10166 字节）
- `audit-history_0_9F3869BD-0F1B-430B-BB9D-24E28FF05743.png`（172291 字节）
- `audit-result_0_8827182D-9EF5-440C-8CA0-5833C90A9048.json`（758 字节）
- `audit-run-tab.ax_0_7FE58C76-CF04-4499-85F3-1A9E2F69C96D.json`（3659 字节）
- `audit-run-tab_0_D0608D25-BFD7-484F-BADE-42148F4C12F5.png`（115323 字节）
- `audit-runview.ax_0_796DAF57-0148-4DDE-A4DA-16BEFDBCF926.json`（3660 字节）
- `audit-runview_0_6816B6D1-786D-4459-B896-DDB2B13C9DEB.png`（116556 字节）
- `audit-settings.ax_0_AA097E42-94C9-4A12-8C29-F88EBB82431F.json`（3957 字节）
- `audit-settings_0_EF1486D5-1A35-4333-A5FF-E464F30CC3C0.png`（107871 字节）

## pending: 待人现场（needs-you 单点）

- 锁屏态本版不验；如公司要求补，只由人在最终候选包上做一次「电源键 + 解锁」（≤ 30 秒），由公司另排，产品侧不得自行加进脚本或窗口。
- 人耳判定（≤ 2 条）随机器证据一次性交回公司负责人：播报是否听清；音乐 duck 后听感是否恢复。
- 本阶段存在机器失败项，需公司确认后另行安排。
