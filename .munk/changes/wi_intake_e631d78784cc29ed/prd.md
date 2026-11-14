# iOS 分发脚本化：归档 → 上传 App Store Connect → 分配内部测试者

## 范围

在既有归档/导出链路上补齐「上传 → 内部测试者分配」两个脚本，并同步工程加密豁免声明、分发静态门、Runbook 与凭据录入文档：

1. `scripts/upload-ios.sh`：默认取 `scripts/archive-ios.sh` 产物目录（`${TMPDIR:-/tmp}/purepace-dist/<version>-<build>/export`）里的 ipa，支持 `--ipa` 覆盖；流程 = 只读校验（`xcrun altool --list-apps --apiKey --apiIssuer`，只输出命中条数）→ 上传（`xcrun altool --upload-app -f <ipa> -t ios --apiKey ... --apiIssuer ...`）→ 输出版本与上传结果。凭据只从 `ASC_KEY_PATH` / `ASC_KEY_ID` / `ASC_ISSUER_ID` 读取，缺失即非零退出且不触网；`DRY_RUN=1` 回显脱敏命令、不联网、退出 0。
2. `ios/project.yml` 的 PurePace target `info.properties` 增加 `ITSAppUsesNonExemptEncryption: false`，并让 `ios/PurePace/Info.plist` 与其生成结果一致（实测 XcodeGen 会把该 properties 写进 plist）。
3. `scripts/testflight-tester.sh`：用 ASC API 把 `TESTFLIGHT_TESTER_EMAIL` 加入该 App 的内部测试组（读 `/v1/betaGroups` 取内部组 → 必要时 `POST /v1/betaTesters` → 加关系）；只读或权限失败即停手并原文报告。
4. `scripts/check-ios-release.sh` 扩展覆盖 upload/tester 脚本契约，接入既有 `lint-ios-release` 门，并把两个新脚本加入 `scripts/check-ios-scripts.sh` 的枚举。
5. `docs/release/testflight-runbook.md` 改写为主路径 = 脚本上传 + 脚本分配测试者；Transporter 仅 fallback。
6. `docs/human-gate-distribution.md`：落一份「人的动作只剩一次性录入凭据」的说明（该文件当前不存在，本项创建）。

## 验收

- ac-upload-script-contract: `scripts/upload-ios.sh` 存在，`bash -n` 通过，shebang 为 `#!/usr/bin/env bash`，含 `set -euo pipefail` 与 `BASH_SOURCE`；`--help` 退出 0 且输出含「用法」，未知参数退出 2，参数错误退出 2。
- ac-upload-default-ipa-and-override: 未传 `--ipa` 时默认解析到 `${TMPDIR:-/tmp}/purepace-dist/<version>-<build>/export` 下唯一的 `*.ipa`（版本取自 `scripts/version.sh`、build 取自 `BUILD_NUMBER` 缺省 1，并支持 `OUT_DIR` 覆盖）；该目录无 ipa 时非零退出且提示可用的 `--ipa` 兜底；`--ipa <路径>` 覆盖默认解析并校验文件存在。
- ac-upload-lists-then-uploads: 非 DRY_RUN 成功路径先执行 `xcrun altool --list-apps`（携带 `--apiKey` / `--apiIssuer`，仅打印命中条数，不打印 App 清单或凭据），再执行 `xcrun altool --upload-app -f <ipa> -t ios`；结束打印 ipa 路径、版本与 build、上传结果，退出 0。
- ac-upload-missing-credentials-fails-closed: 缺少任一 `ASC_*` 变量时脚本非零退出，输出只含缺失变量名；已设置变量的值不出现；桩 `xcrun` 未被调用（未触网）。
- ac-upload-dry-run-redacted: 三凭据全未设置且 `DRY_RUN=1` 时退出 0，回显包含 `--list-apps` 与 `--upload-app` 及字面量占位符 `$ASC_KEY_PATH` / `$ASC_KEY_ID` / `$ASC_ISSUER_ID`；设置伪凭据时输出不出现 `FAKEKEYID` / `FAKE-ISSUER-UUID` / `FAKE-KEY.p8`，且桩 `xcrun` 未被调用。
- ac-upload-no-credential-persistence: 两个新脚本均不含 `set -x`、不含用户目录绝对路径与私钥/JWT 字面量，不向仓库写 `.p8` / `.env` / 凭据文件（运行后 `git status --porcelain` 无凭据类新增）。
- ac-encryption-exemption-declared: `ios/project.yml` 的 PurePace target `info.properties` 含 `ITSAppUsesNonExemptEncryption: false`（布尔，不是字符串），`ios/PurePace/Info.plist` 含 `<key>ITSAppUsesNonExemptEncryption</key>` 且紧随 `<false/>`；静态门对「删除该键」的构造样本必须判红（反例自检）。
- ac-tester-script-contract: `scripts/testflight-tester.sh` 存在且满足与 upload 相同的脚本契约（bash -n / shebang / 严格模式 / `--help` / 未知参数 2）；凭据缺失或 `TESTFLIGHT_TESTER_EMAIL` 缺失/非法时非零退出且不触网；`DRY_RUN=1` 回显脱敏步骤计划、不联网、退出 0。
- ac-tester-readonly-first-internal-group: 成功路径先只读 `GET /v1/betaGroups`（按 App 过滤并选中 `isInternalGroup=true` 的组），再按需 `POST /v1/betaTesters`、最后 `POST /v1/betaGroups/{id}/relationships/betaTesters`；只读或权限失败（非 2xx）立即停手，原文输出 HTTP 状态码与 `errors[].code` / `title`，不重试、不换端点，且不执行任何写请求。
- ac-tester-no-external-invite-or-review: 脚本不引用 `betaAppReviewSubmissions` / `appStoreVersions` / `reviewSubmission`，不向外部组（`isInternalGroup` 非 true）写关系，不触发 Beta App Review，也不打印 JWT / Issuer / Key ID / 私钥内容。
- ac-gate-covers-distribution-scripts: `scripts/check-ios-release.sh` 覆盖上述 upload（无硬编码凭据、无 `set -x`、DRY_RUN 不联网、缺凭据即失败、`--list-apps` 先于 `--upload-app`）与 tester（只读先行、内部组限定、失败停手）契约，且保留 `ExportOptions` 仍为 `app-store-connect` + `automatic` + `uploadSymbols=false`；每条新断言都配「构造错误输入 → 必须红」反例自检并计入断言总数。
- ac-gate-wiring-consistent: 不新增 `code_gates` 条目（门数保持 22，`lint-ios-release` 的 `command` 仍为 `bash scripts/check-ios-release.sh`）；`scripts/check-ios-scripts.sh` 的 `targets` / `strict_targets` 枚举包含 `upload-ios.sh` 与 `testflight-tester.sh`，其帮助文案按实际脚本数更新，门数与拓扑断言仍通过。
- ac-runbook-script-first: `docs/release/testflight-runbook.md` 主路径改为 `bash scripts/archive-ios.sh` → `bash scripts/upload-ios.sh` → `bash scripts/testflight-tester.sh`，人的动作只剩一次性录入凭据并指向 `docs/human-gate-distribution.md`；删除「必须由人在场执行 xcodebuild」的主路径表述；保留 `前置` / `执行步骤` / `证据` / `反范围` 四段与 `$ASC_KEY_PATH` / `$ASC_KEY_ID` / `$ASC_ISSUER_ID` / `xcrun altool --list-apps` / `xcodebuild -version` / `sha256` / `commit` / `.env` 等既有断言要素，命令仍只用占位符。
- ac-runbook-transporter-fallback: 同文件明确把 Xcode Organizer / Transporter 标为 fallback（非主路径），且不出现「上传/邀请测试者由人手工完成」的主路径措辞。
- ac-human-gate-doc: `docs/human-gate-distribution.md` 存在且非空，说明一次性凭据录入（三个 `ASC_*` 变量、`.p8` 必须在仓库外、`TESTFLIGHT_TESTER_EMAIL`），明确凭据不得进仓库 / 日志 / CI，且文件内无真实凭据值、无用户目录绝对路径。
- ac-no-real-upload-and-scope-frozen: 本项不执行真实上传或真实测试者写入；不 push tag、不建 GitHub Release、不改 `VERSION` / bundle id / Team / 签名主干与 `archive-ios.sh` 既有导出逻辑；`.github/workflows/ios.yml` 的腿与触发条件零改动；不引入 fastlane 或第三方运行时依赖；回执写「真实上传未执行（待凭据）」，不得写已分发。
- ac-readme-distribution-entries: `README.md`「构建与测试入口」表补 `bash scripts/upload-ios.sh` 与 `bash scripts/testflight-tester.sh` 两行，不写根 `VERSION` 字面值，既有 `archive-ios.sh` / `check-ios-release.sh` 行保留。

## 非目标

- 不做真实上传、真实 TestFlight 测试者写入、App Store 提交审核或外邀（本项无凭据；真实上传由 projects/ops_8323364a501d6c1c 的分发任务执行）。
- 不 push tag、不建 GitHub Release、不改 `VERSION` / bundle id / Team / 签名主干、不重写 `archive-ios.sh` 既有导出与产物逻辑。
- 不删除或弱化 `ios.yml` 既有腿、不改其触发条件、不把分发塞进 CI。
- 不新增 `code_gates` 条目、不扩门数；不引入 fastlane 或其他第三方分发/加密依赖。
- 不改 `docs/release/stage4-prereqs.md` 的状态事实、不改 README / CHANGELOG 的「已推 tag、未分发」口径。
- 不做真机验收、不改 App 业务代码与 UI。

## 实现约束

- **已完成的环境事实**：本机 `xcrun altool 26.10.1` 与 `xcrun iTMSTransporter` 可用；`xcodegen` 会按 `project.yml` 的 `info.properties` 重写 `ios/PurePace/Info.plist`（默认键 + properties 排序输出），故加键后须把生成后的 plist 一并提交，保持 `xcodegen generate` 无 diff。
- **upload 脚本**：复用 `archive-ios.sh` 的凭据校验形态（`printenv` 判存在、只打印变量名、DRY_RUN 不展开凭据）；altool 调用在目标验收要求的 `--apiKey <id> --apiIssuer <issuer>` 之外，建议追加 `--apiPrivateKey "$ASC_KEY_PATH"`，避免依赖 `~/.appstoreconnect/private_keys` 固定落点；上传前置只读 `--list-apps` 输出仅「命中条数」；退出码沿用 0/1/2（成功/失败/参数非法）。
- **tester 脚本**：ASC REST + ES256 JWT（`openssl dgst -sha256 -sign` 签 `ASC_KEY_PATH`，JWT 只在内存，不落盘不打印）；App 先按 `filter[bundleId]=sh.munk.purepace` 只读解析；凭据能力不足时原文报告 `errors[].code|title` 即停手。
- **门与枚举**：新断言全部并入既有 `lint-ios-release`（不新增 gate，门数 22 不变）；`scripts/check-ios-scripts.sh` 只加脚本枚举与帮助文案，不改门数与拓扑断言；`check-ios-release.sh` 的 `network_problems` 仍只约束归档脚本，upload/tester 的联网规则单独成函数，避免把 altool/curl 一刀切。
- **反例自检**：每条新断言用 `mktemp -d` 沙箱构造错误输入（删凭据、注入 `set -x`、删 `--list-apps`、把组的 `isInternalGroup` 改成 false、删 `ITSAppUsesNonExemptEncryption`），确认检测函数判红；桩 `xcrun` / `curl` 用 marker 文件证明未触网。
- **commit 按面拆分**：建议 1) project.yml + Info.plist + 加密豁免断言；2) `upload-ios.sh`；3) `testflight-tester.sh`；4) `check-ios-release.sh` + `check-ios-scripts.sh` 枚举 + code_gates 一致性；5) Runbook + 凭据录入文档 + README 入口；每个 commit 自身可过 `bash scripts/check-ios-release.sh` 与 `bash scripts/check-ios-scripts.sh`。
- **DoD**：本地 `check-ios-release.sh` / `check-ios-scripts.sh` 全绿，同 commit `ios.yml` 全绿；回执明确写「真实上传未执行（待凭据）」。
