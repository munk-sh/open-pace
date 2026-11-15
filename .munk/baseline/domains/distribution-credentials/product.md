# Domain: distribution-credentials

## 范围

- 分发凭据的唯一录入口径：本机唯一落点 `~/.purepace-asc/asc.env`（`chmod 600`，四项 `ASC_KEY_PATH` / `ASC_KEY_ID` / `ASC_ISSUER_ID` / `TESTFLIGHT_TESTER_EMAIL`），`.p8` 私钥同放 `~/.purepace-asc/`，目录与文件都在仓库之外。
- 承载 `docs/human-gate-distribution.md`（人闸卡）、`docs/release/testflight-runbook.md`（前置与执行第 2 步）、`docs/release/stage4-prereqs.md`（复核方法段）的凭据段落：录入 → 自检 → 加载三段同口径；三份活文档的过时落点由 `scripts/check-ios-release.sh` 判红。
- 口径写进 `AGENTS.md` 目录约定一行（唯一落点 `~/.purepace-asc/asc.env`，`docs/**` 活文档必须引用，过时落点由 `check-ios-release.sh` 判红）；`.munk/changes/**` / `.munk/baseline/**` 的历史记录不改。
- 自检只判存在性、不打印值；分发任务首步与手册一致：先 `. ~/.purepace-asc/asc.env` 再校验四项，任一缺失即停手。
- 静态门落点 `scripts/check-ios-release.sh` 的 `human_gate_problems` / `asc_env_problems` / `stage4_prereqs_problems`：既有 needle 全保留，新口径 needle 补齐，旧口径（`~/keys/`、把 `export ASC_KEY_PATH=...` 当录入主路径、`~/.munk-release/secrets.env`）判红。
- 只改文档与这一条断言及其反例；`archive-ios.sh` / `upload-ios.sh` / `testflight-tester.sh` 的行为与契约不动。

## 验收

- ac-asc-env-single-source: 两份文档均含 `~/.purepace-asc/asc.env` 与 `chmod 600`，四项变量齐全；正文不再把 `export ASC_KEY_PATH=...` 作为录入主路径，`~/keys/` 零命中。
- ac-self-check-no-print: 自检段（`chmod 600 ~/.purepace-asc/asc.env`、`test -f`、子 shell `set -a; . <该文件>; set +a` 后四项 `test -n`）只做存在性判断，不 `echo` / `printf` 任何变量值、不含 `set -x`。
- ac-human-gate-needles: `grep -Fq asc.env`、`grep -Fq 'chmod 600'`、`grep -Fq purepace-asc` 均命中，既有 needle（`ASC_KEY_PATH` / `ASC_KEY_ID` / `ASC_ISSUER_ID` / `TESTFLIGHT_TESTER_EMAIL` / `.p8` / `仓库之外` / `仓库` / `日志` / `CI`）全部保留；旧口径 `~/keys/`、`export ASC_KEY_PATH=` 命中即判红。
- ac-legacy-shape-red: 反例自检——`mktemp -d` 沙箱内把样本的 `~/.purepace-asc/asc.env` 换成 `~/keys/AuthKey.p8` 后 `human_gate_problems` 输出非空；反例只改沙箱样本、不改生产脚本，既有 UUID 反例仍绿。
- ac-manual-runbook-aligned: 手册与 runbook 同口径（先 source 再校验、缺失停手）；保留「ASC App 记录 / 签名 / 测试者 Apple ID」三项人动作指向，隐私政策只写「ASC App 信息填 https://munk.sh/privacy」。
- ac-gates-green: `bash scripts/check-ios-release.sh` 与 `bash scripts/check-baseline.sh` 退出 0，其它门腿不弱化、不删、不 `|| true` 绕过。
- ac-no-credential-leak: 两份文档不含 `/Users/`、`/home/`、`set -x`、`BEGIN PRIVATE KEY` 与真实 UUID。
- ac-stage4-review-asc-env: `docs/release/stage4-prereqs.md` 复核段含 `~/.purepace-asc/asc.env`、四项变量齐全、不打印变量值；`git grep -n 'munk-release/secrets.env' origin/main -- docs/` 零命中。
- ac-stage4-gate-and-counterexample: `stage4_prereqs_problems`（复用 `asc_env_problems` + 过时落点判红）对 stage4 文档退出 0；沙箱反例把 `~/.purepace-asc/asc.env` 换回 `~/.munk-release/secrets.env` 后必须非空，且不依赖改生产代码即可判红。
- ac-repo-agents-line: 仓内 `AGENTS.md` 含「`~/.purepace-asc/asc.env` 唯一落点」约定（≤2 行），既有标题与条目未被改写。

## 非目标

- 不改 `scripts/archive-ios.sh` / `scripts/upload-ios.sh` / `scripts/testflight-tester.sh` 的行为与契约。
- 不改分发任务 instruction、不重开人闸卡、不执行真实归档 / 上传 / 测试者写入。
- 不改 `.github/workflows/**`、`VERSION`、bundle id / Team / 签名主干。
- 不重改 `docs/human-gate-distribution.md` 与 `docs/release/testflight-runbook.md`（上一单已对齐），不改 `stage4-prereqs.md` 里其它产品（如 `com.chaxiu.purepace`）的历史条目。
- 不改 `.munk/changes/**`、`.munk/baseline/**` 的历史记录文本。
- 不扩 UI、功能面或验证基建。

## 实现约束

- 文档只写占位符与 `$HOME` / `~` 相对路径，不写本机绝对路径与任何真实凭据值。
- 断言以函数复用（`asc_env_problems` 同时供 `human_gate_problems` 与 runbook 检查调用），不复制 needle 列表。
- 新断言必须带「构造错误输入 → 必须判红」的反例，且只改沙箱样本、不改生产脚本才红。
- 旧口径检查用 `grep -Fq` 字面量匹配，避免正则转义差异导致漏判。
- 新增活文档只加「该文档必须是新口径」的守卫，沙箱反例用 `sed` 只改样本（不改生产脚本、不改源文档）。

## 最近交付证明

- workItemId: wi_intake_9f416f32cd756c56 / at: 2026-11-16T00:00:00+08:00 / status: pass
- 交付：`docs/release/stage4-prereqs.md` 复核段把过时落点 `~/.munk-release/secrets.env` 换为 `chmod 600 ~/.purepace-asc/asc.env` 后 `set -a; . <该文件>; set +a` 再逐项判存在性（含 `TESTFLIGHT_TESTER_EMAIL`），保留「只读自检 / 建 App 记录 / 回读校验」与占位符写法；`scripts/check-ios-release.sh` 新增 `stage4_prereqs_problems`（复用 `asc_env_problems` + 过时落点判红）与沙箱反例自检；`AGENTS.md` 补一条唯一落点约定。
- 验证：`bash scripts/check-ios-release.sh` / `bash scripts/check-baseline.sh` 退出 0；`git grep 'munk-release/secrets.env' -- docs/ AGENTS.md` 零命中；反例（asc.env → 过时落点）判红；code_gates 23 门全绿（attempt 001）。
- 边界与未做：未改人闸卡与 runbook（上一单已对齐）、未改分发脚本行为与 workflow / `VERSION` / bundle id，未执行真实归档 / 上传；无发布态声明。
