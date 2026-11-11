import XCTest
import PurePaceRunCore
@testable import PurePace

/// 用可抛错的假 loader 钉住 History 的读取结果映射、重试与单一导航路径收敛。
final class HistoryViewStateTests: XCTestCase {
    private struct LoadFailure: Error {}

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeRecord(offset: TimeInterval) -> RunRecord {
        RunRecord(
            startedAt: start.addingTimeInterval(offset),
            endedAt: start.addingTimeInterval(offset + 30),
            distance: RunDistance(meters: 300)!,
            activeDuration: 30,
            splits: [],
            samples: []
        )!
    }

    private func throwingLoader(_ error: Error) -> () throws -> [RunRecord] {
        { throw error }
    }

    private func recordsLoader(_ records: [RunRecord], calls: @escaping () -> Void = {}) -> () throws -> [RunRecord] {
        {
            calls()
            return records
        }
    }

    func testEmptyArchiveAndFailureAreDistinctStates() {
        var state = HistoryViewState()

        state.load(token: 0, using: recordsLoader([]))
        XCTAssertTrue(state.isEmpty)
        XCTAssertFalse(state.didFail)
        XCTAssertEqual(state.outcome, .loaded([]))

        state.load(token: 0, force: true, using: throwingLoader(LoadFailure()))
        XCTAssertTrue(state.didFail)
        XCTAssertFalse(state.isEmpty)
        XCTAssertEqual(state.outcome, .failed)
        XCTAssertNotEqual(HistoryLoadOutcome.loaded([]), HistoryLoadOutcome.failed)
    }

    func testRetryRecoversIntoRecords() {
        var state = HistoryViewState()
        let record = makeRecord(offset: 0)

        state.load(token: 0, using: throwingLoader(LoadFailure()))
        XCTAssertTrue(state.didFail)

        XCTAssertTrue(state.load(token: 0, force: true, using: recordsLoader([record])))
        XCTAssertFalse(state.didFail)
        XCTAssertEqual(state.records, [record])
        XCTAssertFalse(state.isEmpty)
    }

    func testRetryRecoversIntoEmptyState() {
        var state = HistoryViewState()

        state.load(token: 0, using: throwingLoader(LoadFailure()))
        XCTAssertTrue(state.didFail)

        XCTAssertTrue(state.load(token: 0, force: true, using: recordsLoader([])))
        XCTAssertFalse(state.didFail)
        XCTAssertTrue(state.isEmpty)
    }

    func testRetryAfterRepeatedFailureStaysFailedAndRetryable() {
        var state = HistoryViewState()

        state.load(token: 0, using: throwingLoader(LoadFailure()))
        state.load(token: 0, force: true, using: throwingLoader(LoadFailure()))
        XCTAssertTrue(state.didFail)

        XCTAssertTrue(state.shouldLoad(token: 0, force: true))
        XCTAssertTrue(state.load(token: 0, force: true, using: recordsLoader([makeRecord(offset: 0)])))
        XCTAssertFalse(state.didFail)
    }

    func testSameTokenLoadsOnceAcrossDrilldownAndBack() {
        var state = HistoryViewState()
        let records = [makeRecord(offset: 30), makeRecord(offset: 0)]
        var calls = 0
        let loader = recordsLoader(records) { calls += 1 }

        XCTAssertTrue(state.load(token: 0, using: loader))
        let orderBeforeDrilldown = state.records

        state.open(recordID: records[0].id)
        XCTAssertEqual(state.path, [records[0].id])
        state.popToRoot()
        XCTAssertEqual(state.path, [])

        // 返回列表根时再次触发读取：同一 token 必须被守卫拦下。
        XCTAssertFalse(state.load(token: 0, using: loader))
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(state.records, orderBeforeDrilldown)

        // 刷新令牌变化时再读一次。
        XCTAssertTrue(state.load(token: 1, using: loader))
        XCTAssertEqual(calls, 2)
    }

    func testRefreshClearsStaleDetailAndKeepsExistingDetail() {
        var state = HistoryViewState()
        let kept = makeRecord(offset: 0)
        let removed = makeRecord(offset: 30)

        state.load(token: 0, using: recordsLoader([removed, kept]))
        state.open(recordID: kept.id)
        state.load(token: 1, using: recordsLoader([kept]))
        XCTAssertEqual(state.path, [kept.id])

        state.load(token: 2, using: recordsLoader([kept]))
        state.open(recordID: removed.id)
        XCTAssertEqual(state.path, [removed.id])
        state.load(token: 3, using: recordsLoader([kept]))
        XCTAssertEqual(state.path, [])
    }

    func testRunAgainClearsPathAndPreservesLoadedRecords() {
        var state = HistoryViewState()
        let records = [makeRecord(offset: 0)]
        state.load(token: 0, using: recordsLoader(records))
        state.open(recordID: records[0].id)
        XCTAssertEqual(state.path, [records[0].id])

        // 空态 CTA：只清空 History 导航路径；state 不持有任何运行会话命令。
        state.popToRoot()
        XCTAssertEqual(state.path, [])
        XCTAssertEqual(state.records, records)
        XCTAssertFalse(state.didFail)
        XCTAssertFalse(state.isEmpty)
    }

    func testFailureClearsOpenDetailPath() {
        var state = HistoryViewState()
        let record = makeRecord(offset: 0)

        state.load(token: 0, using: recordsLoader([record]))
        state.open(recordID: record.id)
        XCTAssertEqual(state.path, [record.id])

        state.load(token: 1, using: throwingLoader(LoadFailure()))
        XCTAssertTrue(state.didFail)
        XCTAssertEqual(state.path, [])
    }

    func testAutoOpenFirstDetailRunsOnlyOnce() {
        var state = HistoryViewState()
        let first = makeRecord(offset: 30)
        let second = makeRecord(offset: 0)

        state.load(token: 0, using: recordsLoader([first, second]))
        state.openFirstDetailIfNeeded(autoOpen: true)
        XCTAssertEqual(state.path, [first.id])

        state.popToRoot()
        state.openFirstDetailIfNeeded(autoOpen: true)
        XCTAssertEqual(state.path, [])

        state.openFirstDetailIfNeeded(autoOpen: false)
        XCTAssertEqual(state.path, [])
    }
}
