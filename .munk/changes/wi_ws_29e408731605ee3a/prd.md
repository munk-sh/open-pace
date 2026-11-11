# 竞品交互与视觉拆解（只新增 docs/design/**）

WorkSet 第 1 波唯一子项。只读竞品调研 + 文档产出；本轮**不产生任何 App 代码、令牌、UI 或门禁改动**，产出物只作为第 2/3/4 波的输入依据。

## 范围

在仓库新增且仅新增 `docs/design/**`，交付三件东西：

1. `docs/design/competitor-teardown.md`：四样本（Strava / Nike Run Club / Apple Fitness / Keep〔不可达时 咕咚〕）逐屏拆解 + 视觉层拆解 + 「映射到本产品」表。
2. `docs/design/refs/<sample>/<screen>-<theme>.<ext>`：参考截图原件，命名受控（见实现约束）。
3. `docs/design/refs/manifest.sha256` + `docs/design/refs/README.md`：逐文件 sha256 与「来源页 URL / 抓取时刻 / 抓取命令 / 版权用途声明」。

### 逐样本逐屏拆解面（四样本 × 5 屏 = 20 个屏块，一个不能少）

| 屏块 key | 拆什么 |
|---|---|
| `launch` | 首屏与「开始跑步」前置路径，含从冷启动到进入记录态的**步数**（≤2 步为合格基准，超 2 步如实记录并在决策里判拒绝） |
| `running` | 跑步中屏：主指标（距离）字号/字重/占比与层级、次要指标集合、暂停与结束操作位置、误触防护（长按/二次确认/边距） |
| `summary` | 结束与总结：结束确认、保存/丢弃路径、总结页信息顺序与主操作 |
| `history` | 历史列表与详情：行信息密度、层级、下钻与返回 |
| `empty-permission` | 空态与权限拒绝态：说明文案、可执行下一步、是否留死路 |

### 视觉层拆解面（全局，非逐屏）

配色（含深色映射）、字号层级、圆角与阴影、动效节奏、图标与字体风格。每项必须给「观察（挂 URL）→ 为什么有效 → 采用 / 明确拒绝」。

### 文档硬结构

- 文档首节写**预算与期望收口时刻**（开工时刻、预算时长、期望收口绝对时刻）。
- 每屏块三段式，前缀必须机器可判：`观察：` / `为什么有效：` / `决策：采用` 或 `决策：拒绝`。
- 末尾「映射到本产品」表：列为 `结论 | 拟落 token / 屏 / 交互 | 来源（sample/屏块）`。
- 单独一节「不抄竞品菜单结构」：写明拒绝哪些 IA 扩张（社交 feed、训练计划、会员墙、多 Tab 膨胀等），并声明本产品 IA 保持「三 Tab + 跑次详情」不变。
- 附录「复现命令」：列出每个 refs 文件的抓取命令与来源页 URL，使他人可复跑。

## 验收

- ac-doc-and-refs-exist: `docs/design/competitor-teardown.md` 存在且非空；`docs/design/refs/` 下至少 4 个样本目录，每个样本目录至少 3 个图片文件（`png|jpg|jpeg|webp`）。
- ac-budget-and-deadline-first: 文档首个二级标题为预算小节，含开工时刻、预算时长、期望收口绝对时刻三个字段（`2026-*` 形式时间戳）。
- ac-four-samples-present: 文档含 `Strava`、`Nike Run Club`、`Apple Fitness`、`Keep` 四个样本的独立二级节；若 Keep 未采用，则文档存在 `Keep 替换原因` 小节，写明实际尝试的 Keep 来源 URL 与失败证据（HTTP 状态码或错误文本），并声明替代样本为 `咕咚`。
- ac-20-screen-blocks: 每个样本下恰好覆盖 `launch` / `running` / `summary` / `history` / `empty-permission` 五个屏块（合计 20 块），且每块都含 `观察：`、`为什么有效：`、`决策：采用|决策：拒绝` 三行前缀。
- ac-every-observation-has-url-or-missing-marker: 任一 `观察：` 行若描述了具体界面事实，则该屏块内必须出现至少一个 `https://` URL；若无可用真实来源，该行必须以 `观察：来源缺失` 开头，并附「已尝试来源 URL + 失败原因」，且该屏块内不得出现对竞品界面的具体描述性断言。
- ac-source-host-whitelist: 文档内所有 `https://` 页面来源 host 落在白名单内：`apps.apple.com`、`*.apple.com`、`*.nike.com`、`*.strava.com`、`*.gotokeep.com`、`*.codoon.com`、`*.youtube.com`（仅限官方频道，须在来源表标注频道名）；媒体资源 URL 允许 `*.mzstatic.com`。
- ac-source-failure-log: 文档含「来源失败记录」表，列出每个失败 URL、失败原因（状态码/错误文本）、以及后续换用的来源；零失败时该节明确写 `无失败来源`。
- ac-visual-layers-covered: 文档含配色（浅/深）、字号层级、圆角与阴影、动效节奏、图标与字体风格五个小节，每节含至少一个 URL 或 `观察：来源缺失` 标记，且每节给出 `决策：采用` 或 `决策：拒绝`。
- ac-motion-source-honest: 「动效节奏」小节的结论只允许来自 App Store 预览视频/官方录屏的显式记录，或标注 `观察：来源缺失` 并说明「静态截图不可推断动效」；不得凭静态图推断动画曲线/时长。
- ac-mapping-table: 文档含「映射到本产品」表，列头为 `结论 | 拟落 token / 屏 / 交互 | 来源`，行数 ≥ 12，且覆盖颜色、字号、间距/圆角、动效四类 token 对象与至少 5 个屏（RunView 首屏、跑步中、总结、HistoryView、RunDetailView）；拟落屏名称只取自既有视图集合，不新增屏。
- ac-no-menu-copy: 文档含「不抄竞品菜单结构」小节，明确列出被拒的 IA 扩张项，并写明本产品保持三 Tab + 跑次详情、不新增 Tab。
- ac-refs-naming: `docs/design/refs/**` 内每个图片文件路径满足 `<sample>/<screen>-<theme>.<ext>`，sample ∈ {`strava`,`nike-run-club`,`apple-fitness`,`keep`,`gudong`}，screen ∈ {`launch`,`pre-run`,`running`,`summary`,`history`,`history-detail`,`empty`,`permission-denied`}，theme ∈ {`light`,`dark`}。
- ac-manifest-verifies: 在 `docs/design/refs/` 目录执行 `shasum -a 256 -c manifest.sha256` 输出零 `FAILED`，且 manifest 行数等于该目录下实际图片文件数（无遗漏、无多余）。
- ac-refs-provenance: `docs/design/refs/README.md` 为每个图片文件记录来源页 URL、抓取时刻（UTC）、抓取命令、以及「仅作文档证据、不进 App、不再分发」的版权声明。
- ac-refs-size-budget: `docs/design/refs/` 单文件 ≤ 3 MB，目录总字节 ≤ 25 MB（超出用 `sips` 降采样，不裁掉内容）。
- ac-no-out-of-scope-change: 相对工作树起始提交，`git status --porcelain` 与 `git diff --name-only` 在 `ios/`、`scripts/`、`.munk/code-gates.json`、`android/`、`shared/`、`docs/` 其余子目录上均为空；全部新增路径都在 `docs/design/**` 下。
- ac-existing-gates-green: `bash scripts/check-ios-shell.sh`、`bash scripts/check-baseline.sh` 退出码 0，且 `.munk/code-gates.json` 的 sha256 与开工前一致（未新增/改名 gate）。
- ac-no-asset-import: `docs/design/refs/` 内只有位图（`png|jpg|jpeg|webp`），不含字体、图标资产、PDF 或可执行文件；App 端零第三方素材落入。
- ac-budget-stop-receipt: 若预算耗尽仍未齐备，仍须落盘已有产出，并在文档顶部「预算与收口」小节写明 `超时停手` 与已完成的屏块清单，不得以静默延长会话代替。

## 非目标

- 不实现任何设计令牌：不新建 `DesignSystem`，不修改 `ios/PurePace/Design/DesignTokens.swift`，不改任何颜色/字号/间距/圆角/阴影/动效数值。
- 不写 `tech.md`，不产出正式技术方案、不排第 2 波以后的实施步骤。
- 不改 UI、交互行为、文案、可及性 identifier、`ios/project.yml`、`xcodeproj`、测试、资源、本地化。
- 不改 `scripts/**`、`.munk/code-gates.json`、CI workflow；不为文档新增 gate。
- 不改 Android / shared。
- 不把竞品截图、字体、图标引入 App 或 `ios/` 任何目录；refs 只作文档证据。
- 不做真机取图、不引导真人操作；本轮无分发动作（无 ASC / ipa / TestFlight / tag）。

## 实现约束

- **来源只认真实可复现地址**：App Store 截图页（`apps.apple.com`，含 `/cn/` 与 `/us/` 两个 storefront）、厂商官网、官方录屏（App Store 预览视频或官方频道）。主观印象、博客二手图、第三方评测图一律不可作为结论来源。
- 抓取口径（本环境已实测）：App Store 页面需带浏览器 UA 且跟随重定向，`curl -sSL -A "Mozilla/5.0 ... AppleWebKit/537.36" <url>` 返回 200 / ~1.3 MB HTML；截图资源在 `is[0-9]-ssl.mzstatic.com/image/thumb/...`，取原分辨率变体，不放大伪造高清。2026-11-11 实测可达：`apps.apple.com`（301→200）、`www.gotokeep.com` 200、`www.codoon.com` 200、`www.nike.com` 200、`www.apple.com` 200。
- **Keep 判定规则**：先试 Keep 官方站与 App Store 页；若连续失败，按 `ac-four-samples-present` 记录失败证据后换 咕咚，目录 slug 用 `gudong`，并在文档说明替换原因；未失败则必须用 Keep，不得为了省事直接换样本。
- **不可见即标注**：空态 / 权限拒绝态 / 动效 / 深色在多数学样本上无公开可复现素材。缺素材时一律 `观察：来源缺失` + 尝试记录，禁止用「通常」「应该是」这类推断冒充观察。
- refs 目录 slug 固定：`strava` / `nike-run-club` / `apple-fitness` / `keep` / `gudong`；屏 key 与 theme 见 `ac-refs-naming`，不新增枚举值。
- 映射表只允许指向既有视图：`Run/RunView.swift`、`History/HistoryView.swift`、`History/RunDetailView.swift`、`Settings/SettingsView.swift`；token 名必须引用 `ios/PurePace/Design/DesignTokens.swift` 既有分组（`Colors` / `Typography` / `Spacing` / `Radius` / `Stroke` / `Icon`），新增 token 一律标注 `拟新增` 并给理由，本轮不改代码。
- 与本仓既有取舍不冲突的前提：系统字体做字重/字号层级、只用 SF Symbols 与自绘、zh-Hans 单语、浅深色同构、主操作 ≥44pt、动态字体最大档不截断、identifier 集合只增不改；拆解结论若与这些冲突，在决策里写「拒绝」并说明。
- 文档正文用 zh-Hans；引用竞品原界面英文/中文文案时放在引号内作为证据，不受「App 内禁止中英混排」约束（该约束只针对 `ios/` 文案）。
- 文档内出现的每个 URL 必须是本次实际访问过的页面或资源地址，不得凭记忆写域名路径；附录复现命令须能直接粘贴复跑。
- 预算：单会话墙钟预算 90 分钟（采集 ≤60 分钟、写作 ≤25 分钟、校验 ≤5 分钟），开工时刻与期望收口绝对时刻写进文档首节；到点即停手并按 `ac-budget-stop-receipt` 落回执。
- 校验只用本机已有工具（`shasum`、`sips`、`git`、`bash`、`curl`），不装新依赖；不为文档校验新增脚本文件或 gate。
