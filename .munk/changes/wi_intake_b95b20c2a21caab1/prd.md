# device-run preflight 候选包布局双兼容（Payload/ 与根级 .app）

## Scope

- 修复 `scripts/device-run.sh` preflight 对候选包布局的硬假设：解包后 App bundle 解析同时接受 `unpack/Payload/*.app`（存在则优先）与 `unpack/*.app`（根级）；两者都无时仍 fail-closed，错误信息必须列出 `unpack/` 实际顶层条目。
- 同步修复 `scripts/verify-ios-device-flow.sh` 的候选身份绑定 `bind_candidate_identity`：`audio` 步骤经 `collect_candidate_identity` 调用它，当前同样只认 `Payload/*.app`，不修则 `--phase=all` 仍会在 `audio` 步失败。采用同一双布局、同一优先级、同一 fail-closed 口径；audio 三遍顺序、`--configuration=Release`、music 策略、launch-arg、证据路径一律不动。
- 增加可回归断言：`scripts/device-run.sh --self-check` 用临时目录现造四种夹具（不入库大文件），覆盖只有 `Payload/X.app`、只有根级 `X.app`、两者并存、两者都无四种情形，且不退化既有 self-check 断言。
- 同步文档中「解包 `Payload/*.app`」的过时描述（`docs/device-scripts.md`；如 `docs/device-flow-usage.md` / `docs/device-assertion-matrix.md` 涉及候选包布局口径一并同步）。

## Acceptance Criteria

- ac-layout-payload: 解包目录只有 `Payload/X.app` 时，布局解析返回该 `Payload/X.app`；preflight 后续从其 `Info.plist` 读到 bundle id / version / build / exec，zip sha 与 exec sha 正常计算。
- ac-layout-root: 解包目录只有根级 `X.app`（无 `Payload/`）时，布局解析返回该根级 `X.app`，并完成同样的 plist 读取与双 sha，不再报「缺少 Payload/*.app」。
- ac-layout-precedence: 同时存在 `Payload/X.app` 与根级 `Y.app` 时，解析结果为 `Payload/X.app`，且不得以「候选 zip 内含多个 .app」失败。
- ac-layout-missing: 两种布局都没有 `.app` 时 fail-closed 非零退出；错误文本含候选 zip 路径，并列出 `unpack/` 实际顶层条目（例如 `Payload`、`__MACOSX`；空目录时给出显式占位），不得只有固定的「缺少 Payload/*.app」。
- ac-layout-multi-app: 同一被选布局内出现多个 `.app` 时仍 fail-closed 非零退出，错误列出冲突的两个路径（既有语义不变）。
- ac-identity-unchanged: `--expect-zip-sha256` / `--expect-exec-sha256`（及同名 env）比对对象、匹配/不匹配行为与失败文案语义不变；exec sha 取自解析到的 App 可执行文件；`candidateKey` 仍为 zip sha256 前 16 位。
- ac-self-check-fixtures: `bash scripts/device-run.sh --self-check` 退出 0，且四组夹具各自独立断言并打印夹具名：①只有 `Payload/X.app` → 解析到它；②只有根级 `X.app` → 解析到它；③两者并存 → 取 `Payload/*.app` 且不报多 .app；④两者都无 → fail-closed 且错误含顶层条目。任一夹具不符即非零退出；夹具只落临时目录，结束时清理，不写入仓库。
- ac-audio-identity-layout: `scripts/verify-ios-device-flow.sh` 的候选身份绑定对上述四种布局给出与 preflight 一致的判定（Payload 优先、根级接受、同布局多 .app fail-closed、缺失 fail-closed 且含顶层条目），使 `--phase=audio` 在根级 `.app` 的 Release 候选 zip 上不再于身份绑定处失败；三遍顺序 app→runner→none、音乐策略与证据路径不变。
- ac-static-gate: `bash -n scripts/device-run.sh scripts/verify-ios-device-flow.sh`、`bash scripts/device-run.sh --self-check`、`bash scripts/check-ios-scripts.sh`、`bash scripts/check-shell-expansion.sh` 均退出 0；`.munk/code-gates.json` 零 diff，门数与 id 不变（22 门）。
- ac-scope-guard: `git diff --stat` 只含 `scripts/` 与 `docs/`（可含测试文件）；`git diff -- ios android shared artifacts/candidates .github .munk/code-gates.json` 为空；候选 zip 双 sha 不变（zip `a000b0e1…`、exec `d4947469…`），`artifacts/candidates/*` 零改动。
- ac-delivery-receipt: 交付回执写明改动的文件清单、新增断言条数与口径（夹具组数 vs 断言组数分开写清）、本地门结果，以及「本次未改二进制 ⇒ 候选 zip sha `a000b0e1…` / exec sha `d4947469…` 仍是唯一验收身份」的结论。

## Non-Goals

- 不改 App 源码 / `Info.plist` / 签名 / `ios/project.yml`；`ios/**`、`android/**`、`shared/**` 零 diff。
- 不重出候选包、不改 `artifacts/candidates/*`、不推 tag、不碰 ASC。
- 不调整 phase 顺序；不改证据路径、`summary.json` 字段、`logs/<phase>.log` 的 `START/END` 格式，不改 `rm -rf $state_dir/$evidence_dir` 语义。
- 不改锁屏 / TCC / audio 行为：audio 三遍顺序、music 策略、`-autoStartRecording`、`-releaseDeterministicLocation` 的 launch-arg 语义全部不动。
- 不新增真机步骤进 `code_gates` / CI，不增删或弱化既有门腿，不引入第三方依赖。
- 不重构 `--phase=plan` 输出结构，不新增 phase，不改 `candidateKey` 口径，不改 `.munk/baseline/**`（由 Delivery 收口）。

## Implementation Constraints

- 允许改动路径：`scripts/device-run.sh`、`scripts/verify-ios-device-flow.sh`（仅候选包布局解析 / 身份绑定）、`scripts/check-ios-scripts.sh`（如需追加静态断言）、`docs/device-scripts.md`、`docs/device-flow-usage.md`、`docs/device-assertion-matrix.md`；其余路径零 diff。
- 现状锚点：`scripts/device-run.sh` preflight 解包后 `for candidate_app in "${state_dir}"/unpack/Payload/*.app`（约 1045–1057 行）；`scripts/verify-ios-device-flow.sh` 的 `bind_candidate_identity` 内同型 `for candidate_app in "$unpack"/Payload/*.app`（约 513–525 行），`collect_candidate_identity` 在 `phase=audio` 时调用，`main` 无条件执行 `collect_candidate_identity`。
- 建议抽出一个无副作用布局 resolver（输入解包目录，成功回显 app 路径；失败非零并把顶层条目拼进消息），preflight 与 `--self-check` 共用同一实现，使夹具断言的正是生产路径，避免测试与实现分叉。若抽函数不便，self-check 必须调用与 preflight 同源的解析入口，不得复制一份逻辑。
- 优先级与判定：`Payload/` 下存在 `*.app` 时只在其中判多义；否则看根级 `*.app`（`Payload/` 目录本身不会匹配 `*.app`，仍需排除 `__MACOSX` 干扰）；同一层多 `.app` 立即 fail-closed。
- self-check 夹具：用 `mktemp -d`（或 `state_dir` 下临时目录）现造空目录 `Payload/X.app`、`X.app`，只判目录存在与 resolver 输出 / 失败消息；不构造真实二进制、不入库大文件；结束 `rm -rf` 清理。
- fail-closed 文案：保留候选 zip 路径，附 `unpack/` 顶层条目（`ls -A` 或等价）；主流程无 `|| true` / `|| :` 吞错，不关闭 `set -euo pipefail`。
- 真机实证（判断依据）：2026-11-10T09:50:13Z 窗口失败原文 `failedStep=preflight` / `reason: 解包后缺少 Payload/*.app: …/artifacts/candidates/PurePace-Release-0.1.0-20261110T054214Z.zip`；该 zip 顶层为 `PurePace.app/` + `__MACOSX/`；zip sha256 `a000b0e19c2ee4b5c7f8e067abd9f4c25f95b43569c45b29160c73e38c736897`，exec sha256 `d494746936c99043557ae3ba82fe2c94a3bb84c9beb0412e242dda182ef7139d`；`artifacts/candidates/` 下现存 9 个候选包全部为根级 `*.app` 布局。故本项只做双布局兼容，不改出包侧、不重出包。
- 预算：≤90 分钟 / ≤8M token；超时停手回执写清已完成到哪一步，不带病扩范围。
