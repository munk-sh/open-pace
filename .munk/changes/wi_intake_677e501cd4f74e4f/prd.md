# V1.2 B1 结束态 + C2 丢弃确认：机械收口（apply patch → commit → 门禁 → delivery）

## Scope

公司 13:40Z 裁决的机械收口项，不是新功能。V1.2 的 B1 结束态版式与 C2 丢弃确认实现已在旧项 `wi_intake_93f2857d51330b9d` 的 worktree index 完成并验证过，现以 patch 留档。本项**只做** apply + 单一实现 commit + 门禁复跑 + 证据绑定 + delivery（默认 local_merge），并闭环两个待核项（C2 sheet 取数自相矛盾、inline 权限胶囊高度实测）。

- base 固定 `eceedb90948706b813073c9b664074e3df3b116a`，不 rebase、不换 base。
- patch：`/Users/zhutao/Library/Application Support/Munk-AI/munk-auto/products/codebase_19e8ad47434ff059/artifacts/wi_intake_93f2857d51330b9d/b1c2-unclosed/b1c2-staged.patch`，sha256 必须 = `f3ed82dd52ac21dbaa7039460126045fb305a5e7f52b71eb11359a0dfba8ccae`（15 文件 / +759 −208），`git apply --check` 必须干净。
- 证据：归档副本 `.../b1c2-unclosed/evidence/`（4 PNG、4 日志、SHA256SUMS、README）；落仓路径 `docs/evidence/wi_intake_93f2857d51330b9d/`（base 上不存在，需从归档/旧项 worktree 只读复制进本项提交）。
- 旧项 checkpoint 仅供参考：`~/Library/Application Support/Munk-AI/munk-auto/worktrees/codebase_19e8ad47434ff059/wi_intake_93f2857d51330b9d/.munk/runs/run_intake_93f2857d51330b9d/progress.md`。

## Acceptance Criteria

- ac-patch-sha-and-base: `shasum -a 256` 对 patch 得 `f3ed82…ccae`；`git apply --check` 在 `eceedb9` 上 exit 0；apply 后 `git diff --stat` 恰 15 文件 / +759 −208，且无 patch 之外的文件改动（证据目录除外，见 ac-evidence-in-repo）。
- ac-single-impl-commit: 实现以单一 commit 落在本项分支（不停在 index/工作区）；commit 的 parent 为 `eceedb9`，未 rebase/未改 base。
- ac-self-test-100: `bash scripts/check-ios-shell.sh --self-test` exit 0 且汇总 100 项 0 失败，含 `accent 仅作填充正例` 放行与 `accent 作前景反例` 判红、`hero 回退 accent 前景反例` 判红、`design-b1-regression` / `design-c2-medium` 判红。
- ac-shell-33: `bash scripts/check-ios-shell.sh` exit 0，汇总 33 项 0 失败（含 42 identifier 计数单调与冻结基线断言）。
- ac-unit-265-173: `bash scripts/test-ios.sh --unit-only` 下 PurePaceTests 执行 265、RunCore 执行 173，0 失败。
- ac-gates-22: `.munk/code-gates.json` 的 22 门全部绿（不新增/删除/放宽门禁，不跑 `ios.yml` 权威腿）。
- ac-c2-sheet-probe-unambiguous: C2 断言日志不再出现 `sheetExists=false` 与高度并存的含糊组合——取数改为由真实元素推导（sheet 顶边取确认层标题静态文本 `frame.minY − Spacing.xs` 或等价可复核锚点），日志同时打印屏幕高、推导顶边、推导高度、confirm/cancel frame；仍断言顶边 ≥ 屏高 70%、高度 ≤200、confirm 44pt、confirm/cancel 中心差 ≤2pt。若选择保留 `app.sheets` 探测，必须在证据 README 写明其在 iOS 18.6 不匹配 SwiftUI `.presentationDetents` sheet 的实测依据，且日志用 `sheetContainerMatched` 与 `presented=true`（由 confirm+cancel 同时存在判定）区分，不得再出现「false 但高度存在」的自相矛盾输出。
- ac-inline-hint-measured: inline 权限胶囊在真实 UI 腿取得实测高度并打印（`-uiTestLocation` 测试源固定 `authorizedWhenInUse` → `run.backgroundDegraded` 胶囊确定性出现），断言高度 ≤32pt 且宽度 < 内容宽（不占满整行）；实测值写入证据 README 与 `docs/verification-matrix.md` B1 行（覆盖此前仅来自设计稿的 23.7pt 口径）。
- ac-hero-tint-primary: hero 主值色 light=dark=`primary`（不改回 accent）；`RunInteractionPlan.heroTint` running/paused/finished 均为 `.primary`，`check-ios-shell.sh` 禁止 `case .running, .paused: return .accent` 的守卫存在且反例判红。
- ac-identifiers-frozen: 不新增/修改/删除任何 accessibilityIdentifier（冻结 33 项、去重计数 42 不变；`--self-test` 的 identifier 计数自检保持绿）。
- ac-matrix-23-rows: `docs/verification-matrix.md` 数据行恰 23 行（表头 2 行除外），仅就地更新 C2 与 B1 两行内容（实测胶囊高度、C2 取数口径），不删行、不加行。
- ac-evidence-in-repo-and-bound: `docs/evidence/wi_intake_93f2857d51330b9d/` 入仓（4 PNG + 4 日志 + SHA256SUMS + README，来自归档副本）；README 的「构建 head sha」改为本项实现 commit，并补 `git rev-parse <本项 commit>^{tree}` 与 patch sha256，说明截图构建树 = 交付代码树。
- ac-evidence-fresh-or-proven: 在本项 commit 上重跑两条证据 UI 腿并导出 4 张 PNG；若与归档 PNG 哈希不同（含任何重排版/像素差异），必须用新图替换并更新 `SHA256SUMS` 与 README 实测值（`shasum -a 256 -c SHA256SUMS` 通过）；若哈希一致，README 记录「新构建重出哈希相同」作为绑定证据。
- ac-no-version-and-scope: `VERSION` 保持 `0.1.0`；不跑 `ios.yml` 权威腿、不产出 14 张复评截图（写项③）；不改 binding/DB、不动旧项 worktree/分支、不改状态机/持久化/播报/GPX 逻辑、不动 token 色值与对比度阈值。
- ac-delivery-local-merge: 交付走默认 local_merge，跑完后分支可合入且工作区干净（无未提交残留）。

## Non-Goals

- 重写视图 / 重排 B1·C2 / 另起实现 / 以「改进」为名扩范围。
- 新增页面、组件、颜色键、字号档或新 identifier 集合。
- 修改 token 值、对比度阈值、品牌优先豁免登记。
- 跑 `.github/workflows/ios.yml` 权威腿、出 14 张复评截图（后续写项③）。
- 改版本号、改 CI 预算/超时/分段策略、删腿或放宽断言。
- 在旧项 worktree/branch 上施工或删除它；触碰 binding/DB。

## Implementation Constraints

（已约定约束与现场锚点，不是新方案）

- 执行顺序：`shasum -a 256` + `git apply --check` → `git apply` → **立即 commit**（唯一实现 commit，parent=eceedb9）→ 复跑门禁 → 证据绑定 → delivery。
- patch 已自带：`RunFinishedSummaryLayoutPolicy`（standardMapHeroHeight 360 / 40% / 691 预算 / inlineHintMaxHeight 32 / actionBarHeight 68）、`RunInteractionPlan`（`Emphasis.text`、`Style.textSecondary`/`.dangerFilled`，移除 `.dangerOutline`，heroTint 恒 primary）、`RunView`（B1 finishedContent + 地图 hero 叠加 `run.distance`、C2 `onGeometryChange` 实测高度 detent）、单测/UI 断言重基、`scripts/check-ios-shell.sh` B1/C2/accent 守卫与自检沙箱、`docs/verification-matrix.md` 两行重写、`ios/project.yml` 给 UITest target 补 policy 源。
- 旧项 evidence README 的 4 张图和 `SHA256SUMS` 中：`c2-discard-*`/`b1-finished-*`；归档副本即 `.../b1c2-unclosed/evidence/`。`docs/evidence/wi_intake_93f2857d51330b9d/` 必须进 commit，矩阵证据路径才不悬空。
- 待核①取数建议（非强制实现细节）：`app.sheets.firstMatch` 在 iOS 18.6 的 SwiftUI `.presentationDetents` sheet 上实测不匹配（旧日志 `sheetExists=false` 同时 `top=685 height=167`）；改为用确认层标题静态文本（zh-Hans「丢弃这次跑步？」）frame.minY 减 `Spacing.xs` 得到 sheet 顶边，是该 sheet 内容的真实元素，可复核；确认/取消仍作呈现判据。
- 待核②取数建议：`RunTestLocationSource.authorization` 固定 `.authorizedWhenInUse` → `backgroundDegradationHint` 非空 → `run.backgroundDegraded` 胶囊在跑步/结束态确定性出现；`accessibilityIdentifier` 挂在 `hint(...)` 结果上，元素 frame 即胶囊 bounds（含 padding/胶囊底）。在 `RunFlowUITests` 的 `assertBackgroundDegradedDemoted` 或 B1 结束态断言中取 `frame.height/width`，阈值用 `RunFinishedSummaryLayoutPolicy.inlineHintMaxHeight`（32）与屏幕内容宽。
- 证据腿复现：`bash scripts/test-ios.sh --unit-only` 先 build-for-testing + `simctl install`（`test-without-building` 不装 App），再 `xcodebuild test-without-building -project ios/PurePace.xcodeproj -scheme PurePace -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -derivedDataPath .build/ios -only-testing:PurePaceUITests/ScreenshotEvidenceUITests/testEvidenceScreens{Light,Dark} -resultBundlePath …`，浅/深前用 `xcrun simctl ui <udid> appearance light|dark`，`xcresulttool export attachments` 直出 PNG。
- 证据 README 元数据提交：实现 commit 之后取 `git rev-parse HEAD` 与 `git rev-parse HEAD^{tree}`，改 README 后单独 `chore(evidence)` commit；用 `git diff --stat <impl>..<evidence> -- ':!docs/evidence/**'` 为空证明代码树未变。
- 冻结项：`VERSION`=0.1.0 不动；不跑 `ios.yml`；不出 14 张复评截图；不改 binding/DB；不动旧项 worktree/branch。
