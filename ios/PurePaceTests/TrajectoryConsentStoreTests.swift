import XCTest
@testable import PurePace

@MainActor
final class TrajectoryConsentStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "PurePaceTrajectoryConsent-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    /// 未同意 → 同意屏存在且开始按钮 disabled 的存储侧前提：缺省即未同意。
    func testFreshDomainDefaultsToNotConsented() {
        let store = TrajectoryConsentStore(defaults: defaults)
        XCTAssertFalse(store.hasConsented, "无同意记录时必须为未同意态")
    }

    /// 同意后 → 可开始（键值读写往返一致）。
    func testGrantPersistsAcrossInstances() {
        let store = TrajectoryConsentStore(defaults: defaults)
        store.grant()
        XCTAssertTrue(store.hasConsented)
        XCTAssertEqual(defaults.object(forKey: TrajectoryConsentStore.consentKey) as? Bool, true)

        let reloaded = TrajectoryConsentStore(defaults: defaults)
        XCTAssertTrue(reloaded.hasConsented, "同意态必须冷启动回读")
    }

    /// 撤回后 → 回到未同意态且不可开始。
    func testRevokeRestoresNotConsented() {
        let store = TrajectoryConsentStore(defaults: defaults)
        store.grant()
        store.revoke()
        XCTAssertFalse(store.hasConsented)
        XCTAssertEqual(defaults.object(forKey: TrajectoryConsentStore.consentKey) as? Bool, false)

        let reloaded = TrajectoryConsentStore(defaults: defaults)
        XCTAssertFalse(reloaded.hasConsented, "撤回必须落盘，冷启动仍为未同意")
    }

    /// 点「不同意」不写同意：本用例模拟拒绝路径（不调用 store 写方法），域内不得出现同意键。
    func testDeclineDoesNotWriteConsent() {
        _ = TrajectoryConsentStore(defaults: defaults)
        let domain = defaults.persistentDomain(forName: suiteName) ?? [:]
        XCTAssertNil(domain[TrajectoryConsentStore.consentKey])
    }

    /// 单一键：同意态只落一个 key（写入第二个 key 即判红）。
    func testOnlySingleConstantKeyIsWritten() {
        let store = TrajectoryConsentStore(defaults: defaults)
        store.grant()
        store.revoke()
        store.grant()

        let domain = defaults.persistentDomain(forName: suiteName) ?? [:]
        XCTAssertEqual(Set(domain.keys), [TrajectoryConsentStore.consentKey])
    }

    /// 反例保护：缺省值绝不能被当成「已同意」（把门拆掉 / 把键读成默认 true 必红）。
    func testMissingKeyIsNeverConsented() {
        defaults.set(false, forKey: TrajectoryConsentStore.consentKey)
        XCTAssertFalse(TrajectoryConsentStore(defaults: defaults).hasConsented)

        defaults.removeObject(forKey: TrajectoryConsentStore.consentKey)
        XCTAssertFalse(TrajectoryConsentStore(defaults: defaults).hasConsented)
    }

    func testUITestArgumentsResetThenGrant() {
        defaults.set(true, forKey: TrajectoryConsentStore.consentKey)
        TrajectoryConsentStore.applyUITestArguments(
            [RunLaunchArguments.uiTestResetConsentFlag],
            defaults: defaults
        )
        XCTAssertFalse(TrajectoryConsentStore(defaults: defaults).hasConsented)

        TrajectoryConsentStore.applyUITestArguments(
            [RunLaunchArguments.uiTestConsentGrantedFlag],
            defaults: defaults
        )
        XCTAssertTrue(TrajectoryConsentStore(defaults: defaults).hasConsented)
    }

    func testUITestResetWinsOverGrant() {
        TrajectoryConsentStore.applyUITestArguments(
            [
                RunLaunchArguments.uiTestConsentGrantedFlag,
                RunLaunchArguments.uiTestResetConsentFlag
            ],
            defaults: defaults
        )
        XCTAssertFalse(TrajectoryConsentStore(defaults: defaults).hasConsented)
    }
}
