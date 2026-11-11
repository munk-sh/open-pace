# Domain: design-token-gates

设计令牌静态门禁子域：只收紧「`scripts/check-ios-shell.sh` 的 `validate_design_tokens` 与 `--self-test` 能把每条令牌规则真实判红」这一层。令牌取值、语义、视图与交互仍归 `ios-ui-design`；本域负责扫描范围结构性派生、零字面量三向（色 / 字体 / 动效时长）、令牌分组与色对完整性、阶梯单调冻结、可及 identifier「冻结 33 项只增不改」契约、发布路径 demo/示例入口计数为 0，以及「每条规则都有一个正例一绿 + 一个断言原因串的反例一红」。不新增 gate id、不新增脚本文件。

## 范围

- 主要改动落点在 `scripts/check-ios-shell.sh`（唯一逻辑改动文件）：扩写 `validate_design_tokens`（受管面派生 + 五类规则 + identifier 契约 + demo 计数）与 `run_self_test`（`check_fail_reason` / `check_count` 校验 + 新断言），同步 `usage()` 文案；源码侧只允许 `ios/PurePace/Run/RunView.swift` 追加主操作 identifier 与必需新增清单对齐；不重构其余 validate 函数。
- 受管 UI 面 = `ios/PurePace/Run/**`、`ios/PurePace/History/**`、`ios/PurePace/Settings/**`、`ios/PurePace/ContentView.swift`、`ios/PurePace/Design/*.swift`，由 `find` 目录/通配派生后去掉 token 真源，不再依赖硬编码视图文件名清单；新增视图文件自动进扫描。
- 仅两处结构性豁免，且必须写进脚本注释：①`ios/PurePace/Design/DesignTokens.swift`（字面色值唯一合法来源，靠 `palette`/`purposes`/阶梯断言约束）；②`ios/PurePace/Harness/**`（DEBUG-only 测试夹具，不在发布 UI 面，含 `Color.clear` 这类结构性常量）。禁止为变绿新增白名单。
- 五类规则：零字面色值、零散字体修饰符、零动效时长字面量、令牌分组完整性/唯一性/18 色对成对/`purposes` 键集、阶梯单调与冻结值；identifier 契约由「33 项完全等值」改为「冻结 33 项只增不改」：既有逐项存在 + 必需新增项 + 计数单调不减 + 新增项唯一/非空/带可读 label，另加发布路径 demo/示例入口计数为 0。
- 兼容 macOS `/bin/bash` 3.2：禁 `declare -A` / `mapfile` / `${var,,}` / `[[ =~ ]]`；只用脚本已在用的 `grep -E` / `sed -E` / `awk` / `sort -u` / `tr` / `printf`；`set -euo pipefail` 下可能空匹配的 `grep` 必须 `|| true`。
- 自检夹具沿用「复制真实源码到 `mktemp -d` → 单点变更 → 调 `validate_design_tokens <root>`」，不写仓库。

## 验收

- ac-scan-scope-derived: 受管文件集合由目录/通配派生（含 `Run/**`、`History/**`、`Settings/**`、`ContentView.swift`、`Design/*.swift` 去 token 真源），不依赖硬编码视图名清单；反例「在受管目录新增一个此前不存在的视图文件并塞 `Color(red: 0.1, green: 0.2, blue: 0.3)`」判红且原因串含「字面色值」；现存 `History/RunDetailContent.swift` 被断言属受管面。
- ac-no-literal-colors: 受管面内 `Color(`、`Color.<Name>`、`UIColor`、`#colorLiteral`、`SRGB(hex: 0x…)`、裸 `0x[0-9A-Fa-f]{6}`、`.foregroundStyle(.<Name>)`、`.background(.<Name>)` 任一命中即判红；`Color(red:…)` / `Color.white` / `#colorLiteral(...)` / `SRGB(hex: 0xFFFFFF)` / `.foregroundStyle(.red)` 各一条反例判红且原因串含「字面色值」；真实源码正例零命中、判绿。
- ac-no-stray-font: 受管面内 `.font(.`、裸 `Font.system(` / `Font.custom(`、`.fontWeight(`、`.fontDesign(`、`.lineSpacing(<数字>)` 任一命中判红；`.font(.system(size: 20))` 与裸 `Font.system(size: 18, weight: .bold)` 判红且原因串含「零散字体修饰符」；`.font(DesignTokens.Typography.body)` 判绿（证明不误红合法引用）。
- ac-no-motion-literals: 受管面内 `.animation(` / `withAnimation(` / `Animation.` / `.transition(` 所在行不含 `DesignTokens.Motion.` 判红；`duration: <数字>` / `duration: 0.` 判红；`.animation(.easeInOut(duration: 0.3), value:)` 与 `withAnimation(.linear(duration: 0.25))` 判红且原因串含「动效时长字面量」，`.animation(… duration: DesignTokens.Motion.durationShort …)` 判绿，真实视图 `duration: record.activeDuration` / `activeDuration / 3` 零误红。
- ac-token-groups-complete-unique: 必需分组/常量逐个存在性断言（`Colors.palette` / `Colors.purposes` / `Typography.sizes` / `Spacing.scale` / `Radius.scale` / `Stroke.hairline` / `Icon.scale` / `Motion.durationShort` / `durationState` / `reducedMotionDuration` / `Appearance.supportsDarkMode = true` / `minTapTarget: CGFloat = 44`）；`/^    enum <Group>/` 每个分组只允许出现一次；删 `enum Motion` → 原因串含「Motion」，删 `static let reducedMotionDuration` → 含「reducedMotionDuration」，整块重复追加 → 含「重复」。
- ac-color-pairs-complete: `palette` 恰 18 键，每键恰一条 `ColorPair(light: SRGB(hex: 0x…), dark: SRGB(hex: 0x…))`，light ≠ dark；缺 light / 缺 dark / 同键重复定义判红（原因串含「色对缺 dark」/「重复」）；`purposes` 键集与 `palette` 键集等值（缺键/多键/空用途/复读键名判红，原因串含「用途」）；`static let <key> = color("<key>")` 数量 = 18。
- ac-scale-monotonic-frozen: `Typography.sizes == [11, 12, 15, 20, 34, 56]`、`Spacing.scale == [4, 8, 12, 16, 24, 32]`、`Radius.scale == [12, 16, 20]`、`Icon.scale == [16, 20, 24]`、`Stroke.hairline == 1`、`0 < durationShort(0.2) < durationState(0.32)`、`reducedMotionDuration == 0`、`minTapTarget == 44`，且阶梯严格递增；改档 / 重复 / 乱序均判红（原因串含「阶梯」/「档位」）。
- ac-identifier-frozen-still-red: 既有 33 项 accessibility identifier 逐项必须存在；改名 / 删除任一即判红且原因串含「冻结 identifier 缺失或改名」，不得被其他规则顺带命中而偶然变红。
- ac-identifier-addition-allowed: 追加带非空 `L10n` 可读 label 且全局唯一的新 identifier（如 `run.extra`）判绿；整体计数低于下限（冻结 33 + 必需新增 3 = 36）判红。
- ac-identifier-count-visible: 通过路径必须打印真实计数（`identifier: 36（冻结 33 + 新增 3）`），否则「计数单调」不可验证；demo 入口数同法打印。
- ac-identifier-addition-empty-red: 新增 identifier 为空串、或控件无可读非空 `accessibilityLabel` → 判红（原因串含「不得为空串」/「缺少非空可读」）。
- ac-identifier-addition-duplicate-red: 同一新增 id 在源码出现两次 → 判红（原因串含「必须全局唯一」）；唯一性按 `sort -u` 去重前的原始出现次数判定，既有 `tab.run` 在 `ContentView.swift` 与 `RunView.swift` 各一次属既定事实，不因此判红。
- ac-new-main-action-ids: `run.cancelCountdown` / `run.save` / `run.discard` 三个必需新增主操作 identifier 必须存在（缺失原因串含「缺少必需新增主操作 identifier」），且既有 33 项字面逐个未变。
- ac-demo-entry-zero: 发布路径 `ios/PurePace/**/*.swift` 全量文件中用户可达 demo / 示例入口计数必须为 0（整行注释不计，沿用既有口径）；`#if DEBUG` 块内的示例按钮同样判红（原因串含「demo/示例入口必须为 0」）。
- ac-selftest-red-green: `bash scripts/check-ios-shell.sh --self-test` 退出 0、断言数 ≥ 91（基线 84，本项收口 91），覆盖「改名判红 / 删除判红 / 新增放行并计数 / 空 label 判红 / 空串判红 / 重复判红 / demo 入口判红（含 DEBUG 块）」；每条新规则至少 1 条正例（真实源码副本，不得手写简化正例）+ 1 条反例，反例必须命中预期原因串（只判「非空」不算通过）；自检在 `mktemp -d` 内完成，运行前后 `git status --porcelain` 不因自检新增改动。
- ac-digest-red-green-evidence: 交付回执（change pack `digest.md` 或本域「最近交付证明」）记录全量 `bash scripts/check-ios-shell.sh` 绿跑（含 `N 项断言，0 项失败` 与退出码 0）、`--self-test` 输出（断言数与 0 失败）、以及至少一次真实红跑原始片段（受管面注入字面色值/动效字面量 → 非零退出 + 原因串 + 还原后 `git status --porcelain` 证据）；不得只写「已加固」结论。
- ac-gate-list-unchanged: `.munk/code-gates.json` 零 diff（22 个 gate id 与 `command` 不变），不新增 gate id、不改 `lint-ios-shell` 的 command、不新建脚本文件（允许拆同文件内函数）；`bash -n scripts/check-ios-shell.sh` 退出 0，`--help` 文案同步更新且退出 0。
- ac-token-and-view-freeze: 相对本项起始提交，令牌取值与 `purposes` 文案零 diff，`Run/**`（仅允许 `RunView.swift` 追加三个 `accessibilityIdentifier`）、`History/**`、`Settings/**`、`ContentView.swift`、`Resources/**`、`Design/**`、`ios/project.yml`、`ios/PurePaceTests/**`、`ios/PurePaceUITests/**`、`android/**`、`shared/**` 的 `git diff --name-only` 除该例外均为空；若门禁暴露既有违规，只允许字面量等价替换为既有 token 引用（视觉零变化）并在 digest 逐条列出文件名/行号/替换前后。
- ac-gates-green: `lint-ios-shell`（含 `--self-test`）、`lint`、`lint-ios-scripts`、`test-ios`（`--unit-only`）、`build-ios`、`test-ios-core`、`test-ios-run-core`、`lint-baseline`、`test` 全部退出 0；不靠放宽既有断言补绿。

## 非目标

- 不新增 gate id、不改 `.munk/code-gates.json` 门列表与 `command`、不改 CI workflow、不新建脚本文件。
- 不改视图、交互、文案、页面结构、状态机与动画接线；本轮唯一源码改动是 `RunView.swift` 三个主操作（倒计时取消 / 结束保存 / 结束丢弃）补 `run.cancelCountdown` / `run.save` / `run.discard` 三个 identifier，既有 33 项字面与语义零改动，不新增其他 identifier。
- 不改令牌取值、色值、字号、间距、圆角、动效常量与 `purposes` 文案（`design-token-freeze`）。
- 不改 `ios/project.yml`、`ios/PurePaceTests/**`、`ios/PurePaceUITests/**`、`android/**`、`shared/**`。
- 不做对比度矩阵、动态字体、截图、可及树、真机与模拟器验收（第 3–5 波范围）。

## 实现约束

- 解析口径：`DesignTokens.swift` 结构固定（2 空格 `enum <Group>`、8 空格 `static let`、一行一色对），用 `awk` 按 `enum ... {` 到同级 `}` 切块后逐块断言，避免跨块误判；阶梯值用 `grep -oE '[0-9]+(\.[0-9]+)?'` 提取后逐位比较，不引入浮点工具。
- 注释豁免：扫描跳过整行注释（`///` / `//` / `/*`），修规则精度而非加白名单（`PrimaryActionLayoutPolicy.swift` 文档注释含 `Font.system(size:)` 示例即因此免红）。
- 反例校验形式：`case "$out" in *"<原因串>"*) ;; *) 判失败 ;; esac`；新增断言只可追加，既有 identifier 冻结清单（33 项常量）、`light_count == dark_count`、`spacer_count >= 4`、`mono_count`、阈值常量锁定一行不得删。冻结清单继续作为单一真源常量；新增项以「必需新增 + 计数下限」表达，禁止退回完全等值。demo 入口断言取「先计数再与 0 比较」并输出真实计数。
- 证据口径：只写本机真实输出（命令 / 退出码 / 断言数 / 原因串）；不把「规则已加」当证据。

## 最近交付证明

- workItemId: wi_ws_42e0654f761029c3（2026-11-11，pass）
- 交付：identifier 契约由「33 项完全等值」改为「冻结 33 项只增不改」。新增 `raw_identifier_occurrences`（去重前原始出现）、`count_identifiers`（去重计数）、`identifier_has_readable_label`（命中处 ±4 行内须有 `L10n` 键）、`demo_entry_count`（`Button|ToolbarItem|NavigationLink|Label` + 示例/样例/demo/sample 或 `L10n.demo|sample|fixture*`，整行注释不计）；`validate_design_tokens` 加「冻结清单逐项存在 + 必需新增 3 项 + 计数下限 36 + 空串/新增唯一/新增可读 label」与「demo 入口 = 0」；`run_self_test` 断言数 84 → 91，`check_count` 与 `check_fail_reason` 覆盖改名红 / 删除红 / 新增放行并计数 37 / 空 label 红 / 空串红 / 重复红 / demo 红（含 `#if DEBUG` 块内按钮）；`usage()` 同步。
- 判定：`bash scripts/check-ios-shell.sh --self-test` → `91 项断言，0 项失败` / `self-test OK` / 退出 0；全量 `bash scripts/check-ios-shell.sh` → `30 项断言，0 项失败` / `ios shell OK`，pass 行打印 `identifier: 36（冻结 33 + 新增 3）；demo/示例入口: 0`；`code_gates` 22 门全绿（attempt 001，`lint-ios-shell` 日志见 `.munk/runs/run_ws_7a0feb3ab53c1f7a/code-gates/attempts/001/`）。
- 边界：`.munk/code-gates.json` 零 diff（22 gate id 与 command 未变），未新增脚本文件；源码仅 `RunView.swift` 三行 `accessibilityIdentifier`，既有 33 项、令牌取值与 `purposes` 文案、文案键、`project.yml`、Android、`shared/**` 零 diff。
