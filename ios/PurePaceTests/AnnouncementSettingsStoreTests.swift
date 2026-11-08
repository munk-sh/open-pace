import XCTest
@testable import PurePace

@MainActor
final class AnnouncementSettingsStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "PurePaceAnnouncementSettings-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testFreshDomainDefaultsToEnabled() {
        let store = AnnouncementSettingsStore(defaults: defaults)
        XCTAssertTrue(store.isEnabled)
    }

    func testDisabledStatePersistsAcrossInstances() {
        let store = AnnouncementSettingsStore(defaults: defaults)
        store.setEnabled(false)
        XCTAssertFalse(store.isEnabled)

        let reloaded = AnnouncementSettingsStore(defaults: defaults)
        XCTAssertFalse(reloaded.isEnabled)
    }

    func testEnabledStatePersistsAcrossInstances() {
        let store = AnnouncementSettingsStore(defaults: defaults)
        store.setEnabled(false)
        store.setEnabled(true)

        let reloaded = AnnouncementSettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.isEnabled)
    }

    func testBindingStyleWritesPersistToo() {
        let store = AnnouncementSettingsStore(defaults: defaults)
        store.isEnabled = false

        XCTAssertEqual(defaults.object(forKey: AnnouncementSettingsStore.enabledKey) as? Bool, false)
        XCTAssertFalse(AnnouncementSettingsStore(defaults: defaults).isEnabled)
    }

    func testOnlySingleConstantKeyIsWritten() {
        let store = AnnouncementSettingsStore(defaults: defaults)
        store.setEnabled(false)
        store.setEnabled(true)

        let domain = defaults.persistentDomain(forName: suiteName) ?? [:]
        let keys = Set(domain.keys)
        XCTAssertEqual(keys, [AnnouncementSettingsStore.enabledKey])
    }
}
