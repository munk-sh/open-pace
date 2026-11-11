# Domain: design-research

## 范围

- 承载「竞品交互与视觉拆解」类只读调研产出：结论以文档形式沉淀在 `docs/design/**`，作为后续 UI/令牌/交互波次的输入依据，本身不改 App 代码。
- 当前唯一实体：`docs/design/competitor-teardown.md`（四样本逐屏拆解 + 视觉层拆解 + 映射到本产品）、`docs/design/refs/**`（参考位图 + `manifest.sha256` + `README.md` 逐文件溯源）。
- 与 `ios-ui-design` 域的分工：本域只产结论与证据；token 与视图的落地契约仍在 `ios-ui-design`、`ios/*` 域，真源仍是 `ios/PurePace/Design/DesignTokens.swift` 与 `baseline/design/*`。
- 四样本固定为 Strava / Nike Run Club / Apple Fitness / Keep；Keep 连续失败时才许换 `咕咚`（slug `gudong`）并写替换原因。

## 验收

- ac-doc-and-refs-exist：拆解文档存在且非空；`docs/design/refs/` 下 ≥4 个样本目录，每目录 ≥3 个位图（`png|jpg|jpeg|webp`）。
- ac-budget-and-deadline-first：文档首个二级标题为预算小节，含开工时刻、预算时长、期望收口绝对时刻（`2026-*` 时间戳）。
- ac-four-samples-present：四个样本各有独立二级节；换样本时须有「Keep 替换原因」并附失败证据与替代样本声明。
- ac-20-screen-blocks：每样本恰好覆盖 `launch` / `running` / `summary` / `history` / `empty-permission` 五块（合计 20 块），每块含 `观察：`、`为什么有效：`、`决策：采用|决策：拒绝` 三行前缀。
- ac-every-observation-has-url-or-missing-marker：描述具体界面事实的屏块内必须有 `https://` 来源；无素材时以 `观察：来源缺失` 开头并附已尝试来源与失败原因，且不得出现推断式界面断言。
- ac-source-host-whitelist：页面来源 host 限 `apps.apple.com`、`*.apple.com`、`*.nike.com`、`*.strava.com`、`*.gotokeep.com`、`*.codoon.com`、官方 `*.youtube.com` 频道（须标频道名）；媒体资源允许 `*.mzstatic.com`。
- ac-source-failure-log：有「来源失败记录」表（失败 URL / 原因 / 后续换用），零失败时明确写「无失败来源」。
- ac-visual-layers-covered：配色（浅/深）、字号层级、圆角与阴影、动效节奏、图标与字体风格五节各有 URL 或来源缺失标记，并给采用/拒绝决策。
- ac-motion-source-honest：动效结论只来自官方预览视频/录屏的显式记录，或标注「静态截图不可推断动效」。
- ac-mapping-table：「映射到本产品」表列头 `结论 | 拟落 token / 屏 / 交互 | 来源`，行数 ≥12，覆盖颜色/字号/间距圆角/动效四类 token 对象与至少 5 个既有屏（RunView 首屏、跑步中、总结、HistoryView、RunDetailView）；不新增屏。
- ac-no-menu-copy：有「不抄竞品菜单结构」小节，列明被拒 IA 扩张项，并声明本产品保持三 Tab + 跑次详情、不新增 Tab。
- ac-refs-naming：`docs/design/refs/**` 路径为 `<sample>/<screen>-<theme>.<ext>`，枚举值固定不扩。
- ac-manifest-verifies：`shasum -a 256 -c manifest.sha256` 零 `FAILED`，且 manifest 行数等于实际位图数。
- ac-refs-provenance：`refs/README.md` 逐文件记录来源页 URL、抓取时刻（UTC）、抓取命令与「仅作文档证据、不进 App、不再分发」版权声明。
- ac-refs-size-budget：单文件 ≤3 MB、目录总字节 ≤25 MB（超出用 `sips` 降采样，不裁内容）。
- ac-no-out-of-scope-change：全部新增路径落在 `docs/design/**`，`ios/`、`scripts/`、`.munk/code-gates.json`、`android/`、`shared/`、`docs/` 其余子目录零改动。
- ac-existing-gates-green：`bash scripts/check-ios-shell.sh`、`bash scripts/check-baseline.sh` 退出码 0，且 `.munk/code-gates.json` sha256 与开工前一致。
- ac-no-asset-import：`refs/` 内只有位图，无字体/图标资产/PDF/可执行件；App 端零第三方素材。
- ac-budget-stop-receipt：预算耗尽仍须落盘已有产出，并在「预算与收口」节写 `超时停手` 与已完成屏块清单。

## 非目标

- 不实现设计令牌，不新建 `DesignSystem`，不改 `DesignTokens.swift` 任何颜色/字号/间距/圆角/阴影/动效数值。
- 不写 `tech.md`、不产出正式技术方案、不排后续波次实施步骤。
- 不改 UI、交互行为、文案、可及性 identifier、`ios/project.yml`、`xcodeproj`、测试、资源、本地化。
- 不改 `scripts/**`、`.munk/code-gates.json`、CI workflow；不为文档新增 gate。
- 不改 Android / shared；不把竞品截图、字体、图标引入 App 或 `ios/`。
- 不做真机取图、不引导真人操作；无分发动作（无 ASC / ipa / TestFlight / tag）。

## 实现约束

- 来源只认真实可复现地址：App Store 产品页（含 `/cn/` 与 `/us/` storefront）、厂商官网、官方预览视频/录屏；主观印象、博客二手图、第三方评测图不可作结论来源。
- 抓取口径：App Store 页面需带浏览器 UA 并跟随重定向（`curl -sSL -A "Mozilla/5.0 ... AppleWebKit/537.36"`）；截图取 `is[0-9]-ssl.mzstatic.com` 原分辨率变体，不放大伪造高清。
- 不可见即标注：空态、权限拒绝态、深色、动效缺素材时一律 `观察：来源缺失` + 已尝试记录，不得用「通常 / 应该是」冒充观察。
- refs 目录 slug 固定 `strava` / `nike-run-club` / `apple-fitness` / `keep` / `gudong`；screen 与 theme 枚举按 `ac-refs-naming`，不新增取值。
- 映射表只指向既有视图（`Run/RunView.swift`、`History/HistoryView.swift`、`History/RunDetailView.swift`、`Settings/SettingsView.swift`）；token 名只引用既有分组（`Colors` / `Typography` / `Spacing` / `Radius` / `Stroke` / `Icon`），新增一律标 `拟新增` 并给理由，本轮不改代码。
- 与既有取舍冲突时（系统字体做层级、仅 SF Symbols 与自绘、zh-Hans 单语、浅深色同构、主操作 ≥44pt、Dynamic Type 最大档不截断、identifier 只增不改）在决策里写「拒绝」并说明。
- 文档正文用 zh-Hans；引用竞品原界面文案放引号内作证据，不受「App 内禁止中英混排」约束。
- 文档内 URL 必须是本次实际访问过的页面或资源；附录复现命令须可直接粘贴复跑；校验只用本机已有 `shasum` / `sips` / `git` / `bash` / `curl`，不新增脚本或 gate。
- 单会话墙钟预算 90 分钟（采集 ≤60 / 写作 ≤25 / 校验 ≤5），开工与期望收口绝对时刻写入文档首节，到点即停手并落回执。
- 未落地的 token 提案（`metricLabel 11` / `metricUnit 11` / `Motion.durationShort 200ms` / `Motion.durationState 320ms`）只存在于映射表与文档中，**不构成基线 token**；后续波次落地时必须改 `DesignTokens.swift` 并过对比度与几何门禁。

## 最近交付证明

- workItemId: wi_ws_29e408731605ee3a（2026-11-11，pass）
- 交付：新增仅三件文档产物——`docs/design/competitor-teardown.md`（317 行：预算与收口、来源与取证口径、来源失败记录 8 条、四样本 × 5 屏块共 20 块、视觉层五节、16 行映射表、不抄菜单结构、附录复现命令）；`docs/design/refs/` 15 张位图分 4 个样本目录 + `manifest.sha256`（15 行）+ `refs/README.md`（逐文件来源 URL / 抓取时刻 / 命令 / 版权威声明）。
- 关键结论：四家公开素材只有 8 个屏块有真实界面（`summary` / `empty-permission` 全缺，`running` 仅 Strava），其余 12 块如实记为 `观察：来源缺失`，不补造；起跑步数 Strava 3 步（拒）、其余 launch 直给记录入口（采）；视觉上采「单一品牌色只标可执行/选中 + 大圆角零投影 + hairline 分层 + 字号极端对比 + 数值等宽原地刷新」，拒「配速做 hero、5 Tab 社交 feed / 训练计划 / 会员墙、第三方字体与自定义图标资产」。
- 偏离与未做：`summary` / `empty` / `permission-denied` 无位图（素材不存在，非裁剪）；Keep 可达未启用咕咚替代；预览视频来源为 `apptrailers.itunes.apple.com` 的 m3u8（媒体流，未落在 `*.apple.com` / `*.mzstatic.com` 白名单字面内，已在文档与 README 标注为官方 App Store 预览视频）；无任何代码 / 令牌 / 工程配置 / 脚本 / 门禁 / Android / shared 改动。
- 验证：`code_gates` 22 门 attempt 001 全绿；`shasum -a 256 -c manifest.sha256` 15/15 `OK` 且与目录位图数一致；`git status` 新增路径全部在 `docs/design/**`。
