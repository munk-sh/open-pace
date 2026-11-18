# 定位三态可归因：距离恒 0 根因 + 搜索中/超时重试 + 精度降级不静默

## 范围

- 先取证定性、再改码：解释真机「WiFi 有网 / WiFi 关+蜂窝 / 飞行模式」三态下 distance 恒 0 的根因，逐条给文件 + 函数 + 触发条件，并明确说明既有单测 / 模拟器 UI 为何没拦住。必须逐个排除或确认四类假设：①精度过滤把 fix 全丢；②定位会话未启动 / 未收到回调；③授权或后台标志导致不采；④距离累计口径（过滤前后 / 采样入库时机）导致恒 0。禁止以「系统限制 / 环境差异」收尾。
- 诊断区（设置页）单一 snapshot 补全并校验字段：raw 回调数、被精度过滤丢弃数、最近样本时间、最近错误（domain / code / 描述）、`CLAuthorizationStatus`、`accuracyAuthorization`、`allowsBackgroundLocationUpdates`、`locationServicesEnabled`、版本 + 构建 sha 前 8 位；支持一键复制导出纯文本。只扩既有 snapshot，不新建第二套计时或定位真源。
- 记录态搜索语义：进入记录态后 30 秒内无任何可用 fix（含零回调、全部被过滤）时显示「正在搜索定位」，30 秒到点给出可读原因（未授权 / 系统定位服务关闭 / 精度长期不足 / 无回调）与「重试定位」按钮；重试只重启定位会话，不重置计时、不清空已累计距离与样本。禁止「计时在走、距离空白且无任何提示」。
- 精度降级：>50m 的 fix 不得被静默丢弃，走既有 15s 降级窗口（窗口内无 ≤50m fix 则接受当前最佳 fix 并累计距离），UI 标「精度降级」非阻断内联提示；删除静默丢弃路径。
- 三态读数协议：回执给出「人不用敲命令」的读屏步骤（删净旧包 → 装新包 → 三态各开跑 ≥30 秒 → 看诊断区 → 一键复制发回），三态真机读数本身记 `pending: 待人现场`，不得代填或推测。
- 机器侧覆盖：单测 + 模拟器 UI 断言至少覆盖 ①零回调 ②全部 fix 被精度过滤 ③locationServicesEnabled=false 与 denied ④30s 超时出现原因与重试 ⑤重试后计时不清零 ⑥>50m fix 进降级窗口并标「精度降级」。

## 验收

- ac-loc-rootcause：回执含三态根因结论，逐条文件 + 函数 + 触发条件，并说明旧单测 / 模拟器 UI 为何未拦住；结论不含「系统限制」。
- ac-loc-diagnostics：诊断导出文本含 raw 回调数、精度丢弃数、最近样本时间、最近错误、两项授权状态、后台标志、locationServicesEnabled、版本、sha8；数据来自单一 snapshot 且有断言。
- ac-loc-searching：记录态零可用 fix 时先显示「正在搜索定位」，计时与距离区不空白、不静默。
- ac-loc-timeout：30 秒到点显示原因文案 + 「重试定位」按钮；点重试后定位会话重启，计时值与已累计距离不变（断言）。
- ac-loc-degrade：构造只返回 >50m fix 的输入，距离仍累计且显示「精度降级」；该断言附造错必红反例（改回静默丢弃 → 必红）。
- ac-loc-redcounter：上述每条新断言同 commit 附「构造错误输入 → 必红」证据，不靠改生产代码才红，反例原文贴进回执。
- ac-loc-nostale：诊断数据与 UI 同源于唯一 snapshot，仓内无第二套 raw 回调计数真源。

## 非目标

- 不改计时推进逻辑、不改跑步首页既有结构、不做设置 / 历史 / 详情视觉版式改造（另一写项 W3 负责）。
- 不加新功能、不加新权限类型、不改 bundle id / 版本号、不发版、不推 tag。
- 不引入第三方定位 SDK、不改 GPX 格式、不动 Android 侧。

## 实现约束

- 维持 SwiftUI + CoreLocation 现状栈；`DesignTokens.swift` 是唯一令牌来源，视图层零字面色值、零裸 magic number。
- 界面 zh-Hans 单语，用户可见文案走 String Catalog 单一来源；identifier 既有集合只增不改，a11y label 用中文且与可见文字语义一致。
- 计时与定位解耦不变：单调时钟推进，定位缺失不得停表；采样与过滤沿用既有 15s 降级窗口语义，不另建第二套窗口。
- 权限链路既有约定不变：`.notDetermined` 点开始真实弹系统弹窗，取得 WhenInUse 后跑动中请求 Always，未拿 Always 时 UI 写「仅前台记录」。
- 同一 commit 的 `ios.yml` 全绿（本地腿只算旁证）；若改动受管视图或 identifier，必须显式跑 `scripts/check-ios-shell.sh --self-test` 全绿。

## 本单执行约束（不 fold）

- 预算 ≤8M token / ≤90 分钟墙钟；到点停手，交未闭合回执（已做 / 未做 / 已过门 / 未闭合点），不续命、不重跑已绿门、不弱化断言。
- commit 按面拆分：code / fold / prd 不得混在同一 commit。
- 不删不弱化 `ios.yml` / `android.yml` 既有腿，不 `continue-on-error`，不改阈值、不加超时。
- 不自建 / 删除远端仓库、不改 remote、本项不 push / merge / PR（由 Host delivery 走）。
- 不出包、不直装、不上传分发、不碰 VERSION 与 release notes。
- 证据落仓内 artifacts 并绑 commit；未在真机验的项写 `pending: 待人现场`，禁写「真机已验证」。
