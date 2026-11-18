# 距离恒 0 根因结论（WiFi / 蜂窝 / 飞行模式三态）+ 三态读屏协议 + W1 断言变异红证

本文件只做三件事：给「跑步距离恒 0」的根因链条（每条对上仓内真实文件与符号名）、给一套真机三态
自采集读屏协议（只写点哪里 / 看哪几行 / 什么算异常，不含任何命令行）、给 W1 新增 5 条断言的
「构造错误输入 → 实际测得红」索引。**本项不带生产代码，不改阈值，不改断言。**

- 结论依据：已合入 main 的 W1 代码（`c381352`，`wi_intake_9681718e12c7b31c`）。
- 证据目录：`docs/evidence/wi_intake_500f9d48a49c1315/`（`README.md` + `logs/*.log`）。
- 行号以本 worktree 现状为准，可用 `grep -n` 复核；全部数字标口径。
- 本文件不声明「真机已验证」；真机三态读数一律 `pending: 待人现场`。

---

## 1. 先给结论（一句话版）

**三态网络形态不参与任何判定**：`ios/PurePace` 全目录检索 `NWPathMonitor` / `Network` / `Reachability`
零命中，定位链路没有任何网络可达性分支。网络形态只改变「首条 fix 的时间与精度」，
而「距离恒 0」是否成立由 **4 条代码分支** 决定，与网络形态一一对应的是**读数签名**，不是代码路径。

| # | 代码分支（真实符号） | 触发条件 | 读数签名（诊断区） | 距离是否恒 0 |
|---|---|---|---|---|
| A | `RunLocationSource.start()` 前置检查 / 授权分支 | 系统定位服务关闭，或授权 `denied` / `restricted` / 未取得授权 | `原始回调 = 0`、`授权 ≠ 仅前台/始终允许` | 是（永远无样本） |
| B | `RunLocationSource.deliver(_:)` 精度过滤 | 回调到达但 `horizontalAccuracy > accuracyThresholdMeters = 50` | `原始回调 > 0`、`精度过滤丢弃 = 原始回调`、`采样点数 = 0` | 是（窗口到点前 / 超过降级上限时） |
| C | `RunLocationSource.flushPendingFallbackIfDue()` 降级窗口 | 最佳 pending fix `> accuracyFallbackCeilingMeters = 200`，或窗口到点后无后续回调再触发 | `原始回调 > 0`、`精度过滤丢弃 = 原始回调`、`采样点数 = 0` 持续 > 15s | 是（永不结算） |
| D | `RunMetricsEngine.ingest(_:)` 距离累积 | 样本被接受但位置未变化（首条只建锚点；静止时坐标相同） | `采样点数 > 0`、`最近样本时间` 在走、`距离` 仍为 0 | 是（非缺陷，需看坐标是否变化） |

> 「系统不回调 / 回调被精度过滤丢弃 / 被降级窗口吞掉」三者的判别只用诊断区两列计数即可完成，
> 不需要任何设备命令：`原始回调 = 0` 是 A；`原始回调 > 0 且 丢弃 = 原始回调` 是 B 或 C；
> `采样点数 > 0 且距离 = 0` 是 D。

---

## 2. 根因链条（逐段对代码）

### 2.1 入口与授权：没有授权/服务关闭时根本不会开始采样

`ios/PurePace/Location/RunLocationSource.swift`

- `start()` `:263-285`：先读 `manager.locationServicesEnabled` 写入 `locationServicesEnabled`（`:265-266`）；
  `guard servicesEnabled else { endUpdating(); return }`（`:267-270`）——**服务关闭时不调
  `manager.startUpdatingLocation()`**（`endUpdating()` `:330-339`），因此 `rawCallbackCount` 永远 0。
- `apply(_:)` `:305-317`：`resolved.isAuthorized` 才 `beginUpdating()`（`:309-313`）；
  `denied`/`restricted` 走 `endUpdating()`，同样零回调。
- 授权请求：`notDetermined → requestWhenInUseAuthorization()`（`:276-277`，`:288-292` 实例内恰一次）；
  `authorizedWhenInUse → requestAlwaysAuthorization()`（`:278-279`，`:295-299`）。
- 回调入口 `locationManagerDidUpdate(payloads:)` `:440-442` → `deliver(_:)`。

**对应三态**：三条分支都不看网络。飞行模式下若室内无 WiFi/蜂窝辅助、GPS 冷启动拿不到定位，
表现正是 A（`原始回调 = 0`）；这属于「系统没给 fix」，不是「网络断了所以距离为 0」。

### 2.2 精度过滤：50m 以内才直采，其余只进 pending

`RunLocationSource.deliver(_:)` `:341-371`

- `rawCallbackCount += payloads.count`（`:343`）：**每条原始回调都计数**，不受后续过滤影响。
- `horizontalAccuracy < 0`（系统无效精度）整条丢弃并 `filteredCallbackCount += 1`（`:345-348`）。
- `horizontalAccuracy <= accuracyThresholdMeters`（50m，`:191`）→ 清 pending、取消定时器、`accept(payload)`
  （`:349-353`）。
- 否则 `filteredCallbackCount += 1`（`:355`）并留下窗口内「最佳可得」fix（`:361-367`），
  然后 `scheduleFallbackFlushIfNeeded()` + `flushPendingFallbackIfDue()`（`:368-369`）。

**对应三态**：WiFi 定位（关蜂窝）与蜂窝基站定位的典型精度本来就落在 50m 之外，
所以「WiFi 有网 / WiFi 关+蜂窝」两态最容易命中 B：回调在来，但全被算成丢弃，采样点数 0，距离 0。
这与网络是否「有网」无关，只与 fix 的 `horizontalAccuracy` 有关。

### 2.3 降级窗口：15s 到点结算，但 200m 以上永不接受

- 窗口原点不是「第一条低精度回调」，而是 `beginUpdating()` 里的 `updatingStartedAt = uptime()`（`:322`）。
- `accuracyFallbackWindowSeconds = 15`（`:197`）、`accuracyFallbackCeilingMeters = 200`（`:199`）。
- `flushPendingFallbackIfDue()` `:374-390`：`elapsed = uptime() - startedAt`（`:380`），
  未到点则重新挂定时器（`:381-384`）；到点后 `guard pending.horizontalAccuracy <= 200 else { return }`（`:385-386`），
  通过才 `accept(pending)`（`:388-389`）。
- `scheduleFallbackFlushIfNeeded()` `:393-404`：一次性 `Timer` 到点回调 `flushPendingFallbackIfDue()`。

**「被降级窗口吞掉」的确切含义（本项实测，见复现 2）**：`accuracy > 200m` 的待结算 fix 在窗口到点被
`:385-386` 的 `return` 拒绝，且该 `return` **既不清空 pending、也不重挂定时器**；若此后不再有回调，
这条 fix 永远不会结算 → `采样点数 = 0` 持续，距离恒 0。窗口内 65m 一类（≤200m）则会在 15s 到点被
`accept`，距离开始有值。

### 2.4 距离累积：`RunMetricsEngine` 只按坐标差累加

`ios/RunCore/Sources/PurePaceRunCore/RunMetricsEngine.swift`

- `ingest(_:)` `:154-210`：非运行态直接返回（`:155-157`）；**时间倒退/等时样本整条丢弃**
  （`:159-163`，`duplicateSampleCount += 1`）。
- 首个样本只建立位置锚点，距离与时长保持 0（`:165-175`）——**一条 fix 不足以产生距离**。
- 暂停/恢复后的首个样本只重建锚点，不跨空档累计位移（`:180-187`）。
- 之后才 `accumulatedMeters += GeoDistance.meters(...)`（`:189-196`）；`liveMetrics` 投影
  `distance: distanceValue`（`:106`，`distanceValue` 见 `:253-255`）。

**对应三态**：静止时（同一 WiFi AP / 同一基站覆盖下）接连 fix 的坐标可几乎相同，即使采样点数为 1 以上，
距离依旧为 0 —— 这是 D，属于正确行为，判据是「最近样本时间在走、坐标不变」，不是「没有回调」。

### 2.5 对用户的可见投影：30s 搜索态与四类原因

`ios/PurePace/Run/RunLocationReadiness.swift`

- `RunLocationSearchState` `:92-136`：`.idle` / `.searching` / `.timedOut(reason)`；
  `timeoutSeconds = 30`（`:105`）。
- `resolve(...)` `:113-135` 判定顺序：不在记录态或已有数据 → `.idle`（`:123`）；未到 30s → `.searching`（`:124`）；
  `!authorization.isAuthorized → .unauthorized`（`:125-127`）；`!servicesEnabled → .servicesDisabled`（`:128-130`）；
  `raw > 0 && filtered >= raw → .accuracyFiltered`（`:131-133`）；否则 `.noCallbacks`（`:134`）。
- `RunSessionViewModel.locationSearchState`（`ios/PurePace/Run/RunSessionViewModel.swift:477-494`）只聚合
  既有来源：会话状态、`orchestrator.hasLocationData`、定位源 `rawCallbackCount` / `filteredCallbackCount`、
  授权、`locationSource.locationServicesEnabled` —— 不新增第二套计数或计时真源。
- 文案与出口：`RunView` 搜索中 `run.waitingLocation`（`:493-507`）、超时原因 `run.locationSearchTimeout`
  （`:508-513`）、重试 `run.retryLocation`（`:603-613`）；`retryLocation()` 只 `locationSource.restart()`
  （`RunSessionViewModel.swift:440-443`），不重置计时/距离。

**已知局限（如实记账，本项不修）**：`RunLocationReadiness.resolve(authorization:servicesEnabled:lastErrorCode:)`
（`RunLocationReadiness.swift:78-85`）把「服务关闭 / 最近失败」压成 `.unavailable` 再判授权，
因此 `denied + 服务关闭` 在 readiness 层丢 `permissionDenied`；`RunLocationSearchState.resolve` 则先判授权
再判服务（`:125-130`），两层顺序不一致，读屏时须以诊断区原始列为准。

---

## 3. 三态读数签名（网络形态 → 预期读数）

| 网络形态 | 定位辅助来源 | ≥30s 后的典型读数签名 | 命中的分支 | 机器侧可否复现 |
|---|---|---|---|---|
| WiFi 有网 | GPS + WiFi 定位 | `原始回调 > 0`；室内多为 `丢弃 = 原始回调`；`采样点数` 0 或极少 | B → C | 可（注入 65m / 250m fix） |
| WiFi 关 + 蜂窝 | GPS + 蜂窝基站 | 同上，首 fix 更慢、精度更差，`丢弃` 更接近 `原始回调` | B → C | 可（同上，输入相同） |
| 飞行模式 | GPS 单机 | 室内/电梯：`原始回调 = 0`、`最近错误` 多为 `kCLErrorDomain / 0`；室外冷启动可能 >30s 才首 fix | A | 可（零回调路径） |

**判定不变量**：三态的差异只在「首 fix 延迟 + 精度分布」，`距离恒 0` 的判定点永远是 §1 表的 A/B/C/D。
因此「三态都恒 0」不能由「网络断了」解释，只能由读数签名定位到具体分支。

---

## 4. 真机三态读数自采集读屏协议（不含任何命令行）

目标：在真机上按固定步骤采到「三态 × ≥30s」的 6 个读数，用来把上述 A/B/C/D 收敛到唯一分支。
只操作 App 界面；不接 Xcode 控制台，不输入任何命令。

### 4.1 准备（每组只做一次）

1. 打开 App，进「设置」，找到「诊断」分区；确认能看到下列 9 行：`授权`、`精度授权`、`定位服务`、
   `采样点数`、`最近样本时间`、`后台定位`、`原始回调`、`精度过滤丢弃`、`最近错误`
   （诊断文本另有版本 / 构建两行，不参与读数）。
2. 每一组开始前，先在这页抄下**基线读数**（尤其是 `原始回调`、`精度过滤丢弃`、`采样点数` 三个累计值）。
3. 打开系统设置，把定位权限设为「使用 App 期间」（精度先保持系统默认，不要先改成「精确」）。

### 4.2 每组的固定动作（三组各重复一遍）

1. 切到「跑步」页，点「开始」，立刻看屏幕：若出现「正在搜索定位」提示，记为 `搜索中`；若 30s 后
   变成原因文案，照抄文案并记下 `run.retryLocation`（「重试定位」）按钮是否出现。
2. 站在**同一位置不要走动**，让计时连续走 **≥30s**（看页面上的计时数字，30s 后再多等 5s）。
3. 切回「设置 → 诊断」，抄下 6 个读数：`授权`、`精度授权`、`定位服务`、`后台定位`、
   `原始回调`、`精度过滤丢弃`、`采样点数`（与 4.1 的基线相减得本组增量）。
4. 回到「跑步」页，看距离位：若是「未获取到定位」照抄；若显示 `0.00`，照抄并记「有采样点/无采样点」。
5. 点「结束」，再回「设置 → 诊断」抄一次 `采样点数` 与 `最近样本时间`（确认结束后不再增长）。
6. 三组之间必须**完全杀进程重开 App**，否则 `原始回调` 是跨会话累计值。

### 4.3 三态切换（只改网络，不改 App 内设置）

| 组 | 网络操作（在系统设置里做） | 备注 |
|---|---|---|
| W1 | 开 WiFi 并连上可用网络 | 关掉蜂窝也可以，保持与平时一致 |
| W2 | 关 WiFi、开蜂窝数据 | 系统设置 → 无线局域网关闭 → 蜂窝数据打开 |
| W3 | 开飞行模式 | 系统设置 → 飞行模式打开；确认 WiFi/蜂窝都变成关闭 |

### 4.4 什么算异常（逐条判据）

| 现象 | 判据 | 归属 |
|---|---|---|
| 30s 后仍无任何原因文案、也没有「正在搜索定位」 | 状态机没跑到 `timedOut`，属异常 | 记录为「状态未归类」 |
| `授权 = 未决定` 且点「开始」后没有出现系统定位弹窗 | 授权请求链路异常（`start()` `:276-277`） | A 类异常 |
| `授权 = 已拒绝/受限` 但页面仍显示持续计时 | 状态机层未拦住记录态，属异常 | A 类异常 |
| `精度授权 = 仅大致位置` | 属已知精度降级条件，不是缺陷；距离 0 归 B | B 预期 |
| `原始回调 = 0` 连续 ≥30s（含增量） | 系统确实没回调（飞行模式室内最常见） | A |
| `原始回调 > 0` 且 `精度过滤丢弃 = 原始回调`，`采样点数 = 0`，且已过 15s | 全部被精度过滤；若再持续 ≥15s 仍 0 且无新回调，落 C | B/C |
| `采样点数 > 0` 且距离仍是 `0.00`，`最近样本时间` 在走 | 坐标未变化/首条只建锚点 | D（非缺陷） |
| 跑步进行中 `后台定位 = 否` | 后台标志异常（`beginUpdating()` `:326`） | 异常 |
| 结束后 `采样点数` 仍在增长 | 停机链路异常（`endUpdating()` `:330-339`） | 异常 |

### 4.5 记录表（真机执行后逐格填写；本项一律 `pending: 待人现场`）

| 组 | 网络形态 | ≥30s 后 `原始回调` 增量 | `精度过滤丢弃` 增量 | `采样点数` | `授权` | `精度授权` | `后台定位` | 距离位 | 搜索态文案 | 结论分支 |
|---|---|---|---|---|---|---|---|---|---|---|
| W1 | WiFi 有网 | pending | pending | pending | pending | pending | pending | pending | pending | pending |
| W2 | WiFi 关 + 蜂窝 | pending | pending | pending | pending | pending | pending | pending | pending | pending |
| W3 | 飞行模式 | pending | pending | pending | pending | pending | pending | pending | pending | pending |

---

## 5. W1 新增断言的变异红证（真实执行，仓内零改动）

未变异基线：5 条用例同批执行 → `Executed 5 tests, with 0 failures` / `** TEST SUCCEEDED **` / 退出码 0
（`docs/evidence/wi_intake_500f9d48a49c1315/logs/green.log`）。

变异全部只在 `/tmp/pp-w1-500f9d48a49c1315/repo`（仓库只读副本）内做，每次只改一处，跑完即从备份还原；
仓库 `ios/**` 零 diff。

| # | 断言（`ios/PurePaceTests/RunPermissionAndDiagnosticsTests.swift`） | 构造的错误输入（变异） | 失败位置 | 退出码 | 日志 |
|---|---|---|---|---|---|
| 1 | `testSingleImpreciseFixAcceptedAtWindowWithoutAnotherCallback` `:399` | 删掉 `flushPendingFallbackIfDue()` 到点结算里的 `accept(pending)`（恢复旧静默丢弃） | `:426`（0 ≠ 1）、`:427`（nil ≠ 65.0） | 65 | `docs/evidence/wi_intake_500f9d48a49c1315/logs/mutation-1-fallback-silent-drop.log` |
| 2 | `testLocationSearchStateTimesOutWithAttributableReason` `:431` | `RunLocationSearchState.resolve()` 的 `.accuracyFiltered` 分支改返回 `.noCallbacks` | `:462`（`.noCallbacks` ≠ `.accuracyFiltered`） | 65 | `docs/evidence/wi_intake_500f9d48a49c1315/logs/mutation-2-search-reason-collapse.log` |
| 3 | `testTimeoutRetryRestartsLocationWithoutResettingSession` `:483` | `RunSessionViewModel.retryLocation()` 删掉 `locationSource.restart()`（重试变空操作） | `:519`（1 ≠ 2，重试必须重启定位源） | 65 | `docs/evidence/wi_intake_500f9d48a49c1315/logs/mutation-3-retry-noop.log` |
| 4 | `testDiagnosticsSnapshotIsSelfConsistentAndSingleSourced` `:525` | `diagnosticsSnapshot()` 把 `lastError` 写死为 `nil`（不再转发最近定位错误） | `:546`、`:547`、`:548`（3 处） | 65 | `docs/evidence/wi_intake_500f9d48a49c1315/logs/mutation-4-diagnostics-lasterror-dropped.log` |
| 5 | `testLastSampleTimeNeverRegresses` `:568` | `RunSessionOrchestrator.isArchiveAcceptable(_:)` 的 `return sample.timestamp > last` 改成 `return true` | `:585`（22:13:23 ≠ 22:13:25，最近样本时间回退） | 65 | `docs/evidence/wi_intake_500f9d48a49c1315/logs/mutation-5-no-monotonic-guard.log` |

每条日志头部写明「被测用例 / 变异内容 / 执行位置 / 命令 / 裁剪说明」，正文保留失败断言原文与
`Executed N tests, with M failures` / `** TEST FAILED **` / `EXIT:65`。裁剪只删 xcodebuild 的编译与
环境噪声行，断言原文逐字未改。

---

## 6. 机器侧复现（距离恒 0 本身，不接真机）

| # | 输入 | 实测读数 | 结论 | 日志 |
|---|---|---|---|---|
| 1 | 注入时钟推进 5.0s，零条定位采样（`RunMetricsEngine.ingest` 从未调用） | `elapsed = 5.0`、`distance = 0.0` | 计时在走而距离恒 0，可由「零回调」单独造成 | `docs/evidence/wi_intake_500f9d48a49c1315/logs/repro-1-zero-callbacks.log` |
| 2 | acc=65m 单条 fix，t=0 注入、t=15s 到点 | t=0：`raw=1 filtered=1 samples=0`；t=15s：`samples=1 lastAccepted=65.0` | 窗口内距离恒 0，到点降级接受（分支 B 的正常出口） | `docs/evidence/wi_intake_500f9d48a49c1315/logs/repro-2-zero-distance-branches.log` |
| 3 | acc=250m 单条 fix，t=15s 到点 | `raw=1 filtered=1 samples=0 lastAccepted=nil` | 超 200m 上限永不结算，距离恒 0（分支 C） | 同上 |
| 4 | `RunLocationSearchState.resolve` 纯函数三组输入 | `denied → .unauthorized`、`services=off → .servicesDisabled`、`raw=3 filtered=3 → .accuracyFiltered` | 30s 到点后可归因，不空白 | 同上 |

真机三态读数不在本表：`pending: 待人现场`，按 §4 协议采集后回填 §4.5。

---

## 7. 未闭合点（本项不扩范围）

1. `flushPendingFallbackIfDue()` 在 `> 200m` 时 `return` 后既不重挂定时器也不清 pending；
   若不再有回调，该 fix 永远停在 pending（分支 C 的永久 0）。是否需要重挂/清空属行为决策，本项只记录。
2. `RunLocationReadiness.resolve` 与 `RunLocationSearchState.resolve` 的授权/服务判定顺序不一致
   （前者服务优先、后者授权优先），`denied + 服务关闭` 的两处归因不同。
3. 三态真机读数全部待现场采集；本项不含任何真机结论。
