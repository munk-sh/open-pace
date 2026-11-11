# Digest：静态门加固（零字面量与令牌完整性正负两向判红）

## 0. 预算与收口时刻（ac-budget-receipt）

- 开工时刻：2026-11-11 11:46:52 CST
- 预算时长：90 分钟（门禁规则 ≤40 / 两向自检 ≤30 / 红绿证据与回归 ≤20）
- 期望收口绝对时刻：2026-11-11 13:16:52 CST
- 实际收口时刻：2026-11-11 12:20 CST（未超时，未延长会话）

## 1. 改动落点（唯一）

- `scripts/check-ios-shell.sh`（唯一被修改文件）：
  - 新增同文件内 helper：`token_enum_block` / `token_array_block` / `token_number_value` /
    `token_scale_elements` / `token_resolved_values` / `token_scale_order_problem` / `non_comment_hits`。
  - 扩写 `validate_design_tokens`：受管面结构性派生扫描、零字面色值、零散字体修饰符、
    零动效时长字面量、令牌分组存在性/唯一性、18 色对成对、purposes 键集、阶梯单调冻结、Motion 常量。
  - 扩写 `run_self_test`：新增 `check_fail_reason`（反例必须命中预期原因串）+ 32 条新断言（52 → 84）。
  - 同步 `usage()` 文案。
- 未新增脚本文件；未新增强制 gate；`.munk/code-gates.json` 零 diff（22 个 gate id 与 command 未变），
  `git diff --stat -- .munk/code-gates.json` 为空。
- `bash -n scripts/check-ios-shell.sh` → 退出 0；`bash scripts/check-ios-shell.sh --help` → 退出 0。

## 2. 受管面与豁免理由

受管 UI 面 = `ios/PurePace/Run/**`、`ios/PurePace/History/**`、`ios/PurePace/Settings/**`、
`ios/PurePace/ContentView.swift`、`ios/PurePace/Design/*.swift`，由 `find` 目录派生 + 去 token 真源，
不再依赖硬编码视图文件名清单（新增视图文件自动进扫描；自检中新增 `Run/NewlyAddedScreen.swift` 反例已判红）。

仅两处结构性豁免，写进脚本注释：

1. `ios/PurePace/Design/DesignTokens.swift`：字面色值的唯一合法来源（`SRGB(hex:)` / `Color(uiColor:)`），
   其内部由 `palette` 18 键、`purposes` 键集、阶梯冻结与 Motion 常量断言约束。
2. `ios/PurePace/Harness/**`：DEBUG-only 测试夹具，不在发布 UI 面，且含 `Color.clear` 这类结构性常量。

未为变绿新增任何白名单；`Design/PrimaryActionLayoutPolicy.swift` 的一行文档注释含 `Font.system(size:)`
示例，改为扫描时跳过整行注释（`///` / `//` / `/*`），修规则精度而非加白名单。

## 3. 绿跑原始输出（全量门禁）

命令与退出码：

```bash
$ bash scripts/check-ios-shell.sh
exit=0
```

原始片段：

```text
[PASS] ac-design-tokens (单一 token 真源 + 三屏引用 + 可读标签)
...
[PASS] ac-release-deterministic-default-real (self-test)
[PASS] ac-scripts-and-gates (真实构建/测试脚本 + code-gates)

29 项断言，0 项失败
ios shell OK
```

同批回归（真实执行）：

```text
$ bash scripts/check-ios-scripts.sh
exit=0
27 项断言，0 项失败
ios scripts OK

$ bash scripts/check-baseline.sh
exit=0
11 项断言，0 项失败
baseline OK (VERSION=0.1.0)

$ bash scripts/check-shell-expansion.sh
exit=0
7 项断言，0 项失败
check-shell-expansion OK
```

## 4. `--self-test` 原始输出

```bash
$ bash scripts/check-ios-shell.sh --self-test
exit=0
```

```text
[PASS] self-test (包/import/定位配置/Harness 清单/Settings 开关/设计 token/本地化 正负反例)

84 项断言，0 项失败
self-test OK
```

- 基线断言数（本子项开工前实测）：52（`52 项断言，0 项失败`）。
- 本子项收口断言数：84（> 52）。

## 5. 真实红跑（受管面注入后判红，随后还原）

注入（真实树，`ios/PurePace/History/RunDetailContent.swift` 追加两行）：

```swift
private let injectedColor = Color.white
private let injectedMotion = EmptyView().animation(.easeInOut(duration: 0.3), value: false)
```

原始输出：

```text
$ bash scripts/check-ios-shell.sh
exit=1
[FAIL] ac-design-tokens:  ios/PurePace/History/RunDetailContent.swift 含字面色值: 47:private let injectedColor = Color.white; ios/PurePace/History/RunDetailContent.swift 动效时长字面量（未走 DesignTokens.Motion）: 48:private let injectedMotion = EmptyView().animation(.easeInOut(duration: 0.3), value: false); ios/PurePace/History/RunDetailContent.swift 含动效时长字面量: 48:private let injectedMotion = EmptyView().animation(.easeInOut(duration: 0.3), value: false);
29 项断言，1 项失败
```

还原：`git checkout -- ios/PurePace/History/RunDetailContent.swift`，随后：

```text
$ git status --porcelain
 M scripts/check-ios-shell.sh
?? .munk/changes/wi_ws_92e2e6cbdf3f17ec/
```

即 ios 源码零残留（仅脚本改动 + 本 change pack 未跟踪目录）。

## 6. 规则与两向自检覆盖

| 规则 | 反例（断言原因串） | 正例 |
|---|---|---|
| 受管面目录派生（新增文件自动入扫描） | 新增 `Run/NewlyAddedScreen.swift` 塞 `Color(red:…)` → 判红「字面色值」 | 真实源码副本判绿 |
| 现存 `History/RunDetailContent.swift` 属受管面 | 该文件追加 `Color.white` → 判红「字面色值」 | 真实副本判绿 |
| 零字面色值 | `Color.white`、`#colorLiteral(...)`、`SRGB(hex: 0xFFFFFF)`、`.foregroundStyle(.red)`、`.background(.blue)`、`Color(red:…)` → 均判红「字面色值」 | 真实三屏 + Design 组件判绿 |
| 零散字体修饰符 | `.font(.system(size: 20))`、裸 `Font.system(size: 18, weight: .bold)` → 判红「零散字体修饰符」 | `.font(DesignTokens.Typography.body)` 判绿 |
| 动效时长字面量 | `.animation(.easeInOut(duration: 0.3), value:)`、`withAnimation(.linear(duration: 0.25))`、`Ease(duration: -0.3)` → 判红「动效时长字面量」；行尾 `// DesignTokens.Motion.…` 伪豁免 → 判红 | `.animation(… duration: DesignTokens.Motion.durationShort …)` 判绿；真实 `duration: record.activeDuration` / `activeDuration / 3` 零误红 |
| 分组完整性 | 删 `enum Motion` → 判红含「Motion」；删 `static let reducedMotionDuration` → 判红含「reducedMotionDuration」 | 真实 token 真源判绿 |
| 分组唯一 | 追加整块 `enum Motion` → 判红含「重复」 | 真实 token 真源判绿 |
| 色对完整 | 删某键 `dark:` → 判红「色对缺 dark」；light 与 dark 同值（含键名与冒号间带空格的写法）→ 判红「色对」；`surfaceMuted` 键名改成 `surface` 重复 → 判红「重复」；`static let … = color(…)` 全缺 → 判红「语义色 static let 与调色板」且不静默中止 | 18 键成对判绿 |
| purposes 键集 | 删一条 `"surface": "卡片面与底部控制区"` → 判红「用途」 | 18 键等值判绿 |
| 阶梯单调冻结 | `captionSize 12→15` → 判红「阶梯」；`sizes` 元素乱序 → 判红「未严格递增」；`sm 12→8` → 判红「档位」；`Radius.card 16→18` / `Icon.row 20→18` / `Stroke.hairline 1→2` → 判红「档位」 | `[11,12,15,20,34,56]` / `[4,8,12,16,24,32]` / `[12,16,20]` / `[16,20,24]` / `1` 判绿 |
| Motion 常量 | `durationShort 0.2→0.25` → 判红「Motion」；`minTapTarget 44→43` → 判红「44」 | `0 < 0.2 < 0.32`、`reducedMotionDuration == 0` 判绿 |
| 33 项 identifier 冻结 | 既有「改名 / 追加一项」两条反例保留，新增「删掉 `accessibilityIdentifier("run.saved")`」少一项反例 → 判红「可及 identifier」（断言不弱化） | 真实源码副本判绿 |

## 7. 令牌与视图零改动证据

- `git diff --name-only` → 仅 `scripts/check-ios-shell.sh`。
- `ios/PurePace/Run/**`、`History/**`、`Settings/**`、`ContentView.swift`、`Resources/**`、
  `Design/**`、`ios/project.yml`、`ios/PurePaceTests/**`、`ios/PurePaceUITests/**`、
  `android/**`、`shared/**` 均无 diff；令牌取值与 `purposes` 文案零 diff（`design-token-freeze`）。
- 门禁未暴露既有违规，未发生「字面量等价替换 token」改动。
