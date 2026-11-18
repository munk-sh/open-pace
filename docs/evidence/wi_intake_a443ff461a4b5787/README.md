# 定位失败两条断言的变异红证（证据项，产品代码零改动）

- workItemId: `wi_intake_a443ff461a4b5787`
- 基线 commit: `90bb205723fe95070b62ddfa3777a4cb80d0b05f`（main，`merge(delivery): 定位失败链路补丁并入默认分支`）
- 被测断言（仓库内零改动）:
  - `ios/PurePaceTests/RunPermissionAndDiagnosticsTests.swift:272` `testLocationFailureAndServicesOffSetUnavailableAndExposeCopy`
  - `ios/PurePaceTests/RunPermissionAndDiagnosticsTests.swift:325` `testRecoveryAfterLocationFailureReturnsReady`
- 变异位置（唯一被改文件）: `ios/PurePace/Location/RunLocationSource.swift`，且只在 `/tmp/pp-mut-a443ff461a4b5787/repo/` 副本内改。
- 本项不改产品代码 / 文案 / identifier / `ios/**`；仓库 `git status --porcelain` 只有本证据目录与 `.munk/changes/` 的未跟踪文件。

## 环境与命令

环境：macOS（darwin arm64）、Xcode 26.3 (17C529)、模拟器 iPhone 16 / iOS 18.6（`id=B3F00298-E08A-41E0-876E-6E8A75C730FD`，已 Booted）、`xcodegen` 3.x。

沙箱准备（仓库只读复制，`.git` / `.munk` / `.build` 不进副本）：

```bash
D=/tmp/pp-mut-a443ff461a4b5787
mkdir -p "$D" && rsync -a --exclude '.build' --exclude '.git' --exclude '.munk' ./ "$D/repo/"
cd "$D/repo" && xcodegen generate --spec ios/project.yml --project ios
```

每次（未变异 / 三种变异）都用同一条命令，只换 `/tmp` 副本内的源码形态：

```bash
xcodebuild test -project ios/PurePace.xcodeproj -scheme PurePace \
  -destination 'platform=iOS Simulator,id=B3F00298-E08A-41E0-876E-6E8A75C730FD' \
  -derivedDataPath "$D/dd" \
  -only-testing:PurePaceTests/RunPermissionAndDiagnosticsTests/testLocationFailureAndServicesOffSetUnavailableAndExposeCopy \
  -only-testing:PurePaceTests/RunPermissionAndDiagnosticsTests/testRecoveryAfterLocationFailureReturnsReady \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 300 CODE_SIGNING_ALLOWED=NO
```

日志为本轮 `xcodebuild` 原始输出的裁剪版（保留 `# 变异说明` / 变异 diff / `Test Case` / `error:` / `Executed N tests` / `** TEST ... **`）：

| 文件 | 含义 | 退出码 | 摘要 |
|---|---|---|---|
| `logs/green.log` | `90bb205` 未变异 | 0 | `Executed 2 tests, with 0 failures` / `** TEST SUCCEEDED **` |
| `logs/mutation-a1-guard-only.log` | 只删 `guard servicesEnabled else { endUpdating(); return }` | 0 | `Executed 2 tests, with 0 failures`（**未判红，见「发现」**） |
| `logs/mutation-a2-full-precheck.log` | 删整段前置检查（读取 + 回写 + guard） | 65 | `Executed 2 tests, with 2 failures` / `** TEST FAILED **` |
| `logs/mutation-b.log` | 断开 `locationManagerDidFail` → `lastLocationErrorCode` 转发 | 65 | `Executed 2 tests, with 9 failures` / `** TEST FAILED **` |
| `logs/mutation-c.log` | `start()` 恢复时不清 `lastLocationErrorCode` | 65 | `Executed 2 tests, with 3 failures` / `** TEST FAILED **` |

## 未变异（绿）

```
Test Case '-[PurePaceTests.RunPermissionAndDiagnosticsTests testLocationFailureAndServicesOffSetUnavailableAndExposeCopy]' passed (0.004 seconds).
Test Case '-[PurePaceTests.RunPermissionAndDiagnosticsTests testRecoveryAfterLocationFailureReturnsReady]' passed (0.001 seconds).
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.005 (0.006) seconds
** TEST SUCCEEDED **
```

## 变异红证（原文）

### (a2) 去掉 `start()` 的 `servicesEnabled` 前置检查

```diff
@@ -211,13 +211,7 @@
     func start() {
-        // 前置检查：系统定位服务被关闭时不得启动更新，也不得把「无数据」当正常态。
-        let servicesEnabled = manager.locationServicesEnabled
-        locationServicesEnabled = servicesEnabled
-        guard servicesEnabled else {
-            endUpdating()
-            return
-        }
+        // MUTATION(a2): 整段 servicesEnabled 前置检查（读取/回写/guard）被移除
```

```
RunPermissionAndDiagnosticsTests.swift:320: error: -[... testLocationFailureAndServicesOffSetUnavailableAndExposeCopy] : XCTAssertFalse failed
RunPermissionAndDiagnosticsTests.swift:321: error: -[... testLocationFailureAndServicesOffSetUnavailableAndExposeCopy] : XCTAssertEqual failed: ("ready") is not equal to ("unavailable") - 服务关闭必须置不可用态
	 Executed 2 tests, with 2 failures (0 unexpected) in 0.308 (0.309) seconds
** TEST FAILED **
```

### (b) 断开 `locationManagerDidFail` 到 `lastLocationErrorCode` 的转发

```diff
@@ -355,7 +355,8 @@
     func locationManagerDidFail(code: Int) {
-        lastLocationErrorCode = code
+        // MUTATION(b): didFailWithError -> lastLocationErrorCode 转发被断开
+        _ = code
     }
```

```
RunPermissionAndDiagnosticsTests.swift:281: error: -[... testLocationFailureAndServicesOffSetUnavailableAndExposeCopy] : XCTAssertEqual failed: ("nil") is not equal to ("Optional(0)") - 最近一次系统定位失败必须被记录，不得静默丢弃
RunPermissionAndDiagnosticsTests.swift:286: error: -[... testLocationFailureAndServicesOffSetUnavailableAndExposeCopy] : XCTAssertEqual failed: ("ready") is not equal to ("unavailable") - 定位失败必须置不可用态
RunPermissionAndDiagnosticsTests.swift:289: error: ... XCTAssertEqual failed: ("nil") is not equal to ("Optional("run.status.locationUnavailable")") - 必须复用既有定位不可用文案键
RunPermissionAndDiagnosticsTests.swift:290: error: ... XCTAssertEqual failed: ("nil") is not equal to ("Optional("定位暂不可用，请重试")")
RunPermissionAndDiagnosticsTests.swift:291: error: ... XCTAssertFalse failed - 不可用态必须有可见文案，不能只有内部状态
RunPermissionAndDiagnosticsTests.swift:292: error: ... XCTAssertEqual failed: ("nil") is not equal to ("Optional(PurePace.RunLocationReadiness.NextAction.retry)") - 不可用态的唯一出口是既有 retry
RunPermissionAndDiagnosticsTests.swift:298: error: ... XCTAssertEqual failed: ("nil") is not equal to ("Optional(PurePace.RunInteractionPlan.Notice.locationUnavailable)") - 不可用态必须在跑步页渲染定位提示行
RunPermissionAndDiagnosticsTests.swift:308: error: ... XCTAssertNotEqual failed: ("ready") is equal to ("ready")
RunPermissionAndDiagnosticsTests.swift:331: error: -[... testRecoveryAfterLocationFailureReturnsReady] : XCTAssertEqual failed: ("ready") is not equal to ("unavailable")
	 Executed 2 tests, with 9 failures (0 unexpected) in 0.115 (0.116) seconds
** TEST FAILED **
```

### (c) 恢复（`start()`）时不清旧错误码

```diff
@@ -217,8 +217,8 @@
         locationServicesEnabled = servicesEnabled
         guard servicesEnabled else { ... }
-        lastLocationErrorCode = nil
+        // MUTATION(c): 恢复（start）时不再清空旧错误码
         let status = manager.authorizationStatus
```

```
RunPermissionAndDiagnosticsTests.swift:346: error: -[... testRecoveryAfterLocationFailureReturnsReady] : XCTAssertNil failed: "0" - 恢复成功后必须清掉旧错误，避免残留不可用态
RunPermissionAndDiagnosticsTests.swift:347: error: -[... testRecoveryAfterLocationFailureReturnsReady] : XCTAssertEqual failed: ("unavailable") is not equal to ("ready")
RunPermissionAndDiagnosticsTests.swift:348: error: -[... testRecoveryAfterLocationFailureReturnsReady] : XCTAssertNil failed: "定位暂不可用，请重试" - 恢复就绪后不得再显示不可用文案
	 Executed 2 tests, with 3 failures (0 unexpected) in 0.107 (0.108) seconds
** TEST FAILED **
```

## 发现（如实记账，本项不修）

1. **`startUpdatingLocation` 计数断言对「只删 guard」不敏感**：`logs/mutation-a1-guard-only.log` 显示只删 `guard servicesEnabled else { endUpdating(); return }`（保留 `locationServicesEnabled` 回写）时，两条用例仍 `Executed 2 tests, with 0 failures`。原因是 `beginUpdating()` 自带 `guard !isUpdating` 幂等保护，且用例里首轮 `start()` 已把 `isUpdating` 置真，删掉前置检查后再次 `start()` 不会二次调用 `startUpdatingLocation`。
   因此「服务关闭不得启动更新」这个语义在本用例里的**真实判红点**是 `RunPermissionAndDiagnosticsTests.swift:320` 的 `XCTAssertFalse(chain.source.locationServicesEnabled)` 与 `:321` 的 `unavailable` 断言；`:315-319` 的调用计数断言在当前实现下不能单独判红（注释里「去掉前置检查即必红」对该断言偏乐观）。本项按边界**不加新断言、不改产品代码**，只把该事实写进矩阵与本文。
2. **已知局限（公司记账接受，另项再议）**：`RunLocationReadiness.resolve` 先判 `servicesEnabled` / `lastErrorCode`、再判授权，`denied + 定位服务关闭` 会一律压成 `.unavailable` + `retry`，丢掉 `permissionDenied` 与「去系统设置」出口；本项不改判定顺序。

## 仓库零改动证明

```
$ git status --porcelain
?? .munk/changes/wi_intake_a443ff461a4b5787/
?? docs/evidence/wi_intake_a443ff461a4b5787/
$ git rev-parse HEAD
90bb205723fe95070b62ddfa3777a4cb80d0b05f
```

`/tmp` 副本在最后一次运行后已回滚为仓库原文：`diff -r --exclude .build --exclude .git --exclude .munk --exclude PurePace.xcodeproj --exclude dd --exclude logs <repo> <tmp 副本>` 仅打印 `Only in /tmp/.../repo/ios/RunCore: .swiftpm`（xcodegen 生成工程的副作用，源文件逐字节一致）。
