# 清理写项 B：文档收口与误导源清除（真机验收改为交付后人工手测）

## 范围

写项 A（`5161e2b`，父 `54caf17`）已删除 agent 级真机验收的代码与门：`scripts/device-run.sh`、`scripts/verify-ios-device-flow.sh`、`ios/PurePaceUITests/DeviceFlowUITests.swift`、`ios/PurePaceUITests/TCCAuthorizationUITests.swift`、`artifacts/device-audit/**`。本项只做「文档与误导源」半：

1. **四文档合一**：把 `docs/device-assertion-matrix.md`、`docs/device-flow-usage.md`、`docs/device-scripts.md`、`docs/device-tcc-automation.md` 合并为一份 `docs/device-manual-acceptance.md`（≤80 行），其余三份删除。
   合并后只保留人手真机手测需要的内容，且**只**保留这五块：
   - 核心闭环一条：开跑 → 记录 → 结束保存 → 历史 → 导出 GPX；
   - 构建身份标注要求：写清「用哪个包 / 哪个 commit 测」；双 sha（候选 zip sha256 + commit）只作记录，不构成脚本校验流程；
   - 人耳判定 ≤2 条：播报是否听清；音乐是否被打断、播完是否恢复；
   - 系统定位权限三步：设置 → 隐私与安全 → 定位服务 → 选「始终允许」；
   - `pending: 待人现场` 语义：未做即 pending，禁写「已验证」。
   删除所有脚本命令、phase 名、manifest 路径、19 项产物清单、harness 步骤；文中不得出现 `device-run` / `verify-ios-device-flow` / `DeviceFlowUITests` / `TCCAuthorizationUITests` 字样。
2. **baseline 三域整域退役**：`.munk/baseline/domains/ios-device-verification/product.md`、`ios-device-run/product.md`、`ios-audio-verification/product.md` 一律改为「已下线」占位（agent 级真机验收已停止，改由人手按 `docs/device-manual-acceptance.md` 手测），不得保留旧步骤（phase 名、脚本名、用例名、证据目录、manifest、19 项清单）。写项 A 已退役 `ios-device-run`，本项只把其措辞对齐到同一占位模板并补人手口径。
3. **`ios-e2e` 断言改写**：`.munk/baseline/domains/ios-e2e/product.md` 的 `ac-device-runnable` 删除，改为等价断言 `ac-simulator-runnable-manual-device-doc`（模拟器可跑 + 真机交人手文档），不再要求「真机可跑」，也不要求 README 提供真机命令。
4. **README**：`README.md` 真机执行命令行（原 :57）改为一句「真机验收已改为交付后由人按 `docs/device-manual-acceptance.md` 手测，agent 不再执行」。
5. **仓内 AGENTS.md**：`AGENTS.md` 真机验收相关表述（原 :64、:66）删除，改为同一口径；不改四节结构、测试金字塔命令与 skill 路由表。
6. **计划文档**：`docs/plans/v1-scope-suggestion.md` 原 :33、:39 的「必须真机」改为「交付后由人手测」；原 :84「没有真机 S2/S3/S4 无法验收」改为同一口径（技术验收点原样保留，只改验收主体与时机）。
7. **release candidates**：`docs/release/candidates/Release-candidate-2c7c4f3.md`、`Release-candidate-7ce3dfe.md` 标题与正文的「真机验收用」改为「历史候选，仅记录构建身份」，构建身份（sha / commit / 证据路径）原样保留。
8. **交叉引用最小修复**：`.munk/baseline/domains/ios-shell/product.md` 的 `ac-legacy-bundle-id-grep-exempt` 豁免清单原引用已删的 `scripts/verify-ios-device-flow.sh` 与 `docs/device-assertion-matrix.md`，删去这两项（技术结论与 `docs/evidence/**` 豁免不变）；`.munk/baseline/domains/ios-app/product.md` 中候选包「供真机硬门绑定」改为「供交付记录标注构建身份」（结论不变）。
9. **其余 `pending: 待人现场` 口径统一**：凡文档把真机验收写成「必须真机 / 由 Product Ops 发起 / agent 会跑」的表述，统一为「真机不做 agent 验收，交付后由人手测」；状态位仍写 `pending: 待人现场`，不改任何技术结论。
10. 只改文档与 baseline 文档；不改脚本、`ios/**`、`.github/**`、`.munk/code-gates.json`。

## 验收

**合并文档**
- ac-manual-doc-created: `docs/device-manual-acceptance.md` 存在且 `wc -l` ≤ 80。
- ac-manual-doc-five-blocks: 该文件同时含五块内容——核心闭环一条（开跑/结束保存/历史/导出 GPX）、构建身份标注（「用哪个包/commit 测」+ 双 sha 仅记录）、人耳判定 ≤2 条（播报是否听清、音乐是否被打断/播完是否恢复）、定位权限三步（设置 → 隐私与安全 → 定位服务 → 始终允许）、`pending: 待人现场` 语义（未做即 pending、禁写「已验证」）。
- ac-manual-doc-no-script-residue: `rg -n "device-run|verify-ios-device-flow|DeviceFlowUITests|TCCAuthorizationUITests|--phase|--music-strategy|manifest|artifacts/device-audit|phase=|19 项" docs/device-manual-acceptance.md` 无输出。
- ac-four-docs-removed: `docs/device-assertion-matrix.md`、`docs/device-flow-usage.md`、`docs/device-scripts.md`、`docs/device-tcc-automation.md` 均 `test ! -e`。

**baseline 退役**
- ac-domains-retired: 三个域文档（`ios-device-verification`、`ios-device-run`、`ios-audio-verification`）各 ≤ 25 行，正文含「已下线」与指向 `docs/device-manual-acceptance.md` 的一句，且三份对 `device-run|verify-ios-device-flow|DeviceFlowUITests|TCCAuthorizationUITests|--phase|artifacts/device-audit|manifest` 零命中。
- ac-e2e-device-assertion-rewritten: `ios-e2e/product.md` 不再有 `ac-device-runnable`；存在 `ac-simulator-runnable-manual-device-doc`，其内容为「模拟器可跑 + 真机按 `docs/device-manual-acceptance.md` 由人手测」，且该文件对 `00008101-001C701E0A68001E`、`真机可执行命令`、`真机可跑` 零命中；该断言无门脚本承载，删除不削弱任何门（`scripts/check-*` 对 `ac-device-runnable` 零命中）。
- ac-baseline-no-must-device: `rg -n "必须真机|必须.*真机" README.md AGENTS.md .munk/baseline` 无输出。

**入口文档与计划**
- ac-readme-device-line-rewritten: `README.md` 对 `00008101-001C701E0A68001E`、`-destination id=` 零命中，且含「交付后由人按 `docs/device-manual-acceptance.md` 手测」一句；`bash scripts/check-baseline.sh` 与 `bash scripts/check-ios-release.sh` 仍退出 0（README 入口 needle `scripts/archive-ios.sh` / `scripts/check-ios-release.sh` 保留）。
- ac-agents-device-lane-removed: `AGENTS.md` 不再把真机列为 agent/CI 验收路径，含「交付后由人按 `docs/device-manual-acceptance.md` 手测」；四节标题、测试金字塔命令与 skill 路由表零改动（`bash scripts/check-baseline.sh` 通过）。
- ac-plans-no-must-device: `docs/plans/v1-scope-suggestion.md` 对「必须真机」零命中，原 :33 / :39 / :84 三条以「交付后由人手测」表述收口，Spotify duck、锁屏 30 min、180 BPM 漂移、iOS 18+ 设备等原技术点与目标不变。
- ac-release-candidates-neutral: 两份 candidate 文档标题与正文不含「真机验收用」，改为「历史候选，仅记录构建身份」；两文件的候选 sha/commit/证据路径仍可检索到。

**收口与门**
- ac-no-device-verified-claim: `git grep -n "真机已验证" -- README.md AGENTS.md docs .munk/baseline` 的每一处命中都处于否定/禁止句式（含「不得出现」「不写」「禁写」等），无任何「真机已验证」肯定宣称；真机项状态一律 `pending: 待人现场`。
- ac-zero-hits-tracked: `git grep -inE "device-run|verify-ios-device-flow|DeviceFlowUITests|TCCAuthorizationUITests"` 仅命中 `.gitignore` 的 `artifacts/device-run/` 豁免行与 `.munk/changes/**` 历史 PRD；`docs/`、`README.md`、`AGENTS.md`、`.munk/baseline/`、`scripts/`、`ios/`、`.github/` 零命中。
- ac-three-gates-green: `bash scripts/check-ios-scripts.sh`、`bash scripts/check-shell-expansion.sh`、`bash scripts/check-ios-shell.sh` 逐条退出 0、stdout 无 `[FAIL]`，回执给断言数与失败数（当前基线 27 / 7 / 26，失败 0）。
- ac-sim-ui-leg-green: `bash scripts/test-ios.sh`（不带 `--unit-only`）退出 0，回执给出 Executed 用例数与失败数（失败必须为 0）。
- ac-scope-guard: `git diff --name-only` 仅含 `docs/**`、`README.md`、`AGENTS.md`、`.munk/baseline/domains/{ios-device-verification,ios-device-run,ios-audio-verification,ios-e2e,ios-shell,ios-app}/product.md` 与 `.munk/changes/<wi>/**`；`ios/**`、`scripts/**`、`.github/**`、`.munk/code-gates.json` 零 diff；`ios/PurePace/Harness/`、`scripts/verify-ios-sim-runtime.sh`、`scripts/verify-ios-ui-e2e.sh` 仍存在。

## 非目标

- 不删 `ios/PurePace/Harness/`、`scripts/verify-ios-sim-runtime.sh`、`scripts/verify-ios-ui-e2e.sh`，不改其断言语义。
- 不改 App 业务源码、不改测试断言强度、不加 `continue-on-error`、不删门腿、不抬超时、不改 `.munk/code-gates.json` 门列表。
- 不为凑「零命中」删掉模拟器/单测共用的断言或文档；遇难判引用保留功能、只改措辞并在回执列出。
- 不改 `.munk/baseline/INDEX.md`（Host 自动生成）、不改历史证据 `docs/evidence/**` 与 `.munk/changes/**`。
- 不手改 main、不推 tag、不动 GitHub Release / TestFlight；不连真机、不宣称真机已通过。
- 不做文档体系重构、不新增其它文档、不顺手优化业务或脚本。

## 实现约束

- **规范来源**：`AGENTS.md` 技术栈冻结 + 测试金字塔（L1 `swift test` / L2 模拟器 XCUITest）；本项为文档项，不新增依赖。
- **合并文档骨架**（≤80 行，可直接落笔）：
  `# PurePace 真机手测手册` → 导读一句（agent 不再执行真机验收）→ `## 1. 核心闭环（一条）` → `## 2. 构建身份标注` → `## 3. 人耳判定（≤2 条）` → `## 4. 系统定位权限（三步）` → `## 5. 状态语义（pending: 待人现场）`。
  构建身份段要求写清「用哪个包 / 哪个 commit 测」，历史候选 `sha256 7258d2e3…b9d8f` / commit `8db1a167` 只作记录示例，不引入脚本校验流程。
- **退役占位模板**（三域同一形状，≤25 行）：
  `# Domain: <name>` + 「**已下线（2026-11-10，清理写项 B）**：agent 级真机验收已停止——脚本、真机 UI 用例、证据目录均已移除，不再恢复。真机验收改由人手按 `docs/device-manual-acceptance.md` 在交付后执行；本域不承载任何 agent 侧门禁或断言。」+ 一段「不得据本域恢复脚本/用例；真机结论一律 `pending: 待人现场`」。
- **命令锚点**：`bash scripts/check-ios-scripts.sh`（27 项）、`bash scripts/check-shell-expansion.sh`（7 项）、`bash scripts/check-ios-shell.sh`（26 项）、`bash scripts/check-baseline.sh`、`bash scripts/check-ios-release.sh`、`bash scripts/test-ios.sh`（全量 UI 腿，模拟器 `iPhone 16` UDID `B3F00298-E08A-41E0-876E-6E8A75C730FD` 已 booted）。
- **零命中口径**：`git grep -inE "device-run|verify-ios-device-flow|DeviceFlowUITests|TCCAuthorizationUITests"` 的唯一合法残留是 `.gitignore` 的 `artifacts/device-run/`（防误入库，保留）与 `.munk/changes/**` 历史 PRD（不改写历史）；其余路径必须零命中。
- **措辞口径**：需求/路径表述写「真机不做 agent 验收，交付后由人手测」；状态位写 `pending: 待人现场`；禁用肯定式「真机已验证」。`ios-e2e` 的 `ac-device-runnable` 无门脚本承载（已核 `scripts/check-*`），改名为 `ac-simulator-runnable-manual-device-doc` 不削弱任何门。
- **顺序建议**：先落合并文档与删三份 → 再退役三域与改 `ios-e2e`/`ios-shell`/`ios-app` 措辞 → 再改 README / AGENTS / plans / candidates → 跑三条门 + `check-baseline` + `check-ios-release` → 最后跑全量模拟器 UI 腿 → 回执逐条给实测输出。
- **停手条件**：若门红源于业务代码或与本项无关，停手回执现状，不越界改代码；若红源于本项文档/引用残留，本项内最小修复到绿。
