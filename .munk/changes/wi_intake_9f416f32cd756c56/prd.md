# 分发凭据口径收尾：stage4-prereqs 复核段与活文档守卫

## 范围

- 改 `docs/release/stage4-prereqs.md`「复核方法（凭据只用占位符）」段：凭据加载改为 `. ~/.purepace-asc/asc.env` 后逐项判存在性（不打印值），删掉 `. ~/.munk-release/secrets.env` 这一过时落点；保留该段「只读自检 / 建 App 记录 / 回读校验」的既有语义与占位符写法。
- `scripts/check-ios-release.sh` 新增结构守卫（复用 `asc_env_problems` 口径）：`docs/release/stage4-prereqs.md` 含 `~/.purepace-asc/asc.env`、且 `~/.munk-release/secrets.env` 零命中；命中旧落点即判红。
- 新增反例自检：沙箱样本把 asc.env 行换回 `~/.munk-release/secrets.env` 后守卫必须非空；不改生产脚本即可判红。
- 仓内 `AGENTS.md` 增一条约定（≤2 行）：分发凭据唯一落点是 `~/.purepace-asc/asc.env`，活文档必须引用该口径；`.munk/changes/**` 与 `.munk/baseline/**` 的历史记录不改。

## 验收

- ac-stage4-review-asc-env: `git grep -n 'munk-release/secrets.env' origin/main -- docs/` 零命中；`docs/release/stage4-prereqs.md` 复核段含 `~/.purepace-asc/asc.env` 且自检命令不 echo/printf 变量值。
- ac-stage4-gate-and-counterexample: `check-ios-release.sh` 对 stage4-prereqs 的新守卫在 main 上退出 0，沙箱反例（asc.env → `~/.munk-release/secrets.env`）判红，日志含该反例 pass 行。
- ac-repo-agents-line: 仓内 `AGENTS.md` 含「`~/.purepace-asc/asc.env`」唯一落点这一条，且未改写既有「Recent Conclusions」标题与条目。
- ac-gates-green: `bash scripts/check-ios-release.sh` 与 `bash scripts/check-baseline.sh` 退出 0（含 AGENTS.md 相关尺寸 / needle 断言）。

## 非目标

- 不改 `docs/human-gate-distribution.md` 与 `docs/release/testflight-runbook.md`（上一单已对齐）。
- 不改 `.munk/changes/**`、`.munk/baseline/**` 历史记录文本。
- 不改归档 / 上传 / 测试者脚本行为，不改 workflow、`VERSION`、bundle id、签名，不执行真实归档 / 上传。
- 不动 stage4-prereqs 里其它产品（如 `com.chaxiu.purepace`）的历史条目。

## 实现约束

- 新断言必须带「构造错误输入 → 必须红」的反例，且不依赖改生产代码。
- 门腿不得删、不得弱化、不得 `continue-on-error`。
- 文档只写占位符与 `~` / `$HOME` 相对路径，不写本机绝对路径与真实凭据。

## 本单执行约束（不 fold）

- 预算 ≤8M token、墙钟 ≤90 分钟；到点交未闭合回执。
- commit 按面拆分（code / fold / prd 不混面）。
- 回执写：改了哪些段落、反例红绿原文、两条门退出码；未跑齐的腿记「未跑齐」并给依据。
- 不写「已发布 / 已分发 / 可下载」。
