# 分发手册与分发任务凭据口径对齐（asc.env 单一口径）

## 范围

- 仓内 `docs/human-gate-distribution.md` 与 `docs/release/testflight-runbook.md` 的凭据录入口径改为唯一落点 `~/.purepace-asc/asc.env`：`chmod 600`，四项变量 `ASC_KEY_PATH` / `ASC_KEY_ID` / `ASC_ISSUER_ID` / `TESTFLIGHT_TESTER_EMAIL`，不入仓、不贴聊天、不打印值。
- `.p8` 一律落 `~/.purepace-asc/`，删除 `~/keys/` 示例与「export 到当前 shell 即算录入」的表述。
- 给出可复制自检命令（只判存在性，不打印值）：`chmod 600 ~/.purepace-asc/asc.env`、`test -f ~/.purepace-asc/asc.env`、以及 `( set -a; . ~/.purepace-asc/asc.env; set +a; test -f "$ASC_KEY_PATH" && test -n "$ASC_KEY_ID" && test -n "$ASC_ISSUER_ID" && test -n "$TESTFLIGHT_TESTER_EMAIL" && echo asc-env-ok )`。
- `scripts/check-ios-release.sh` 的 `ac-human-gate-doc` needle 集合补 `asc.env`、`chmod 600`、`purepace-asc`，并新增「旧口径必须判红」的反例自检。
- 手册需与分发任务首个前置步一致：先 `. ~/.purepace-asc/asc.env` 再校验四项，缺失即停手；同时保留「ASC App 记录 / 签名 / 测试者 Apple ID」三项人动作的指向，隐私政策只写「ASC App 信息填 https://munk.sh/privacy」。

## 验收

- ac-asc-env-single-source: 两份文档均含 `~/.purepace-asc/asc.env` 与 `chmod 600`，四项变量齐全，且正文不再把 `export ASC_KEY_PATH=...` 作为录入主路径；`~/keys/` 零命中。
- ac-self-check-no-print: 自检命令段只做存在性判断，不 echo / printf 任何变量值，不含 `set -x`。
- ac-human-gate-needles: `grep -Fq asc.env docs/human-gate-distribution.md`、`grep -Fq 'chmod 600'`、`grep -Fq purepace-asc` 均命中，既有 needle（`ASC_KEY_PATH`/`ASC_KEY_ID`/`ASC_ISSUER_ID`/`TESTFLIGHT_TESTER_EMAIL`/`.p8`/`仓库之外`/`仓库`/`日志`/`CI`）全部保留。
- ac-legacy-shape-red: 新增反例自检——把样本中 `~/.purepace-asc/asc.env` 替换为 `~/keys/AuthKey.p8` 后 `human_gate_problems` 输出非空；反例不得依赖修改生产脚本之外的文件，且既有 UUID 反例仍绿。
- ac-gates-green: `bash scripts/check-ios-release.sh` 与 `bash scripts/check-baseline.sh` 退出 0。
- ac-no-credential-leak: 两份文档不含 `/Users/`、`/home/`、`set -x`、`BEGIN PRIVATE KEY`、真实 UUID。

## 非目标

- 不改 `scripts/archive-ios.sh` / `scripts/upload-ios.sh` / `scripts/testflight-tester.sh` 的行为与契约。
- 不改分发任务 instruction、不重开人闸卡、不执行真实归档 / 上传 / 测试者写入。
- 不改 `.github/workflows/**`、不改 `VERSION`、不改 bundle id / Team / 签名主干。
- 不扩 UI、功能面或验证基建。

## 实现约束

- 只改文档与 `check-ios-release.sh` 的这条断言及其反例；其它门腿不得弱化、不得删、不得 `continue-on-error`。
- 文档只写占位符与 `$HOME` / `~` 相对路径，不写本机绝对路径与任何真实凭据值。
- 新断言必须带「构造错误输入 → 必须红」的反例，且不依赖改生产代码才红。

## 本单执行约束（不 fold）

- 预算 ≤8M token、墙钟 ≤90 分钟；到点交未闭合回执，不续命。
- commit 按面拆分：文档与脚本改动不同 commit 或按仓内既有惯例，禁止混面（`code` / `fold` / `prd`）。
- 交付回执写：改了哪些段落、两条自检反例的红绿原文、`check-ios-release.sh` 与 `check-baseline.sh` 的退出码；未跑齐的腿记「未跑齐」并给截断依据。
- 不写「已发布 / 已分发 / 可下载」。
