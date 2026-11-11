# 竞品交互与视觉拆解（Strava / Nike Run Club / Apple Fitness / Keep）

本文件只作为 WorkSet 第 1 波的输入依据：不产生 App 代码、令牌、UI 与门禁改动，所有产出限于 `docs/design/**`。

## 预算与收口

- 开工时刻：`2026-11-11T02:43:28Z`（UTC）
- 预算时长：90 分钟（`2026-11-11T02:43:28Z` → `2026-11-11T04:13:28Z`；采集 ≤60 min / 写作 ≤25 min / 校验 ≤5 min）
- 期望收口绝对时刻：`2026-11-11T04:13:28Z`（UTC）
- 实际收口：`2026-11-11T03:12Z` 前后，未触发超时停手；无「超时停手」回执需要落。

## 来源与取证口径

- 真实界面只认三类来源：App Store 产品页截图（`apps.apple.com`）、厂商官网、官方预览视频/录屏。
- 每张参考图都落盘在 `docs/design/refs/**`，逐文件 sha256 见 `docs/design/refs/manifest.sha256`，逐文件来源页 URL / 抓取时刻 / 抓取命令见 `docs/design/refs/README.md`。
- 这次 Keep 的官网与 App Store 页都可达（HTTP 200），因此**没有启用咕咚替代**，目录 slug 为 `keep`。
- 缺素材一律写 `观察：来源缺失` 并附已尝试来源与失败原因，不用「通常」「应该是」补写界面细节。
- 本条最容易踩坑的一点：四家的**公开素材里都没有**结束保存页、空态、权限拒绝态；`running` 屏只有 Strava 有（在其官方预览视频里）。因此 20 个屏块中只有 8 块有真实界面观察，其余 12 块是显式的来源缺失记录，不为了凑数编造。

## 来源失败记录

| 失败 URL | 失败原因 | 后续换用 |
|---|---|---|
| https://apps.apple.com/cn/app/id6881013554 | HTTP 404（Keep 的 App ID 猜错） | https://apps.apple.com/cn/app/keep-ai-%E8%BF%90%E5%8A%A8%E6%95%99%E7%BB%83/id952694580 （200） |
| https://apps.apple.com/cn/app/id426826309 | HTTP 404（Strava 未在 CN storefront 上架） | https://apps.apple.com/us/app/strava-running-and-cycling/id426826309 （301→200，落到 `strava-run-bike-walk`） |
| https://apps.apple.com/cn/app/id387771637 | HTTP 404（Nike Run Club 未在 CN storefront 上架） | https://apps.apple.com/us/app/nike-run-club-running-coach/id387771637 （200） |
| https://www.apple.com/apple-fitness/ | HTTP 404（该路径不存在） | https://apps.apple.com/us/app/fitness/id1208224953 （200） |
| https://www.apple.com/fitness/ | HTTP 404（该路径不存在） | 同上 |
| https://www.strava.com/apps | 302 跳转到 https://www.strava.com/login ，内容在登录墙后，不可作为公开来源 | 改用 Strava 的 App Store 官方预览视频（`apptrailers.itunes.apple.com`） |
| https://www.gotokeep.com/ | 200，但页面里的 App 截图托管在非白名单 CDN，不能作为图片证据 | 仅作为官网文本来源；截图统一取 App Store 产品页 |
| https://apps.apple.com/us/app/nike-run-club-running-coach/id387771637 （预览视频字段） | 该页 HTML 中无 `videoUrl` 字段，Nike Run Club 没有官方预览视频 | 动效结论按 `观察：来源缺失` 处理 |

## Strava

来源页：https://apps.apple.com/us/app/strava-running-and-cycling/id426826309 ；官方预览视频：https://apptrailers.itunes.apple.com/itunes-assets/PurpleVideo221/v4/a6/f2/50/a6f250e3-79cf-dcd3-af53-82f6b1b93b35/P1126263724_default.m3u8

### Strava · launch（首屏与开始跑步前置路径）

观察：冷启动首屏是社区 Home feed：顶栏左侧 `⊕` 与搜索、中间标题 `Home`、右侧通知与私信；底部 5 个 Tab `Home / Maps / Record / Groups / You`；首条内容是一条他人跑次卡（头像 + `Today at 9:31 AM · London, United Kingdom` + 标题 + `Distance / Time / Elevation / Achievements` 四列小字 + 地图 + 点赞/评论/分享）。开始跑步要切到底部正中的 `Record`，该 Tab 落地即叠出 `Choose a Sport` 面板（顶部 `Your Top Sports` 圆形运动图标行，下面分组 `Foot Sports: Run / Trail Run / Walk / Hike`），选中运动后回到地图 + 底部一行运动图标 + 单枚橙色圆形 `START`。从冷启动到真正进入记录态是 **3 步**（Record → 选运动 → START），超出 ≤2 步基准。来源：https://apps.apple.com/us/app/strava-running-and-cycling/id426826309 （refs `strava/launch-dark.jpg`、`strava/pre-run-dark.jpg`）；浅色下的同一条路径见官方预览视频 https://apptrailers.itunes.apple.com/itunes-assets/PurpleVideo221/v4/41/ed/c4/41edc4fa-6050-7e53-ca2f-9ef4a3295dd3/P1126263724_Anull_video_gr265_sdr_886x1920.m3u8 （refs `strava/pre-run-light.png`）。

为什么有效：首屏先给「别人的跑次」，产品价值（记录 + 分享 + 被点赞）在没有自己数据时也能立刻成立；`Record` 放在底栏正中，是五格里视觉与肌肉记忆都最强的一格，说明「记录」是它的核心动作而不是附属功能。

决策：拒绝 —— 首屏社交 feed 与 3 步起跑都不采用：本产品没有社交面，「冷启动即落在可用的 Run 首屏」是既有契约，且要求 ≤2 步。可迁移的只有「记录入口常驻底部」这一条，落点在映射表。

### Strava · running（跑步中）

观察：记录中屏整屏白底、没有地图也没有卡片，三组指标垂直堆叠：每组是「上置小号大写灰标签（`TIME` / `SPEED` / `DISTANCE`）+ 特大窄体黑数字 + 数值下方极小灰单位（`MPH` / `MILES`）」，组与组之间一条淡灰 hairline；本帧里 `SPEED` 的数值明显大于 `TIME` 与 `DISTANCE`（同一屏内主次由字号差建立）；屏底居中一枚橙色实心圆，圆内白色暂停双竖条，圆外一圈极淡的同色光晕；本帧内未见结束/停止入口。同一段预览视频里数字是原地逐秒刷新的（`00:00:00` → `00:00:33` → `00:02:35`），页面结构不重排。来源：https://apptrailers.itunes.apple.com/itunes-assets/PurpleVideo221/v4/41/ed/c4/41edc4fa-6050-7e53-ca2f-9ef4a3295dd3/P1126263724_Anull_video_gr265_sdr_886x1920.m3u8 （refs `strava/running-light.png`）。

为什么有效：跑步中抬眼看屏只有不到一秒，任何边框、卡片、地图都在抢注意力；只留「标签-数值-单位」三行加一条分隔线，靠字号极端对比建立层级，弱信息（标签、单位）用灰字退到背景里。把「当前配速」放到最大，符合跑者此刻最关心的「我快还是慢」，而累计距离/用时本来就是缓慢变化的量。

决策：采用 —— 采用其排版骨架：上置标签 / 超大数值 / 下置单位 + hairline 分组 + 底部单枚大圆暂停（≥44pt、底部安全区内）。不采用两点：一是主指标不换成配速（本产品以距离为 hero，见既有契约），二是拒绝「记录中屏看不到结束入口」——本产品的结束入口必须常驻可见。

### Strava · summary（结束与总结）

观察：来源缺失。已尝试：App Store 产品页 5 张截图（https://apps.apple.com/us/app/strava-running-and-cycling/id426826309 ）与官方预览视频逐秒抽样 30 帧（https://apptrailers.itunes.apple.com/itunes-assets/PurpleVideo221/v4/41/ed/c4/41edc4fa-6050-7e53-ca2f-9ef4a3295dd3/P1126263724_Anull_video_gr265_sdr_886x1920.m3u8 ）内都没有结束确认、保存/丢弃、跑后总结任一面。

为什么有效：没有可复现素材，不做有效性判断，也不按印象补写流程。

决策：拒绝 —— 无证据不抄；结束与保存路径按本产品既有契约自行定义（结束确认可取消、保存/丢弃显式二选一）。

### Strava · history（历史列表与详情）

观察：详情页结构是：顶部 `‹` 返回 + 右侧 `…`，一行小灰字时间，下面一行大号标题 + 铅笔图标，一条 hairline 之后是人体正反面热力图，再往下是上传者行、活动名 `Night Weight Training`，最后四宫格指标（`Elapsed Time 45:30` / `Total Volume 4,115 lbs` / `Total Sets 47` / `Avg Heart Rate 98 bpm`，数值大字 + 上置小灰标签），底部仍是 5 Tab。官方素材里**没有**「我的活动」列表页本体，因此列表形态不做任何描述。来源：https://apps.apple.com/us/app/strava-running-and-cycling/id426826309 （refs `strava/history-detail-dark.jpg`）。

为什么有效：详情页把「什么时候、叫什么、能不能改」压在顶部极少两行，中间用一张可视化（这里是热力图）承载「这次练了哪儿」，最后才给指标四宫格；读者从「是什么」到「怎么样」的顺序自然，不需要图表也能读懂。

决策：采用 —— 采用「顶部元信息 + hairline + 可视化/hero + 指标网格」的纵向顺序，以及「数值大、标签上置小灰」的层级；拒绝其 5 Tab 底栏（见「不抄竞品菜单结构」）。

### Strava · empty-permission（空态与权限拒绝态）

观察：来源缺失。已尝试：App Store 产品页 5 张截图（https://apps.apple.com/us/app/strava-running-and-cycling/id426826309 ）与官方预览视频 30 帧（https://apptrailers.itunes.apple.com/itunes-assets/PurpleVideo221/v4/41/ed/c4/41edc4fa-6050-7e53-ca2f-9ef4a3295dd3/P1126263724_Anull_video_gr265_sdr_886x1920.m3u8 ）；官网 https://www.strava.com/features 只提供营销图，不含空态或权限拒绝界面。

为什么有效：无素材不判断；权限拒绝态的文案与下一步属于产品责任，不靠竞品猜。

决策：拒绝 —— 无证据不抄；空态与定位拒绝态按本产品契约实现（一句说明 + 一个可执行下一步，不留死路）。

## Nike Run Club

来源页：https://www.nike.com/nrc 、https://apps.apple.com/us/app/nike-run-club-running-coach/id387771637

### Nike Run Club · launch（首屏与开始跑步前置路径）

观察：`Run` 页顶部是三个页签 `Start a Run / Guided Runs / Training Plans`，默认停在 `Start a Run`；下方一张大插画卡（紫色底 + 三个跑者剪影 + `Get Started`）配 `4-Week Training Plan` 标题、一行说明、`Beginner` 标签与一张红色纹样卡。它的首页是 `Activity`：头像 + `+`、标题 `Activity`、`W / M / Y / All` 分段、`This Week` `20.6 Miles` + `3 Runs / 5'14" Avg. Pace / 1:48:04 Time`、按星期的柱状图、`Recent Activity` 卡，底部 5 Tab `Home / Plans / Run / Club / Activity`。从首页到可开始是 **≥2 步**（Run Tab → 起跑按钮），第二步所在的页面本身未被官方素材截取，故不描述它长什么样。来源：https://www.nike.com/nrc （refs `nike-run-club/launch-light.png`）、https://apps.apple.com/us/app/nike-run-club-running-coach/id387771637 （refs `nike-run-club/history-light.jpg`）。

为什么有效：把「现在就跑 / 跟着教练跑 / 按计划跑」拆成三个平级页签，用户不用在信息流里翻卡片找入口；`Start a Run` 排第一且默认选中，承认多数人是来「立刻跑」的。

决策：拒绝 —— 起跑要先离开首页进 `Run` Tab、再点一次；本产品首屏本身就是记录态入口，不复制它的跨 Tab 起跑。可迁移的是「一个页签只放一件事」的命名克制，不落 UI。

### Nike Run Club · running（跑步中）

观察：来源缺失。已尝试：App Store 产品页 6 张截图（https://apps.apple.com/us/app/nike-run-club-running-coach/id387771637 ）与官网 https://www.nike.com/nrc 的 9 张官方图，均无记录中屏；该产品也没有官方预览视频（页面无 `videoUrl` 字段）。

为什么有效：无素材不判断；记录中屏的指标布局不靠猜测。

决策：拒绝 —— 无证据不抄；跑步中屏按本产品契约与 Strava 的可复现观察实现。

### Nike Run Club · summary（结束与总结）

观察：来源缺失。已尝试：App Store 产品页 6 张截图（https://apps.apple.com/us/app/nike-run-club-running-coach/id387771637 ）与官网 https://www.nike.com/nrc 全部官方图，无结束确认/保存/总结页；无官方录屏。

为什么有效：无素材不判断。

决策：拒绝 —— 无证据不抄。

### Nike Run Club · history（历史列表与详情）

观察：列表侧是 `Activity` 页的 `Recent Activity` 行：左侧小缩略图 + 两行文字（`Today` 与 `Morning Fun Run`），下面一行三个数值 `3.12 Miles / 8'21" / 32:04`，数值大字在上、标签小灰字在下。详情页是：顶部 `‹` 与 `…`、一行小灰字 `Tomorrow - 9:35am` 形式的日期时间、标题 `Monday Morning Run` + 铅笔、hairline、hero 数字 `3.12` + 单位 `Miles`，然后两行三列指标（`8'21" Avg. Pace` / `23:29 Time` / `442 Calories`；`56 ft Elevation Gain` / `159 Avg. Heart Rate` / `167 Cadence`），最下方地图卡带城市标签。来源：https://apps.apple.com/us/app/nike-run-club-running-coach/id387771637 （refs `nike-run-club/history-light.jpg`）、https://www.nike.com/nrc （refs `nike-run-club/history-detail-light.jpg`）。

为什么有效：列表行只答三个问题（多远、多快、多久），标签在数值下方用灰字，扫视时先命中数字；详情页完全继承同一套「大数值 + 小标签」语法，从列表下钻到详情不会有层级跳变，也不需要重新学习阅读顺序。

决策：采用 —— HistoryView 行沿用「日期标题 + 距离/时长/配速三数值」，RunDetailView 沿用「hero 距离 → 2×3 指标 → 地图」的顺序与「数值在上、标签小灰字在下」的对齐方式。不采用卡片阴影与页签膨胀。

### Nike Run Club · empty-permission（空态与权限拒绝态）

观察：来源缺失。已尝试：App Store 产品页 6 张截图（https://apps.apple.com/us/app/nike-run-club-running-coach/id387771637 ）与官网 https://www.nike.com/nrc 全部官方图；无空态、无权限拒绝态素材。

为什么有效：无素材不判断。

决策：拒绝 —— 无证据不抄。

## Apple Fitness

来源页：https://apps.apple.com/us/app/fitness/id1208224953

### Apple Fitness · launch（首屏与开始跑步前置路径）

观察：`Workout` 页把运动类型做成纵向大卡：每卡左侧一枚绿色线性跑者/步行者人形图标 + 名称（`Outdoor Walk` / `Indoor Walk` / `Outdoor Run`），卡片右上角一枚绿色实心圆内白色播放三角 —— 这枚播放钮就是开始按钮，和运动类型在同一张卡上；卡片底部还排三个圆角小胶囊（指标、提示、历史）。底部 4 Tab 为 `Summary / Fitness+ / Workout / Sharing`，当前 `Workout` 用绿色高亮。从这一页进入记录态只需 **1 次点击**。冷启动落在哪个 Tab 未被素材覆盖，不描述。来源：https://apps.apple.com/us/app/fitness/id1208224953 （refs `apple-fitness/launch-dark.png`）。

为什么有效：用户根本不需要「先选中运动、再去找开始按钮」两段式：他扫到 `Outdoor Run` 那张卡，主操作就在同一张卡的拇指可达位置。运动类型越少，这种「卡片即按钮」的合并越省一步。

决策：采用 —— 采用「主操作贴在它作用的那一行上、不做二次确认页」的思路；本产品只有一个运动，等价落地是首屏唯一主操作即开始，不设运动类型选择页。不采用 4 Tab 与卡片仪表盘。

### Apple Fitness · running（跑步中）

观察：来源缺失。已尝试：App Store 产品页 5 张截图（https://apps.apple.com/us/app/fitness/id1208224953 ）与 CN storefront 同名图集（https://apps.apple.com/cn/app/id1208224953 ）；https://www.apple.com/apple-fitness-plus/ 只给一张 OG 图，无 App 内记录中界面；该页亦无官方预览视频。

为什么有效：无素材不判断。

决策：拒绝 —— 无证据不抄。

### Apple Fitness · summary（结束与总结）

观察：来源缺失。已尝试：App Store 产品页 5 张截图（https://apps.apple.com/us/app/fitness/id1208224953 ）；无结束确认/保存/跑后总结素材。

为什么有效：无素材不判断。

决策：拒绝 —— 无证据不抄。

### Apple Fitness · history（历史列表与详情）

观察：`Summary` 页是卡片网格：首卡 `Activity Rings`（`Move 665/750 CAL`、`Exercise 72/30 MIN`、`Stand 4/12 HRS` 三行 + 三色圆环），第二行并排 `Step Count 13,818` 与 `Step Distance 6.58 MI`（各带一条 12AM–9PM 微型柱图），第三行是 `Sessions` 卡（`Outdoor Run 6.21MI` + `Today`）与 `Awards` 卡（`New Move Record`）；每张卡标题行左对齐标题、右侧一枚 `ⓘ` 解释入口。逐次记录本身没有出现在素材里，`Sessions` 卡是它的入口。来源：https://apps.apple.com/us/app/fitness/id1208224953 （refs `apple-fitness/history-dark.png`）。

为什么有效：把「今天多少」这类聚合量做成方格化仪表盘，一眼扫完；每张卡的标题行右侧放解释入口，既保留科普又不抢数值位置；`Sessions` 卡把「今天跑过一次 6.21 英里」压成一行标题 + 一个大数字，是列表的轻量替代。

决策：拒绝 —— 本产品不做圆环、徽章与多卡仪表盘（三 Tab 已有 History 列表，仪表盘会与它争夺同一块认知）；采用「卡标题行左标题 + 右解释入口」和「一组聚合数字配一个下钻入口」两处写法，落到 HistoryView。

### Apple Fitness · empty-permission（空态与权限拒绝态）

观察：来源缺失。已尝试：App Store 产品页 5 张截图（https://apps.apple.com/us/app/fitness/id1208224953 ）；无空态或定位权限拒绝素材。

为什么有效：无素材不判断。

决策：拒绝 —— 无证据不抄。

## Keep

来源页：https://apps.apple.com/cn/app/keep-ai-%E8%BF%90%E5%8A%A8%E6%95%99%E7%BB%83/id952694580 、https://www.gotokeep.com/

### Keep · launch（首屏与开始跑步前置路径）

观察：首页 `课程` 顶部是三分段 `课程 / 计划 / 工具`，下面是图标四宫格（`全部课程 / 免费课 / 直播课 / 动作库`）+ `为你推荐` 横滑 + `精选合集` 三列卡 + `专属计划`，底部 5 Tab `首页 / 今日 / 运动 / 发现 / 我的`。真正起跑面在 `运动` Tab：顶部四个模式胶囊 `自由跑 / 目标跑 / 课程跑 / 自定义`，中间一行三个运动 `户外跑步 / 户外骑行 / 健身房`，再下一行 `AI 语音互动跑` 横条，最后一行 `音乐 / GO / 装备` —— `GO` 是绿色大圆按钮，两侧「音乐」「装备」是小灰字。从 `运动` Tab 到记录态 **1 次点击**（GO），加上切 Tab 共 **2 步**，达标。来源：https://apps.apple.com/cn/app/keep-ai-%E8%BF%90%E5%8A%A8%E6%95%99%E7%BB%83/id952694580 （refs `keep/launch-light.jpg`、`keep/pre-run-light.jpg`）。冷启动默认落在哪个 Tab 未被素材覆盖，不描述。

为什么有效：自上而下是「先定怎么跑（模式）→ 再定跑什么（运动）→ 最后出发（GO）」的决策顺序，和用户脑内的顺序一致；GO 独占最后一行的视觉重心，两侧次要点用灰字小图标，谁主谁次一眼分明。

决策：采用 —— 采用「主操作独占底部一行、左右只放次要点按」的构图，以及 ≤2 步起跑。拒绝其 5 Tab、三模式与三运动的层级扩张（本产品单运动、无课程模式）。

### Keep · running（跑步中）

观察：来源缺失。已尝试：App Store 产品页 6 张截图（https://apps.apple.com/cn/app/keep-ai-%E8%BF%90%E5%8A%A8%E6%95%99%E7%BB%83/id952694580 ）；官网 https://www.gotokeep.com/ 的 App 截图托管在非白名单 CDN，不可作为证据；无官方预览视频。

为什么有效：无素材不判断。

决策：拒绝 —— 无证据不抄。

### Keep · summary（结束与总结）

观察：来源缺失。已尝试：App Store 产品页 6 张截图（https://apps.apple.com/cn/app/keep-ai-%E8%BF%90%E5%8A%A8%E6%95%99%E7%BB%83/id952694580 ）；无结束确认/保存/跑后总结素材。

为什么有效：无素材不判断。

决策：拒绝 —— 无证据不抄。

### Keep · history（历史列表与详情）

观察：`数据` 页是「今日概览 / 身体能力 / 全部数据」三分段，下面是三个环形指标（`饮食 82` / `训练 86` / `睡眠 92`），再接一张 `AI 洞察` 卡（一句结论 + `查看完整分析 ›`），最下面是 `体重 66.2 / 63.8 公斤` 与一条折线趋势。逐次跑步记录列表没有出现在素材里。来源：https://apps.apple.com/cn/app/keep-ai-%E8%BF%90%E5%8A%A8%E6%95%99%E7%BB%83/id952694580 （refs `keep/history-light.jpg`）。

为什么有效：把「今天怎么样」压成三个环形加一句自然语言结论，比堆指标更省阅读成本；趋势图只留一条主线与首尾标注，不铺坐标网格。

决策：拒绝 —— 三个环形与 AI 洞察卡都不进本产品（无多指标数据源，也没有 AI 结论可信度保证）；采用「一张聚合卡只讲一件事 + 一个下钻入口」的克制，落到 HistoryView 的空态与分组标题。

### Keep · empty-permission（空态与权限拒绝态）

观察：来源缺失。已尝试：App Store 产品页 6 张截图（https://apps.apple.com/cn/app/keep-ai-%E8%BF%90%E5%8A%A8%E6%95%99%E7%BB%83/id952694580 ）；无空态或定位权限拒绝素材。

为什么有效：无素材不判断。

决策：拒绝 —— 无证据不抄。

## 视觉层

### 配色（浅色 / 深色）

观察：Strava 浅色记录屏是纯白底 + 纯黑数字 + 淡灰标签与 hairline，唯一彩色是动作橙（`START`、暂停钮、选中项）；深色侧（Home feed、训练详情）背景近黑、卡片只比背景提亮一档，橙色同样只出现在可执行项与选中态。Nike 浅色是白底黑字，蓝色只出现在柱状图与选中分段。Apple Fitness 深色是纯黑底 + 一档灰的卡面，荧光绿只给动作与选中 Tab。Keep 浅色是浅灰紫底 + 纯白卡，主色绿只给 GO。来源：https://apps.apple.com/us/app/strava-running-and-cycling/id426826309 、https://www.nike.com/nrc 、https://apps.apple.com/us/app/fitness/id1208224953 、https://apps.apple.com/cn/app/keep-ai-%E8%BF%90%E5%8A%A8%E6%95%99%E7%BB%83/id952694580

为什么有效：四家都把品牌色压缩到只标记「可执行 / 选中」，其余信息全部交给黑白灰的明度层级；一屏里「颜色出现在哪里」本身就变成了操作提示，用户不需要读文案就知道下一步按哪儿。

决策：采用 —— 单一品牌色只用于主操作、记录态与选中态，其余靠 `primary / secondary / separator` 的明度分层；浅深两套同构（`Colors.accent` 已在 `DesignTokens.swift` 成对定义，不新增色值）。

### 字号层级

观察：Strava 记录屏的标签（`TIME` / `SPEED` / `DISTANCE`）是全大写小号灰字，数值与标签的字高比目测约 6–8 倍，单位再小一号；Nike 详情页 hero 距离 `3.12` 与六个指标数字之间是「hero 约为指标 3 倍」的对比；Apple Fitness 卡内是「卡标题一档、数值一档、标签更小一档」。四家都不靠颜色区分层级，而靠字号与字重。来源：https://apptrailers.itunes.apple.com/itunes-assets/PurpleVideo221/v4/41/ed/c4/41edc4fa-6050-7e53-ca2f-9ef4a3295dd3/P1126263724_Anull_video_gr265_sdr_886x1920.m3u8 、https://www.nike.com/nrc 、https://apps.apple.com/us/app/fitness/id1208224953

为什么有效：跑步场景是「远处、晃动中扫一眼」，字号差必须极大才成立；小号全大写标签在视觉重量上足够轻，不会和数值抢注意力。

决策：采用 —— 保持 4 档以内的阶梯，并在跑步中屏把主数值与标签的比值拉到 6 倍以上；为此拟新增两个排版 token（见映射表，本轮不改代码）。

### 圆角与阴影

观察：Apple Fitness 的卡片是大圆角（目测约 20pt）且看不到描边；Nike 的卡片同样是大圆角、无描边；Keep 的白卡压在浅灰底上，靠明度差分层；Strava 记录屏干脆没有卡片，只有 hairline 分隔。四家截图里都看不到明显投影 —— 深色侧靠卡面比背景亮一档，浅色侧靠 hairline 或极浅的底色分层。来源：https://apps.apple.com/us/app/fitness/id1208224953 、https://www.nike.com/nrc 、https://apps.apple.com/cn/app/keep-ai-%E8%BF%90%E5%8A%A8%E6%95%99%E7%BB%83/id952694580 、https://apptrailers.itunes.apple.com/itunes-assets/PurpleVideo221/v4/41/ed/c4/41edc4fa-6050-7e53-ca2f-9ef4a3295dd3/P1126263724_Anull_video_gr265_sdr_886x1920.m3u8

为什么有效：无投影 = 没有堆叠感，界面读起来是「同一平面上的分区」而不是「浮起的卡片」，在深色下尤其干净；大圆角提供柔和感，代价只是四角几个像素。

决策：采用 —— 大圆角 + 零投影 + hairline 分层，直接用既有 `Radius.card 16` / `Radius.panel 20` / `Stroke.hairline`，不新增阴影 token。

### 动效节奏

观察：唯一可用的动态素材是 Strava 官方预览视频（30fps、约 30 秒）：记录屏上的数字以秒为节拍原地刷新（`00:00:06` → `00:00:33` → `00:02:35`），数字位宽与行高不变、版面不重排；除此之外整段是营销剪辑的硬切与叠化，没有可以直接测量时长的 App 内过渡动画，故不对竞品的过渡曲线/时长下任何结论。来源：https://apptrailers.itunes.apple.com/itunes-assets/PurpleVideo221/v4/41/ed/c4/41edc4fa-6050-7e53-ca2f-9ef4a3295dd3/P1126263724_Anull_video_gr265_sdr_886x1920.m3u8

观察：来源缺失 —— Nike Run Club、Apple Fitness、Keep 都没有官方预览视频或官方录屏；静态截图不可推断动效，因此这三家的动画节奏、曲线与时长一律不作结论。

为什么有效：数字原地刷新而不重排，视线不需要重新定位，这正是跑步中屏唯一需要的「动态」；装饰性动效在高心率场景里只会增加认知负担。

决策：采用 —— 只做「数值原地更新 + 状态切换短渐变」两类动效，拟新增 `Motion.durationShort`（200ms，用于数值/色块过渡）与 `Motion.durationState`（320ms，用于记录态切换），并要求 Reduce Motion 打开时降级为无动画；拒绝数字滚动、弹性回弹等装饰动效。

### 图标与字体风格

观察：Strava 的运动图标是实心剪影（跑鞋、自行车、瑜伽垫），Tab 图标是细线；记录屏数字是窄体紧缩无衬线，和系统 SF 的比例明显不同。Nike 营销层是全大写超粗无衬线 + 极少图形，App 内是中性无衬线 + 细线图标（日历、发条、跑者）。Apple Fitness 用与「活动绿」绑定的系统线性人形图标。Keep 用圆润中文黑体 + 彩色圆形图标底。来源：https://apps.apple.com/us/app/strava-running-and-cycling/id426826309 、https://www.nike.com/nrc 、https://apps.apple.com/us/app/fitness/id1208224953 、https://apps.apple.com/cn/app/keep-ai-%E8%BF%90%E5%8A%A8%E6%95%99%E7%BB%83/id952694580

为什么有效：图标承担「选哪种运动」的语义，实心剪影比线框在运动中更容易辨认；数字用窄体是为了在同样宽度里塞进更多位数而不缩小字号 —— 但这需要自带字体资源。

决策：拒绝 —— 不引入任何第三方字体与自定义图标资产（本仓契约：仅系统框架、零第三方依赖、SF Symbols + 自绘）。用系统字体的字重与 `monospacedDigit` 复刻「数字不跳动」，用 SF Symbols 覆盖图标语义。

## 映射到本产品

只指向既有视图：`Run/RunView.swift`（首屏 / 跑步中 / 保存态）、`History/HistoryView.swift`、`History/RunDetailView.swift`、`Settings/SettingsView.swift`；token 名只引用 `ios/PurePace/Design/DesignTokens.swift` 既有分组（`Colors` / `Typography` / `Spacing` / `Radius` / `Stroke` / `Icon`），新增一律标 `拟新增` 且本轮不改代码。

| 结论 | 拟落 token / 屏 / 交互 | 来源 |
|---|---|---|
| 首屏即记录入口，0 跳转、0 引导页 | RunView 首屏（保持现有三 Tab 首屏直达，不新增引导/类型选择页） | strava/launch、nike-run-club/launch |
| 记录入口常驻、一屏只一个主操作 | RunView 底部主操作（现有 `safeAreaInset` 位置不变，`Icon.minTapTarget 44`） | strava/launch、keep/launch |
| 主操作独占底部一行，左右仅次要点击 | RunView 主操作 + `Spacing.md` 边距；次要点按用 `secondary` 色 | keep/launch |
| 指标三行结构：上置小标签 / 超大数值 / 下置单位 | `Typography` 拟新增 `metricLabel 11`（小号、`secondary`）与 `metricUnit 11`；RunView 跑步中 | strava/running |
| 主指标距离保持最大，不换成配速 | `Typography.display 56` 继续做距离 hero；RunView 跑步中（明确拒绝竞品的「配速最大」） | strava/running |
| 用 hairline 分组代替卡片堆叠 | `Stroke.hairline`；RunView 跑步中三段指标之间 | strava/running |
| 数字等宽，逐秒刷新不跳动 | `Typography` 数值一律加 `monospacedDigit`（拟新增约束，不改字号）；RunView 跑步中与 RunDetailView | strava/running、nike-run-club/history |
| 暂停/结束在主操作区，单枚大圆、语义明确 | `Colors.warning` / `Colors.accent`、`Icon.control 24`；RunView 跑步中主操作 | strava/running |
| 大圆角 + 零投影 + 明度分层 | `Radius.card 16` / `Radius.panel 20` + `Colors.surface` / `surfaceMuted`；所有卡片 | apple-fitness/history、nike-run-club/history |
| 品牌色只标记可执行与选中 | `Colors.accent` / `onAccent` 用法约束（不做大面积底色）；全局 | strava/launch、apple-fitness/history |
| 列表行：日期标题 + 距离/时长/配速三数值，标签小灰字在下 | HistoryView 行结构（`Typography.title` + `caption` + `Colors.secondary`） | nike-run-club/history |
| 详情页顺序：顶部元信息 → hero 距离 → 指标网格 → 地图 | RunDetailView 版式顺序（`Typography.primaryValue` + `caption`） | nike-run-club/history、strava/history |
| 一屏最多一个视觉主角，其余退为次级卡 | RunView 首屏层级（`primaryValue` 与 `caption` 的对比固定）；全部屏 | apple-fitness/history、keep/history |
| 数值原地更新 + 状态切换短渐变，Reduce Motion 关闭动效 | `Motion` 拟新增 `durationShort 200ms` / `durationState 320ms`；RunView 三态切换 | 无（竞品动效不可测，本产品自定） |
| 结束保存/丢弃显式二选一、可取消 | RunView 保存态（既有 saved 态扩展，不新增屏）；交互按既有状态机契约 | 无（四家 summary 均不可见） |
| 空态与定位拒绝态：一句说明 + 一个可执行下一步 | HistoryView 空态、RunView 定位拒绝提示（`Colors.warning` + `caption`） | 无（四家 empty/permission 均不可见） |

## 不抄竞品菜单结构

被明确拒绝的 IA 扩张项（逐家列出，不做部分引入）：

- **Strava**：`Home` 社交 feed、`Groups` 俱乐部、`Maps` 路线库、`Segments` 路段榜单、Kudos 与评论。本产品没有社交面，也不做 UGC。
- **Nike Run Club**：`Plans` 训练计划、`Club` 会员内容、`Challenges` 挑战卡。不做计划/挑战/赛事。
- **Apple Fitness**：`Fitness+` 订阅内容库、`Sharing` 社交、圆环与 `Awards` 游戏化。不做订阅墙，不做成就体系。
- **Keep**：`课程 / 计划` 内容库、`今日` AI 教练日程、`发现`，以及会员标识与内容锁定。不做内容电商与会员墙。

声明：本产品 IA 保持**「Run / History / Settings 三 Tab + 跑次详情」不变**，不新增 Tab、不新增二级入口、不新增内容库；本轮所有视觉与交互结论都必须在现有三个 Tab 与一个详情页里落地。四家竞品的 5 Tab（Strava / Nike / Keep）与 4 Tab（Apple Fitness）结构一律不复制。

## 附录：复现命令

```bash
# 1) 产品页（带浏览器 UA，跟随重定向；实测 301→200）
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
curl -sSL -A "$UA" -o /dev/null -w "%{http_code} %{size_download}\n" "https://apps.apple.com/us/app/strava-running-and-cycling/id426826309"
curl -sSL -A "$UA" -o /dev/null -w "%{http_code} %{size_download}\n" "https://apps.apple.com/us/app/nike-run-club-running-coach/id387771637"
curl -sSL -A "$UA" -o /dev/null -w "%{http_code} %{size_download}\n" "https://apps.apple.com/us/app/fitness/id1208224953"
curl -sSL -A "$UA" -o /dev/null -w "%{http_code} %{size_download}\n" "https://apps.apple.com/cn/app/keep-ai-%E8%BF%90%E5%8A%A8%E6%95%99%E7%BB%83/id952694580"
curl -sSL -A "$UA" -o /dev/null -w "%{http_code} %{size_download}\n" "https://www.nike.com/nrc"
curl -sSL -A "$UA" -o /dev/null -w "%{http_code} %{size_download}\n" "https://www.gotokeep.com/"

# 2) 单张截图（原分辨率变体：请求超大尺寸由 CDN 回落到源图，不放大）
curl -sSL -f -o docs/design/refs/strava/launch-dark.jpg \
  "https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/d8/5d/38/d85d3879-493c-5ba6-36cd-1ca6e44e8f07/AppStore-TodayTab-6.5-en-US.jpg/9999x9999bb.jpg"

# 3) Strava 官方预览视频（母带清单 → 886x1920 变体 → 定帧）
curl -sS "https://apptrailers.itunes.apple.com/itunes-assets/PurpleVideo221/v4/a6/f2/50/a6f250e3-79cf-dcd3-af53-82f6b1b93b35/P1126263724_default.m3u8"
V="https://apptrailers.itunes.apple.com/itunes-assets/PurpleVideo221/v4/41/ed/c4/41edc4fa-6050-7e53-ca2f-9ef4a3295dd3/P1126263724_Anull_video_gr265_sdr_886x1920.m3u8"
ffmpeg -hide_banner -loglevel error -i "$V" -ss 2.7 -frames:v 1 -y docs/design/refs/strava/pre-run-light.png
ffmpeg -hide_banner -loglevel error -i "$V" -ss 5.5 -frames:v 1 -y docs/design/refs/strava/running-light.png
ffmpeg -hide_banner -loglevel error -i "$V" -vf "fps=1,scale=300:-1" /tmp/strava-%02d.jpg   # 逐秒抽样，用于屏块与 VE 判断

# 4) 证据自检（期望零 FAILED、行数等于图片数、总字节 ≤ 25 MB、无单文件 > 3 MB）
cd docs/design/refs
shasum -a 256 -c manifest.sha256
wc -l < manifest.sha256
find . -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' \) | wc -l
du -sh .
find . -type f -size +3000k | wc -l
```
