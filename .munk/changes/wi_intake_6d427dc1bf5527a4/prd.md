# 更正 AX5 digest 的整包腿状态表述为明确「未跑齐」

## 范围

只改 `docs/evidence/ax5-order-independence/digest.md` 的文字表述：

1. 第 5 节「腿状态」中整包条目现写作「见 `ax5-pack-standard.log` 与回执（跑不齐则如实记未跑）」，是条件句、等于省略事实。改为无条件事实陈述，三要素齐全：
   - 整包腿未跑齐；
   - 事实依据是 `ax5-pack-standard.log` 被截断，末行停在后续用例 `t = 7.67s`（`Waiting 10.0s for NavigationBar (First Match) to exist`），无整包结论；
   - 已绿范围只到单用例 `testEvidenceAx5Layout` exit 0 与两条反例/正向对照（`ax5-counterexamples.log`）。
2. 文件顶部「结论/摘要」处当前没有整包相关描述；若有则一并改为同口径，且全文不得出现「整包绿 / 整包通过」字样。

不改任何 Swift 源码、测试源码、脚本、CI 配置、identifier、阈值；不重跑 AX5 整包腿或任何 UI 用例（按公司裁决用现有 log 记录事实）；不顺手修 digest 中已记录的 2 条未修项。

## 验收标准

- ac-single-file: `git diff --name-only` 仅列出 `docs/evidence/ax5-order-independence/digest.md` 一个文件。
- ac-pack-line-explicit: 第 5 节「腿状态」的整包条目为无条件事实表述，同时含「整包腿未跑齐」、`ax5-pack-standard.log` 被截断且末行停在后续用例 `t = 7.67s` 无整包结论、已绿范围仅到单用例 `testEvidenceAx5Layout` exit 0 与两条反例/正向对照三要素；原条件句「跑不齐则如实记未跑」不再出现。
- ac-no-green-wording: `grep -n "整包" docs/evidence/ax5-order-independence/digest.md` 输出中含「未跑齐」，且全文不出现「整包绿」「整包通过」字样。
- ac-summary-consistent: 顶部标题/摘要区若出现整包相关描述，其口径与第 5 节一致（明确未跑齐、不写绿）；若原本无整包描述，则保持不新增整包结论。
- ac-no-scope-creep: digest 中第 5 节「未修清单」的 2 条未修项、其他章节文字与事实、以及全部源码/测试/脚本/CI/identifier/阈值均未改动；未新增长跑结论或补跑记录。
- ac-gates-green: `.munk/code-gates.json` 的 code_gates 照常全绿（至少 `bash scripts/check-baseline.sh` 通过，其他门禁不受文档改动影响）。

## 非目标

- 不重跑 AX5 整包腿或任何 UI 用例，不产出新 log。
- 不修复 digest 中已记录的 2 条未修项（标准字号档 03-run-finished 相交、05-history-detail 第二页导出）。
- 不调整任何测试断言、identifier、阈值、布局策略或 CI workflow。
- 不改写 digest 其他章节的既有结论与数据。

## 实现约束

- 单文件 Markdown 文本改动；diff 必须仅 1 个文件。
- 事实来源冻结为现有产物：`ax5-pack-standard.log` 共 1708 行、末行 `t = 7.67s Waiting 10.0s for NavigationBar (First Match) to exist`、无整包结论行；`ax5-single-green.log` 对应单用例 exit 0；`ax5-counterexamples.log` 对应两条反例 + 正向对照。
- 建议替换文本（保留原有标识符与日志路径，只把条件句改为事实陈述）：
  `- 同容器整包（-only-testing:PurePaceUITests，标准字号档 large，与 ios.yml 权威腿同口径）：整包腿未跑齐。事实依据：ax5-pack-standard.log 被截断，末行停在后续用例 t = 7.67s（Waiting 10.0s for NavigationBar (First Match) to exist），无整包结论。已绿范围只到单用例 testEvidenceAx5Layout exit 0 与两条反例/正向对照（ax5-counterexamples.log）。`
- 预算 ≤2M token、≤30 分钟；到点未闭合则交未闭合回执，不得扩大改动面。
