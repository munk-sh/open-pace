# 根治 Android CI 腿的 Gradle 分发下载脆弱性（接入官方 Gradle 缓存 + bin 分发 + wrapper 有界重试）

## 范围

只改两个文件，其它一律不动：

1. `.github/workflows/android.yml`：在 `checkout` / `install-jdk` 之后、`lint` 之前插入一步官方 `gradle/actions/setup-gradle@v6`，开启 Gradle User Home 缓存（缓存 `~/.gradle/wrapper/dists` 与 `~/.gradle/caches`，含 `caches/modules-2`）。使用官方 Basic 缓存提供方（`cache-provider: basic`，即 100% 开源 `actions/cache` 实现），其缓存键为 `setup-java-{RUNNER_OS}-{arch}-gradle-{hash}`，hash 取自 `**/*.gradle*`、`**/gradle-wrapper.properties` 等构建文件内容（含本轮 `gradle-wrapper.properties` 的 hash），不是固定 key。显式 `cache-read-only: 'false'`，避免非默认分支默认只读导致「只读不写缓存」。保留既有 job/step 语义与失败判定。
2. `android/gradle/wrapper/gradle-wrapper.properties`：`distributionUrl` 由 `gradle-8.14.3-all.zip` 换成 `gradle-8.14.3-bin.zip`（体积约一半，去掉 docs/sources），新增官方 `distributionSha256Sum`，`retries=3` + `retryBackOffMs=1000` 作兜底，其余键保持不变。

背景事实（已实测）：`main@bea5040` 的 android run 42471304587 因 `services.gradle.org` 返回 HTTP 504、wrapper `Attempt 1/1` 一次即红；根因是每条 android 腿都现下 230MB+ 的 `all.zip`、仓内无 Gradle 缓存、wrapper `retries=0`。`main@e0fbdc59`（`829cd` 合入）两条 run 42475233796 / 42475233696 已绿属兜底，不是根治。

## 验收

- ac-workflow-has-setup-gradle: `.github/workflows/android.yml` 存在 `uses: gradle/actions/setup-gradle@v6` 的步骤，且其 YAML 步骤顺序位于 `checkout`、`install-jdk` 之后与 `lint` 之前。
- ac-workflow-cache-config: 该步骤 `with` 恰含 `cache-provider: basic`、`cache-read-only: 'false'`；不额外接 `Develocity` / `build-scan` / `dependency-graph` / `cache-encryption-key` 等输入。
- ac-cache-key-not-fixed: 文件内无固定 key 的缓存步骤——不出现 `actions/cache` 步骤；若出现，其 `with.key` 必须含 `hashFiles(`。
- ac-workflow-semantics-preserved: 解析后仍为单 job、`runs-on: ubuntu-latest`、`timeout-minutes: 45`、`permissions.contents: read`；`install` / `lint` / `test` / `build` 四步名称与顺序不变且 `run` 非空；文件内不出现 `continue-on-error` / `allowed-failure`，不删 job、不删步、不摘 test/build 腿。
- ac-workflow-gates-green: `bash scripts/check-android-workflow.sh`（含 4 条反例自检）、`bash scripts/check-android.sh`、`bash scripts/check-baseline.sh` 全部退出 0；三个脚本与 `.munk/code-gates.json` 零改动。
- ac-distribution-url-bin: `distributionUrl` 精确等于 `https\://services.gradle.org/distributions/gradle-8.14.3-bin.zip`，文件中不出现 `-all.zip`。
- ac-distribution-sha256-sum: 文件含 `distributionSha256Sum=bd71102213493060956ec229d946beee57158dbd89d0e62b91bca0fa2c5f3531`（64 位小写十六进制），与官方 `gradle-8.14.3-bin.zip` 一致。
- ac-wrapper-retries: 文件含 `retries=3`、`retryBackOffMs=1000`、`networkTimeout=10000`、`validateDistributionUrl=true` 四个键且取值精确（`retries` 不再是 0）。
- ac-properties-parseable: properties 每行满足 `key=value`、键唯一、无 CR；`bash scripts/version.sh` 仍解析出 Gradle `8.14.3`（离线，不触网、不启动 JVM）。
- ac-scope-two-files: 相对基线 `git diff --name-only` 仅含 `.github/workflows/android.yml` 与 `android/gradle/wrapper/gradle-wrapper.properties`（外加 `.munk/changes/**`）；`scripts/**`、`.munk/code-gates.json`、`android/**`（仅 wrapper properties 允许）、`ios/**`、`shared/**` 零改动。
- ac-local-evidence-recorded: 交付说明写明本机验证证据：YAML 解析通过（本机 `python3` 无 PyYAML，用 `ruby -ryaml`，与仓内既有门同口径）、properties 解析通过、sha256 取值来源为官方 `https://services.gradle.org/distributions/gradle-8.14.3-bin.zip.sha256` 与 `https://gradle.org/release-checksums/` 及 `https://downloads.gradle.org/distributions/gradle-8.14.3-bin.zip.sha256` 三处一致。
- ac-remote-run-recorded: 交付 push 触发的 `android` run 记录真实数字 run id 与 conclusion（来源 `gh run list --repo munk-sh/open-pace --workflow android.yml` 或 Host CI 通道）。取不到时逐字记 `pending: 待远端复核`，禁止编造 run id。
- ac-second-run-cache-hit: 复核用第二次 push 触发的 `android` run 日志出现缓存恢复命中（如 `Cache restored from key` / `Restored Gradle User Home`）且不再出现 `Downloading https://services.gradle.org`，两次 run 均 `success` 才算根治。
- ac-cache-scope-honest-report: 若复核 run 与写缓存 run 跨分支（GitHub 缓存按分支作用域，功能分支条目对默认分支不可见）导致该次仍冷启动，交付说明必须给出真实 run id、日志行与该作用域事实，不得写成「已命中」，也不得为凑命中反复推空提交。

## 非目标

- 不改 `scripts/` 下任何脚本（含 `scripts/check-android.sh` 里 `gradle-8.14.3-all.zip: HTTP 504` 的沙箱桩字符串、`scripts/version.sh`、`build-android.sh` / `test-android.sh`）、不改 `.munk/code-gates.json`。
- 不改 `android/` 业务代码、Gradle/AGP 版本、依赖声明、`gradlew` 脚本、`gradle-wrapper.jar`（已确认该 jar 支持 `distributionSha256Sum` 与 `retryBackOffMs`）。
- 不改 iOS 腿、`.github/workflows/ios.yml`、`shared/**`；不新增 job / 矩阵 / 分支保护 / secrets / environment。
- 不做 Android SDK、JDK、Robolectric 专项目录、构建产物（APK / test-results）缓存；不接 Develocity / Build Scan / dependency-graph / 覆盖率 / 产物上传。
- 不放宽任何失败判定：不引入 `continue-on-error` / allowed-failure，不降级 `blocked:` 判定，不删或跳过 test / build 腿。
- 不改 `README.md` 与 `.munk/baseline/**`（baseline 由 Host 折叠）。本项取代 `android-ci` baseline 中「不引入依赖缓存」的旧非目标（公司负责人 2026-11-08 裁决）。
- 不在本机全量下载 130MB+ 分发包复算校验和（本机拉取该包 200s 超时，与 CI 同源网络脆弱），sha256 以三处官方源交叉核对为准。

## 实现约束

**精确改动（Coding 按此执行，不多不少）**

`.github/workflows/android.yml`：在 `install-jdk` 步之后、`install-sdk` 步之前插入（其余内容逐字保留）：

```yaml
      - name: gradle-cache
        uses: gradle/actions/setup-gradle@v6
        with:
          cache-provider: basic
          cache-read-only: 'false'
```

`android/gradle/wrapper/gradle-wrapper.properties` 目标内容：

```properties
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.14.3-bin.zip
distributionSha256Sum=bd71102213493060956ec229d946beee57158dbd89d0e62b91bca0fa2c5f3531
networkTimeout=10000
retries=3
retryBackOffMs=1000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
```

**选型理由（避免 Coding 改主意）**

- `gradle/actions/setup-gradle@v6` 是官方 action（`gradle/actions` 最新发布 v6.4.1，2026-10-28）。其 Basic 提供方（`cache-provider: basic`）文档明确缓存 `~/.gradle/caches` 与 `~/.gradle/wrapper`，键为 `setup-java-{RUNNER_OS}-{arch}-gradle-{hash}`，hash 取自 `**/*.gradle*`、`**/gradle-wrapper.properties` 等——正好满足「键必须含 wrapper properties hash、不得固定 key」的硬约束，且是 100% 开源 `actions/cache` 实现。
- 不用 Enhanced 默认提供方：其键为 `{os}|{job-id}|{workflow-hash}|{git-sha}`（靠 restore key 兜底），不含 wrapper properties hash，与本项硬约束不符；也避免引入专有缓存服务。
- 不用手写 `actions/cache`：官方 action 已覆盖同一目录且自带 wrapper 校验与 job 摘要，无需自创第二套。

**已实测的既有门禁约束（改动必须继续满足）**

- `scripts/check-android.sh` 要求 `^distributionUrl=.*gradle-[0-9]+\.[0-9]+(\.[0-9]+)?-(bin|all)\.zip$`（`-bin.zip` 合法），并要求整个 properties 文件不含 `latest` / `snapshot`（大小写不敏感）与 `+` —— 因此该文件**不要新增任何注释**。
- `scripts/check-android-workflow.sh` 要求文件原文不含 `gradlew`（`setup-gradle` 不含该串）、`install` 步仍含 `actions/setup-java@v4` + temurin + `java-version: '21'` + `setup-android@v3` + java 主版本/`ANDROID_HOME` 校验；额外步骤名不在断言集合内，不影响 `install`/`lint`/`test`/`build` 顺序断言。
- 已用「临时目录 + 拷贝门脚本 + 计划版 YAML」预跑真实门：10 条断言 + 4 条反例自检全 PASS，`check-android-workflow.sh` 退出 0；计划版 properties 亦通过 url 正则、浮动标记与 `+` 检查，`version.sh` 的 sed 仍解析出 `8.14.3`。
- properties 文件路径不要改；`distributionSha256Sum` 用上表精确值（由三处官方源核对，见 `ac-local-evidence-recorded`）。

**本机验证命令（Coding/交付说明照此取证）**

```bash
ruby -ryaml -e 'YAML.load(File.read(".github/workflows/android.yml"))'   # 本机无 PyYAML
bash scripts/check-android-workflow.sh
bash scripts/check-android.sh
bash scripts/check-baseline.sh
bash scripts/version.sh            # 期望 Gradle 行仍为 8.14.3
git diff --name-only
```

**缓存作用域事实（交付与复核口径）**

GitHub Actions 缓存按分支作用域：功能分支写入的条目对默认分支不可见。因此「写缓存 run」与「命中 run」同分支时第二次必命中；若交付 push 在功能分支、Owner 复核 push 落在 main 且 main 尚无条目，则该次仍冷启动——须按 `ac-cache-scope-honest-report` 如实报告，不得为凑命中反复推空提交。冷启动 run 也应 success（bin 包更小 + wrapper 3 次重试 + 官方 action 自带校验），这是本项「不靠缓存也不红」的兜底价值。

**推送与阻塞口径**

- workflow 文件推送所需的 workflow scope 已由人补齐。只推本分支 `munk/{workItemId}` 触发 `on.push`，一次推送后轮询 `gh run list`；取不到即记 `pending: 待远端复核`。
- 网络 git 操作统一 `env -u GIT_EXEC_PATH git ...`。若 push 报 `refusing to allow` / workflow scope / remote-https / `GIT_EXEC_PATH` 类错误，把原文整段记入 waiting 理由后停手：不重试到绿、不 bash 绕行、不改 remote、不推 tag。
- 远端 run 为 `failure` / `cancelled` 时本项不交付，附失败 run id 与失败步骤日志摘要，不沿用旧绿 run。
