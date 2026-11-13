# V1.2 token diff 草案（只写建议值，不应用）

> **已被 V1.2 终版取代（2026-11-13 人拍板）**：本文件的历史建议值（A1 `#E85D04` / A2 `#BE4E05` 等）全部作废，不再作为任何实现或验收依据。当前唯一真源为 `ios/PurePace/Design/DesignTokens.swift` 的 `Colors.palette`（accent `#FF6B00` / danger `#F53A48` 双模式同色），落地口径与实测见 `docs/design/palette-a.md` 与 `docs/evidence/palette-a-contrast.txt`。

> **边界**：本文件只给建议值。`ios/PurePace/Design/DesignTokens.swift` 本轮**零改动**（`git diff` 可证，见 `changed-files.txt`），落地由下一轮实现条目执行。所有数值用与 `ContrastPolicy` 一致的 WCAG 2.x 公式实测：相对亮度 `c ≤ 0.04045 → c/12.92`，否则 `((c+0.055)/1.055)^2.4`，`L = 0.2126R + 0.7152G + 0.0722B`；对比度 `(L1+0.05)/(L2+0.05)`。阈值先定后测：非文本组件 ≥3:1、按钮文字 ≥4.5:1、浅色 accent H ∈ [20°,35°] 且 S ≥60%。

## 1. `accent` / `onAccent`（首选 A1，备选 A2）

| key | 现网 light | 建议 light（A1 首选） | 建议 light（A2 备选） |
|---|---|---|---|
| `accent` | `#B4400B`（H 18.8 / S 88.5 / L 37.5） | **`#E85D04`**（H 23.4 / S 96.6 / L 46.3） | **`#BE4E05`**（H 23.7 / S 94.9 / L 38.2） |
| `onAccent` | `#FFFFFF` | **`#1F1200`**（H 34.8 / S 100 / L 6.1） | **`#FFFFFF`** |

实测（页面底 light `background` = `#FAFAF9`）：

| 组合 | A1 | A2 | 阈值 |
|---|---|---|---|
| accent vs `#FAFAF9` | 3.35:1 | 4.70:1 | ≥3:1 ✓ |
| onAccent vs accent | 5.24:1 | 4.90:1 | ≥4.5:1 ✓ |

- 两者都满足「仍是橙」：H 23.4° / 23.7° 落在 20–35°，S ≥ 94%，不再出现砖红 `#B4400B`。
- `accentSoft` 若跟随 accent 提亮，建议按 accent 的 L 重新取浅底（A1 可试 `#FDEBE0`）；本轮未实测，落地前用同一公式复核。
- **dark 未在本轮实测**（A 组只出浅色）：现网 dark `accent = #FF9A5C`（H 22.8 / S 100 / L 68）、`onAccent = #2A1206` 已是橙且深字，建议保持不动；若随浅色一起收紧 S/L，须按 dark `background` 重算两条阈值，不要照搬浅色结论。

## 2. `warning`：**不必重算**

`warning` light = `#6E5C00`（H 50.2 / S 100 / L 21.6）。与两套候选 accent 的分离度：

| 对 | ΔH | ΔL | ΔS | 结论 |
|---|---|---|---|---|
| A1 `#E85D04` ↔ warning | 26.8° | 24.7 | 3.4 | ΔH ≥ 25° ✓（`DesignTokens.swift:76-77` 的「ΔH≥25° / ΔL≥15 / ΔS≥30 其一」） |
| A2 `#BE4E05` ↔ warning | 26.5° | 16.6 | 5.1 | ΔH ≥ 25° ✓ |

## 3. `danger`：按现有分离规则**可以不动**，A2 下建议加宽余量

`danger` light = `#660D09`（H 2.6 / S 83.8 / L 21.8）。

| 对 | ΔH | ΔL | ΔS | 是否满足现规则（其一即可） |
|---|---|---|---|---|
| A1 ↔ danger | 20.8° | **24.5** | 12.8 | ✓ 靠 ΔL ≥ 15 |
| A2 ↔ danger | 21.1° | **16.4** | 11.1 | ✓ 但仅余 1.4 的 ΔL 余量 |

- 结论：**danger 无需重算**，两套候选都满足公司既定的 H/S/L 分离规则；但 A2 与 danger 明度接近（`#BE4E05` vs `#660D09`，两者对比度仅 2.63:1），在「深橙主色 + 深红破坏性」同屏语境（结束态 → 丢弃 sheet）里容易糊在一起。
- 若采用 A2，建议把 light `danger` 压到 **`#4E0A07`**（H 2.5 / S 83.5 / L 16.7）以拉开明度：vs A2 accent 3.12:1、vs A1 accent 4.38:1、白字 15.3:1、vs `#FAFAF9` 14.7:1。选 A1 时保持 `#660D09` 即可。
- `dangerSoft` / dark `danger = #F53A48` 本轮不动。
- **语义注释需要跟进（实现轮）**：`DesignTokens.swift:99` 现写「danger … 仅出现在确认层文本或描边按钮」，而 C 组两版把丢弃做成了 **danger 实心按钮**（强形态）。落地时要么改这条注释为「确认层实心破坏性主操作 + 文本」，要么在 `ContrastPolicy.pairMatrix` 里补 `danger` 实心底上的 `onDanger` 白字对（白字 vs `#660D09` = 12.91:1 / vs `#4E0A07` = 15.3:1，均达标）。

## 4. 建议的落地顺序

1. 先落 `accent` / `onAccent`（A1），跑 `ContrastPolicy` 快照与既有单测，确认 `pairMatrix` 里 accent 相关对全部通过。
2. 再决定 C 组实心 danger 形态：同步更新 token 语义注释 + `onDanger` 对。
3. `warning` 保持；`danger` 选 A1 时保持，选 A2 时压到 `#4E0A07`。
