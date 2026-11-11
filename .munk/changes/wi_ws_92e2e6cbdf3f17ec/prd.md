# 静态门加固：零字面量与令牌完整性正负两向判红

WorkSet 第 2 波第二子项（`gate-hardening`）。前任 `wi_ws_d2340f794eac5a6c`（`token-core`）已把 `ios/PurePace/Design/DesignTokens.swift` + `ContrastPolicy.swift` 补齐为令牌唯一真源（18 语义色对 + `purposes` 注册表、`Typography` 6 档含 `metricLabel/metricUnit 11` 与 `roleLadder`、`Spacing` 语义项、`Radius`/`Icon`/`Stroke`、`Motion.durationShort 0.2`/`durationState 0.32`/`reducedMotionDuration 0`），但**「全应用统一引用令牌」目前只有部分结构性证据**：`scripts/check-ios-shell.sh` 的 `validate_design_tokens` 只做 section 名存在性、light/dark 聚合计数、以及一个硬编码文件名清单上的字面色值/字体修饰符扫描；新视图文件（如已在仓的 `ios/PurePace/History/RunDetailContent.swift`）只要不在那份清单里就完全逃过扫描；`enum Motion`、`purposes` 键集、逐键 light/dark 成对、`Typography.sizes`/`Spacing.scale` 严格递增、重复键、动效时长字面量都没有门禁断言。

本子项只做一件事：把这套门禁补齐到**「每条规则都有一个真能把它判红的反例」**，并且在本机跑出红/绿两条真实输出写进 digest。**不改视图、不改交互、不改令牌取值、不新增 gate。**

## 范围

1. **扫描范围改为结构性派生**（`validate_design_tokens` 内）：受管 UI 面 = `ios/PurePace/Run/**`、`ios/PurePace/History/**`、`ios/PurePace/Settings/**`、`ios/PurePace/ContentView.swift`、`ios/PurePace/Design/*.swift`（唯一豁免 `Design/DesignTokens.swift` —— 它是字面色值的唯一合法来源）。新增视图文件自动进扫描，不再依赖硬编码文件名清单。`ios/PurePace/Harness/**` 排除，并在脚本注释与 digest 中写明理由（DEBUG-only 测试夹具，不在发布 UI 面，且它含 `Color.clear` 这类结构性常量）。
2. **字面色值零容忍**（两向）：受管面内出现 `Color(`、`Color.<Name>`、`UIColor`、`#colorLiteral`、`SRGB(hex: 0x…)`、`0x[0-9A-Fa-f]{6}`、`.foregroundStyle(.<Name>)`、`.background(.<Name>)` 任一即判红；正例（现存视图只写 `.font(DesignTokens.Typography.…)` / `DesignTokens.Colors.…`）必须仍为绿。
3. **零散字体修饰符零容忍**（两向）：受管面内出现 `.font(.`（含 `.font(.system(size:`、`.font(.custom(`）、裸 `Font.system(`/`Font.custom(` 值、`.fontWeight(`、`.fontDesign(`、`.lineSpacing(<数字>)` 任一即判红；`.font(DesignTokens.Typography.<role>)` 必须为绿。
4. **动效时长字面量零容忍**（两向）：受管面内出现 `.animation(`、`withAnimation(`、`Animation.`、`.transition(` 且同一行不含 `DesignTokens.Motion.` 即判红；任何 `duration: <数字字面量>` / `duration: 0.` 即判红（`duration: record.activeDuration` 这类表达式必须为绿——既有仓内全是表达式，必须零误红）。
5. **令牌分组完整性 + 无重复/缺项**：必需分组/常量逐个存在性断言（`enum Colors`+`palette`+`purposes`、`enum Typography`+`sizes`、`enum Spacing`+`scale`、`enum Radius`+`scale`、`enum Stroke`+`hairline`、`enum Icon`+`scale`、`enum Motion`+`durationShort`/`durationState`/`reducedMotionDuration`、`enum Appearance`+`supportsDarkMode = true`、`minTapTarget: CGFloat = 44`）；每个 `enum <Group>` 在 token 真源里只允许出现一次（重复分组判红）；`palette` 键数 = 18 且每键恰好一条 `"<key>": ColorPair(light: SRGB(hex: …), dark: SRGB(hex: …))`，缺 light、缺 dark、light 与 dark 相等、同键重复定义均判红；`purposes` 键集必须与 `palette` 键集完全相等（缺键/多键/空用途/用途复读键名判红）；`static let <key> = color("<key>")` 数量与 `palette` 键数一致。
6. **阶梯单调与冻结值**：`Typography.sizes` 严格递增且恰为 `[11,12,15,20,34,56]`；`Spacing.scale` 严格递增且恰为 `[4,8,12,16,24,32]`；`Radius.scale == [12,16,20]`；`Icon.scale == [16,20,24]`；`Stroke.hairline == 1`；`Motion` 满足 `0 < durationShort(0.2) < durationState(0.32)`、`reducedMotionDuration == 0`；`minTapTarget == 44`。任一档位被改、被删、被重复或次序被打乱判红。
7. **可及 identifier 集合冻结不退化**：既有 33 项集合等值断言与「少一项 / 改名 / 多一项」两条反例全部保留，断言不可弱化。
8. **`--self-test` 两向自检扩写**：上述每条新规则都要有正例一绿 + 反例一红；每条反例必须**断言判红原因串**（例如必须含「字面色值」「零散字体修饰符」「动效时长字面量」「缺枚举 Motion」「色对缺 dark」「令牌重复」「字号阶梯未严格递增」「可及 identifier」字样），只判「非空」不算通过——否则反例因别的原因判红会掩盖规则失效。自检仍在 `mktemp -d` 内构造夹具，不写仓库。
9. **红/绿真实输出入 digest**：digest 记录本次门禁的绿跑与红跑原始输出片段（含命令、退出码、`N 项断言，0 项失败` / 失败原因串），并记当前 `--self-test` 基线断言数 52 与本子项收口断言数（必须 > 52）。

## 验收

- ac-scan-scope-derived: `validate_design_tokens` 的受管文件集合由目录/通配派生（含 `Run/**`、`History/**`、`Settings/**`、`ContentView.swift`、`Design/*.swift` 去 token 真源），不再依赖硬编码视图文件名列表；自检反例「在受管目录新增一个此前不存在的视图文件并塞入 `Color(red: 0.1, green: 0.2, blue: 0.3)`」必须判红且原因串含「字面色值」；现存 `ios/PurePace/History/RunDetailContent.swift` 属于受管面（在自检里被断言覆盖）。
- ac-no-literal-colors: 受管面内 `Color(`、`Color.<Name>`、`UIColor`、`#colorLiteral`、`SRGB(hex: 0x…)`、裸 `0xXXXXXX`、`.foregroundStyle(.<Name>)` 任一命中即判红；自检对 `Color(red: 0.1, green: 0.2, blue: 0.3)`、`Color.white`、`#colorLiteral(...)`、`SRGB(hex: 0xFFFFFF)`、`.foregroundStyle(.red)` 至少各一条反例判红且原因串含「字面色值」；正例（真实源码复制）为零、判绿。
- ac-no-stray-font: 受管面内 `.font(.`、裸 `Font.system(`/`Font.custom(`、`.fontWeight(`、`.fontDesign(`、`.lineSpacing(<数字>)` 任一命中即判红；自检反例 `.font(.system(size: 20))` 与裸 `Font.system(size: 18, weight: .bold)` 判红且原因串含「零散字体修饰符」；反例 `.font(DesignTokens.Typography.body)` 判绿（证明规则不误红合法引用）。
- ac-no-motion-literals: 受管面内 `.animation(`/`withAnimation(`/`Animation.`/`.transition(` 所在行若不含 `DesignTokens.Motion.` 判红；`duration: <数字>`、`duration: 0.` 判红；自检反例 `.animation(.easeInOut(duration: 0.3), value: flag)` 与 `withAnimation(.linear(duration: 0.25)) { }` 判红且原因串含「动效时长字面量」，正例 `.animation(.easeInOut(duration: DesignTokens.Motion.durationShort), value: flag)` 判绿，且真实视图中 `duration: record.activeDuration` / `duration: activeDuration / 3` 被判绿（零误红）。
- ac-token-groups-complete: 必需分组与常量（`Colors.palette`/`Colors.purposes`/`Typography.sizes`/`Spacing.scale`/`Radius.scale`/`Stroke.hairline`/`Icon.scale`/`Motion.durationShort`/`Motion.durationState`/`Motion.reducedMotionDuration`/`Appearance.supportsDarkMode = true`/`minTapTarget: CGFloat = 44`）逐个存在性断言；自检反例分别删除 `enum Motion` 与删除 `static let reducedMotionDuration`，两者判红且原因串分别含「Motion」「reducedMotionDuration」。
- ac-token-groups-unique: `/^    enum <Group>/` 每个分组在 token 真源中只出现一次；同一 `palette` 键定义两次或同一分组块重复出现判红；自检反例把 `enum Motion` 整块追加一次，判红且原因串含「重复」。
- ac-color-pairs-complete: `palette` 键数恰为 18、每键恰有一条 `ColorPair(light: SRGB(hex: 0x…), dark: SRGB(hex: 0x…))`、light 与 dark 不相等；自检反例（删掉某键的 `dark: SRGB(hex: 0x…)`）判红且原因串含「色对缺 dark」；`purposes` 键集与 `palette` 键集等值，删一条 purpose 判红且原因串含「用途」。
- ac-scale-monotonic-frozen: `Typography.sizes` 严格递增且等于 `[11, 12, 15, 20, 34, 56]`，`Spacing.scale` 等于 `[4, 8, 12, 16, 24, 32]`，`Radius.scale == [12, 16, 20]`，`Icon.scale == [16, 20, 24]`，`Motion.durationShort == 0.2`、`durationState == 0.32`、`0 < durationShort < durationState`、`reducedMotionDuration == 0`；自检反例把 `Typography.sizes` 改成含 `13` 破坏严格递增、把 `Spacing.scale` 改成一档重复值，均判红且原因串含「阶梯」/「档位」。
- ac-identifier-set-frozen: 既有 33 项 accessibility identifier 集合等值断言与「少一项 / 改名 / 追加一项」三条反例全部保留且仍判红；自检断言总数不减少。
- ac-selftest-red-green: `bash scripts/check-ios-shell.sh --self-test` 退出 0、断言数 > 52（基线），每条新规则至少有 1 条反例与 1 条正例，且反例校验原因串；自检在 `mktemp -d` 夹具内完成，运行前后 `git status --porcelain` 不因自检新增改动。
- ac-digest-red-green-evidence: `.munk/changes/<workItemId>/digest.md` 记录：全量 `bash scripts/check-ios-shell.sh` 绿跑输出（含 `N 项断言，0 项失败` 与退出码 0）、`--self-test` 输出（断言数与 0 失败）、以及至少一次真实红跑（受管面内临时注入字面色值/动效字面量后门禁非零退出并打印原因串，随后还原）的原始片段与还原证据；digest 不得只写「已加固」之类结论。
- ac-no-view-interaction-change: 相对本子项起始提交，`ios/PurePace/Run/**`、`ios/PurePace/History/**`、`ios/PurePace/Settings/**`、`ios/PurePace/ContentView.swift`、`ios/PurePace/Resources/**`、`ios/PurePace/Design/**`、`ios/project.yml`、`ios/PurePaceTests/**`、`ios/PurePaceUITests/**`、`android/**`、`shared/**` 的 `git diff --name-only` 均为空；若门禁确实暴露既有违规，只允许把字面量等价替换为既有 token 引用（视觉零变化），且必须在 digest 逐条列出文件名/行号/替换前后；禁止借此改字号、颜色值、间距、文案与交互。
- ac-gate-list-unchanged: `.munk/code-gates.json` 零 diff（22 个 gate id 与 `command` 全部不变），不新增 gate id、不改 `lint-ios-shell` 的 command；不新增脚本文件，全部改动落在 `scripts/check-ios-shell.sh`；`bash -n scripts/check-ios-shell.sh` 退出 0，`--help` 文案同步更新且退出 0。
- ac-gates-green: `lint-ios-shell`（含 `--self-test`）、`lint`、`lint-ios-scripts`、`test-ios`（`--unit-only`）、`build-ios`、`test-ios-core`、`test-ios-run-core`、`lint-baseline`、`test` 全部退出 0；不靠放宽既有断言补绿。
- ac-budget-receipt: `digest.md` 首节写开工时刻、预算时长与期望收口绝对时刻（建议 90 分钟：门禁规则 ≤40、两向自检 ≤30、红绿证据与回归 ≤20）；预算耗尽仍未完成时，落盘已完成改动并在该节写「超时停手」+ 未完成项，不得静默延长会话或删断言。
- ac-token-freeze: 本子项不改变任何令牌取值与语义（`design-token-freeze` checkpoint）：`palette` 18 组 hex、`purposes` 文案、`Typography`/`Spacing`/`Radius`/`Icon`/`Stroke`/`Motion` 全部数值相对起始提交零 diff，仅由门禁读取。

## 非目标

- 不新增 gate id、不改 `.munk/code-gates.json` 的门列表与 `command`、不改 CI workflow、不新建脚本文件（允许拆同文件内的函数）。
- 不改任何视图、交互行为、文案、accessibility identifier、页面结构、状态机、动画接线（本子项只让门禁能判红，不接 `.animation`）。
- 不改令牌取值、色值、字号、间距、圆角、动效常量与 `purposes` 文案（checkpoint `design-token-freeze`）。
- 不改 `ios/PurePaceTests/**`、`ios/PurePaceUITests/**`、`ios/project.yml`、`android/**`、`shared/**`。
- 不做对比度矩阵、动态字体、截图、可及树、真机与模拟器验收（第 3–5 波范围）。
- 不写 `tech.md`；不排后续波次。

## 实现约束

- **改动落点唯一**：`scripts/check-ios-shell.sh` —— 扩写 `validate_design_tokens`（第 409 行起）与 `run_self_test`（第 726 行起），同步 `usage()` 文案；复用既有 `pass`/`fail`/`check_ok`/`check_fail` 与 `problems` 累加风格，不重构其余 14 个 validate 函数。
- **兼容 macOS `/bin/bash` 3.2**：禁止 `declare -A`、`mapfile`、`${var,,}`、`[[ ... =~ ]]` 扩展用法；只用当前脚本已在用的 `grep -E`/`sed -E`/`awk`/`sort -u`/`tr`/`printf`。`set -euo pipefail` 下所有可能空匹配的 `grep` 必须 `|| true`。
- **解析口径**：`DesignTokens.swift` 结构固定（2 空格缩进 `enum <Group>`、8 空格 `static let`、`"<key>": ColorPair(light: SRGB(hex: 0x…), dark: SRGB(hex: 0x…))` 一行一色），用 `awk` 按 `enum ... {` 到同级 `}` 切块后逐块断言，避免跨块误判；阶梯值用 `grep -oE '[0-9]+(\\.[0-9]+)?'` 提取后逐位比较，不引入浮点工具。
- **免红白名单最小化**：仅两处结构性豁免，且必须写进脚本注释与 digest 理由 —— ①`Design/DesignTokens.swift`（字面色值唯一合法来源，其内部靠 `palette`/`purposes`/阶梯断言约束）；②`ios/PurePace/Harness/**`（DEBUG-only 测试夹具，不在发布 UI 面，含 `Color.clear`）。禁止为了变绿再新增白名单条目；若某规则在真实源码上误红，先修规则精度，不加白名单。
- **自检夹具**：沿用现有「复制真实源码到 `mktemp -d` 再单点变更 + 调 `validate_design_tokens <root>`」模式；每条反例断言 `case "$out" in *"<原因串>"*) ;; *) 判失败 ;; esac` 形式的原因串匹配；正例必须是真实源码副本（不得手写简化正例），以防规则在真实文件上误红。
- **红跑证据可复现**：建议用 `mktemp -d` 复制受管文件 → 注入一行字面量/动效字面量 → 对副本跑 `validate_design_tokens` 显示原因串 → 删除副本；若改用真实树临时注入，必须 `git checkout --` 还原并在 digest 贴 `git status --porcelain` 为空的证据。
- **既有断言不弱化**：33 项 identifier 等值、`light_count == dark_count`、`spacer_count >= 4`、`mono_count`、阈值常量锁定等既有断言一行不得删；新增断言只可追加。收口断言数基线：`--self-test` 当前 52 项。
- **预算**：开工即写预算与期望收口绝对时刻；超时按 `ac-budget-receipt` 落回执。
- 本子项为 WorkSet 子项，不开 Design / Architect / PM 阶段追加工作；第 3 波核心屏重建将消费本子项的门禁结论。
