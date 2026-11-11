# refs 参考截图来源与 sha256 清单

本目录只存放**文档证据用**的竞品界面位图。图片不进 App、不进 `ios/`、不再分发；分析结论见 `../competitor-teardown.md`。

- 全部位图来自公开可复现页面：App Store 产品页截图 / 厂商官网 / App Store 官方预览视频。
- 抓取时刻一律 UTC（`2026-11-11`，与 `competitor-teardown.md` 的采集窗口 `02:43Z–03:20Z` 一致）。
- 校验：在本目录执行 `shasum -a 256 -c manifest.sha256`。
- 体积：单文件 ≤ 3 MB，目录总字节 ≤ 25 MB。

## 版权与用途声明

这些截图与视频抽帧的著作权归 Strava、Nike、Apple、Keep 各自所有。本仓库仅将其作为**竞品拆解的文档证据**（评论、比较、研究用途），不用于 App 内展示、不进入任何产品资源、不再分发、不用于商业宣传。若权利人要求，删除本目录即可，不影响任何代码与门禁。

## 目录与命名

路径格式固定为 `<sample>/<screen>-<theme>.<ext>`：

- `sample` ∈ `strava` / `nike-run-club` / `apple-fitness` / `keep`（Keep 官方站与 App Store 页均可达，未启用咕咚替代）
- `screen` ∈ `launch` / `pre-run` / `running` / `summary` / `history` / `history-detail` / `empty` / `permission-denied`
- `theme` ∈ `light` / `dark`

本轮实际入库 15 个文件；无 `summary` / `empty` / `permission-denied` 素材：四家公开素材里都没有结束保存页、空态与权限拒绝态，缺素材不补造（见拆解文档对应屏块）。

## 逐文件记录

### strava/launch-dark.jpg

- 来源页：https://apps.apple.com/us/app/strava-running-and-cycling/id426826309
- 媒体地址：https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/d8/5d/38/d85d3879-493c-5ba6-36cd-1ca6e44e8f07/AppStore-TodayTab-6.5-en-US.jpg/9999x9999bb.jpg
- 抓取时刻：`2026-11-11T02:53:44Z`
- 抓取命令：`curl -sSL -f -o docs/design/refs/strava/launch-dark.jpg "https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/d8/5d/38/d85d3879-493c-5ba6-36cd-1ca6e44e8f07/AppStore-TodayTab-6.5-en-US.jpg/9999x9999bb.jpg"`
- 对应屏块：Strava · `launch`（深色 Home feed 首屏，底部 5 Tab）
- 尺寸 / 字节：1242×2688 / 393799

### strava/pre-run-dark.jpg

- 来源页：https://apps.apple.com/us/app/strava-running-and-cycling/id426826309
- 媒体地址：https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/91/4d/82/914d8235-d689-dd03-ff95-b1100dbdfaa9/ASO-6.5-TrackWorkouts-en-US1201.jpg/9999x9999bb.jpg
- 抓取时刻：`2026-11-11T02:53:45Z`
- 抓取命令：`curl -sSL -f -o docs/design/refs/strava/pre-run-dark.jpg "https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/91/4d/82/914d8235-d689-dd03-ff95-b1100dbdfaa9/ASO-6.5-TrackWorkouts-en-US1201.jpg/9999x9999bb.jpg"`
- 对应屏块：Strava · `launch`（Record 页 + Choose a Sport 面板，深色）
- 尺寸 / 字节：1242×2688 / 374265

### strava/pre-run-light.png

- 来源页：https://apps.apple.com/us/app/strava-running-and-cycling/id426826309
- 媒体地址：https://apptrailers.itunes.apple.com/itunes-assets/PurpleVideo221/v4/41/ed/c4/41edc4fa-6050-7e53-ca2f-9ef4a3295dd3/P1126263724_Anull_video_gr265_sdr_886x1920.m3u8
- 抓取时刻：`2026-11-11T02:52Z`（官方预览视频抽帧，命令见附录）
- 抓取命令：`ffmpeg -hide_banner -loglevel error -i "<媒体地址>" -ss 2.7 -frames:v 1 -y out.png`
- 对应屏块：Strava · `pre-run`（Choose a Sport 面板，浅色）
- 尺寸 / 字节：886×1920 / 402576

### strava/running-light.png

- 来源页：https://apps.apple.com/us/app/strava-running-and-cycling/id426826309
- 媒体地址：https://apptrailers.itunes.apple.com/itunes-assets/PurpleVideo221/v4/41/ed/c4/41edc4fa-6050-7e53-ca2f-9ef4a3295dd3/P1126263724_Anull_video_gr265_sdr_886x1920.m3u8
- 抓取时刻：`2026-11-11T02:52Z`（官方预览视频抽帧，命令见附录）
- 抓取命令：`ffmpeg -hide_banner -loglevel error -i "<媒体地址>" -ss 5.5 -frames:v 1 -y out.png`
- 对应屏块：Strava · `running`（记录中三组指标 + 暂停，浅色）
- 尺寸 / 字节：886×1920 / 335478

### strava/history-detail-dark.jpg

- 来源页：https://apps.apple.com/us/app/strava-running-and-cycling/id426826309
- 媒体地址：https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/35/34/27/35342763-a02b-a58a-5d86-1ab868464a4e/ASO-6.5-TrackWorkouts-en-US1201.jpg/9999x9999bb.jpg
- 抓取时刻：`2026-11-11T02:53:45Z`
- 抓取命令：`curl -sSL -f -o docs/design/refs/strava/history-detail-dark.jpg "https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/35/34/27/35342763-a02b-a58a-5d86-1ab868464a4e/ASO-6.5-TrackWorkouts-en-US1201.jpg/9999x9999bb.jpg"`
- 对应屏块：Strava · `history`（训练记录详情：人体图 + 四列指标，深色）
- 尺寸 / 字节：1242×2688 / 298496

### nike-run-club/launch-light.png

- 来源页：https://www.nike.com/nrc
- 媒体地址：https://static.nike.com/a/images/f_auto,cs_srgb/w_1920,c_limit/ea5c329a-52f9-43a5-a21b-0172ad211685/nike-run-club-app.png
- 抓取时刻：`2026-11-11T02:53:49Z`
- 抓取命令：`curl -sSL -f -o docs/design/refs/nike-run-club/launch-light.png "https://static.nike.com/a/images/f_auto,cs_srgb/w_1920,c_limit/ea5c329a-52f9-43a5-a21b-0172ad211685/nike-run-club-app.png"`
- 对应屏块：Nike Run Club · `launch`（Run 页三段式起始：Start a Run / Guided Runs / Training Plans）
- 尺寸 / 字节：1920×1286 / 148681

### nike-run-club/pre-run-light.png

- 来源页：https://apps.apple.com/us/app/nike-run-club-running-coach/id387771637
- 媒体地址：https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/d0/92/f8/d092f8a8-fdba-6144-a6ab-3664358c4f2f/92fa0975-fd9c-4447-a363-3d07e37f676e_Nike_NikeRunClub_en-US_iOS_6.5_ScreenshotMockup_240820_02.png/9999x9999bb.png
- 抓取时刻：`2026-11-11T02:53:47Z`
- 抓取命令：`curl -sSL -f -o docs/design/refs/nike-run-club/pre-run-light.png "https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/d0/92/f8/d092f8a8-fdba-6144-a6ab-3664358c4f2f/92fa0975-fd9c-4447-a363-3d07e37f676e_Nike_NikeRunClub_en-US_iOS_6.5_ScreenshotMockup_240820_02.png/9999x9999bb.png"`
- 对应屏块：Nike Run Club · `pre-run`（引导跑详情页 + 白色圆形 START）
- 尺寸 / 字节：1284×2778 / 1609580

### nike-run-club/history-light.jpg

- 来源页：https://apps.apple.com/us/app/nike-run-club-running-coach/id387771637
- 媒体地址：https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/ad/71/d5/ad71d5d9-b4f8-4b93-a064-0b2d37a780a3/708c8350-8cc9-480c-b4e5-c9940fbfd38d_Nike_NikeRunClub_en-US_iOS_6.5_ScreenshotMockup_240820_01.png/9999x9999bb.png
- 抓取时刻：`2026-11-11T02:53:47Z`（下载 PNG 后按体积预算用 `sips` 转 JPEG，未改动内容）
- 抓取命令：`curl -sSL -f -o /tmp/nike.png "<媒体地址>" && sips -s format jpeg -s formatOptions 85 /tmp/nike.png --out docs/design/refs/nike-run-club/history-light.jpg`
- 对应屏块：Nike Run Club · `history`（Activity 页：本周汇总 + Recent Activity 行）
- 尺寸 / 字节：1284×2778 / 744835

### nike-run-club/history-detail-light.jpg

- 来源页：https://www.nike.com/nrc
- 媒体地址：https://static.nike.com/a/images/f_auto,cs_srgb/w_1920,c_limit/638ce2b8-4c31-4ef3-bc4a-3c60dbea3a6f/nike-run-club-app.jpg
- 抓取时刻：`2026-11-11T02:53:52Z`
- 抓取命令：`curl -sSL -f -o docs/design/refs/nike-run-club/history-detail-light.jpg "https://static.nike.com/a/images/f_auto,cs_srgb/w_1920,c_limit/638ce2b8-4c31-4ef3-bc4a-3c60dbea3a6f/nike-run-club-app.jpg"`
- 对应屏块：Nike Run Club · `history`（跑次详情：hero 距离 + 2×3 指标 + 地图）
- 尺寸 / 字节：1920×1000 / 301156

### apple-fitness/launch-dark.png

- 来源页：https://apps.apple.com/us/app/fitness/id1208224953
- 媒体地址：https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/13/3f/22/133f22f9-d45e-101e-ab48-e0942118165f/Fitness-iPhone6p9-LuckC-USEN-Wrapper4.png/9999x9999bb.png
- 抓取时刻：`2026-11-11T02:53:53Z`
- 抓取命令：`curl -sSL -f -o docs/design/refs/apple-fitness/launch-dark.png "https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/13/3f/22/133f22f9-d45e-101e-ab48-e0942118165f/Fitness-iPhone6p9-LuckC-USEN-Wrapper4.png/9999x9999bb.png"`
- 对应屏块：Apple Fitness · `launch`（Workout 页：运动类型行，行内绿色播放圆钮）
- 尺寸 / 字节：1320×2868 / 2148510

### apple-fitness/pre-run-dark.png

- 来源页：https://apps.apple.com/us/app/fitness/id1208224953
- 媒体地址：https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/9f/c3/5f/9fc35fe7-64f5-e405-96fb-28b33088df7d/Fitness-iPhone6p9-LuckC-USEN-Wrapper3.png/9999x9999bb.png
- 抓取时刻：`2026-11-11T02:53:54Z`
- 抓取命令：`curl -sSL -f -o docs/design/refs/apple-fitness/pre-run-dark.png "https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/9f/c3/5f/9fc35fe7-64f5-e405-96fb-28b33088df7d/Fitness-iPhone6p9-LuckC-USEN-Wrapper3.png/9999x9999bb.png"`
- 对应屏块：Apple Fitness · `pre-run`（运动类型三列网格 + Get Started / Skip）
- 尺寸 / 字节：1320×2868 / 1976661

### apple-fitness/history-dark.png

- 来源页：https://apps.apple.com/us/app/fitness/id1208224953
- 媒体地址：https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/a0/e0/ad/a0e0ad1b-f65e-9134-9b7d-dca428d14346/Fitness-iPhone6p9-LuckC-USEN-Wrapper1.png/9999x9999bb.png
- 抓取时刻：`2026-11-11T02:53:55Z`
- 抓取命令：`curl -sSL -f -o docs/design/refs/apple-fitness/history-dark.png "https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/a0/e0/ad/a0e0ad1b-f65e-9134-9b7d-dca428d14346/Fitness-iPhone6p9-LuckC-USEN-Wrapper1.png/9999x9999bb.png"`
- 对应屏块：Apple Fitness · `history`（Summary 页：圆环卡 + 步数/距离卡 + Sessions 卡）
- 尺寸 / 字节：1320×2868 / 1402928

### keep/launch-light.jpg

- 来源页：https://apps.apple.com/cn/app/keep-ai-%E8%BF%90%E5%8A%A8%E6%95%99%E7%BB%83/id952694580
- 媒体地址：https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/3d/9c/8c/3d9c8c94-77fa-07db-1974-44f9db610691/02__U8bfe_U7a0b__U00b7_1206_U00d72622.jpg/9999x9999bb.jpg
- 抓取时刻：`2026-11-11T02:53:55Z`
- 抓取命令：`curl -sSL -f -o docs/design/refs/keep/launch-light.jpg "https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/3d/9c/8c/3d9c8c94-77fa-07db-1974-44f9db610691/02__U8bfe_U7a0b__U00b7_1206_U00d72622.jpg/9999x9999bb.jpg"`
- 对应屏块：Keep · `launch`（课程首页：顶部三分段 + 底部 5 Tab）
- 尺寸 / 字节：1206×2622 / 527038

### keep/pre-run-light.jpg

- 来源页：https://apps.apple.com/cn/app/keep-ai-%E8%BF%90%E5%8A%A8%E6%95%99%E7%BB%83/id952694580
- 媒体地址：https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/92/55/56/92555635-42b3-e43a-9fd1-5567cad3c661/04__U8fd0_U52a8__U00b7_1206_U00d72622.jpg/9999x9999bb.jpg
- 抓取时刻：`2026-11-11T02:53:59Z`
- 抓取命令：`curl -sSL -f -o docs/design/refs/keep/pre-run-light.jpg "https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/92/55/56/92555635-42b3-e43a-9fd1-5567cad3c661/04__U8fd0_U52a8__U00b7_1206_U00d72622.jpg/9999x9999bb.jpg"`
- 对应屏块：Keep · `pre-run`（运动页：模式胶囊 + 户外跑步 + 绿色 GO）
- 尺寸 / 字节：1206×2622 / 443510

### keep/history-light.jpg

- 来源页：https://apps.apple.com/cn/app/keep-ai-%E8%BF%90%E5%8A%A8%E6%95%99%E7%BB%83/id952694580
- 媒体地址：https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/e8/df/2f/e8df2fb4-1333-2880-b238-0a84533342e7/06__U6570_U636e__U00b7_1206_U00d72622.jpg/9999x9999bb.jpg
- 抓取时刻：`2026-11-11T02:53:59Z`
- 抓取命令：`curl -sSL -f -o docs/design/refs/keep/history-light.jpg "https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/e8/df/2f/e8df2fb4-1333-2880-b238-0a84533342e7/06__U6570_U636e__U00b7_1206_U00d72622.jpg/9999x9999bb.jpg"`
- 对应屏块：Keep · `history`（数据页：今日三环 + AI 洞察 + 体重趋势）
- 尺寸 / 字节：1206×2622 / 344911

## 校验

```bash
cd docs/design/refs
shasum -a 256 -c manifest.sha256          # 期望零 FAILED
find . -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' \) | wc -l
wc -l < manifest.sha256                    # 两数必须相等
du -sh .                                   # 期望 ≤ 25 MB
find . -type f -size +3000k | wc -l        # 期望 0
```
