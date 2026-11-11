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

    private func makeSummary(offset: TimeInterval) -> RunRecordSummary {
        RunRecordSummary(record: makeRecord(offset: offset))
    }

    private func throwingLoader(_ error: Error) -> () throws -> [RunRecordSummary] {
        { throw error }
    }

    private func summariesLoader(_ summaries: [RunRecordSummary], calls: @escaping () -> Void = {}) -> () throws -> [RunRecordSummary] {
        {
            calls()
            return summaries
        }
    }

    func testEmptyArchiveAndFailureAreDistinctStates() {
        var state = HistoryViewState()

        state.load(token: 0, using: summariesLoader([]))
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
        let summary = makeSummary(offset: 0)

        state.load(token: 0, using: throwingLoader(LoadFailure()))
        XCTAssertTrue(state.didFail)

        XCTAssertTrue(state.load(token: 0, force: true, using: summariesLoader([summary])))
        XCTAssertFalse(state.didFail)
        XCTAssertEqual(state.summaries, [summary])
        XCTAssertFalse(state.isEmpty)
    }

    func testRetryRecoversIntoEmptyState() {
        var state = HistoryViewState()

        state.load(token: 0, using: throwingLoader(LoadFailure()))
        XCTAssertTrue(state.didFail)

        XCTAssertTrue(state.load(token: 0, force: true, using: summariesLoader([])))
        XCTAssertFalse(state.didFail)
        XCTAssertTrue(state.isEmpty)
    }

    func testRetryAfterRepeatedFailureStaysFailedAndRetryable() {
        var state = HistoryViewState()

        state.load(token: 0, using: throwingLoader(LoadFailure()))
        state.load(token: 0, force: true, using: throwingLoader(LoadFailure()))
        XCTAssertTrue(state.didFail)

        XCTAssertTrue(state.shouldLoad(token: 0, force: true))
        XCTAssertTrue(state.load(token: 0, force: true, using: summariesLoader([makeSummary(offset: 0)])))
        XCTAssertFalse(state.didFail)
    }

    func testSameTokenLoadsOnceAcrossDrilldownAndBack() {
        var state = HistoryViewState()
        let summaries = [makeSummary(offset: 30), makeSummary(offset: 0)]
        var calls = 0
        let loader = summariesLoader(summaries) { calls += 1 }

        XCTAssertTrue(state.load(token: 0, using: loader))
        let orderBeforeDrilldown = state.summaries

        state.open(recordID: summaries[0].id)
        XCTAssertEqual(state.path, [summaries[0].id])
        state.popToRoot()
        XCTAssertEqual(state.path, [])

        // 返回列表根时再次触发读取：同一 token 必须被守卫拦下。
        XCTAssertFalse(state.load(token: 0, using: loader))
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(state.summaries, orderBeforeDrilldown)

        // 刷新令牌变化时再读一次。
        XCTAssertTrue(state.load(token: 1, using: loader))
        XCTAssertEqual(calls, 2)
    }

    func testRefreshClearsStaleDetailAndKeepsExistingDetail() {
        var state = HistoryViewState()
        let kept = makeSummary(offset: 0)
        let removed = makeSummary(offset: 30)

        state.load(token: 0, using: summariesLoader([removed, kept]))
        state.open(recordID: kept.id)
        state.load(token: 1, using: summariesLoader([kept]))
        XCTAssertEqual(state.path, [kept.id])

        state.load(token: 2, using: summariesLoader([kept]))
        state.open(recordID: removed.id)
        XCTAssertEqual(state.path, [removed.id])
        state.load(token: 3, using: summariesLoader([kept]))
        XCTAssertEqual(state.path, [])
    }

    func testRunAgainClearsPathAndPreservesLoadedRecords() {
        var state = HistoryViewState()
        let summaries = [makeSummary(offset: 0)]
        state.load(token: 0, using: summariesLoader(summaries))
        state.open(recordID: summaries[0].id)
        XCTAssertEqual(state.path, [summaries[0].id])

        // 空态 CTA：只清空 History 导航路径；state 不持有任何运行会话命令。
        state.popToRoot()
        XCTAssertEqual(state.path, [])
        XCTAssertEqual(state.summaries, summaries)
        XCTAssertFalse(state.didFail)
        XCTAssertFalse(state.isEmpty)
    }

    func testFailureClearsOpenDetailPath() {
        var state = HistoryViewState()
        let summary = makeSummary(offset: 0)

        state.load(token: 0, using: summariesLoader([summary]))
        state.open(recordID: summary.id)
        XCTAssertEqual(state.path, [summary.id])

        state.load(token: 1, using: throwingLoader(LoadFailure()))
        XCTAssertTrue(state.didFail)
        XCTAssertEqual(state.path, [])
    }

    func testAutoOpenFirstDetailRunsOnlyOnce() {
        var state = HistoryViewState()
        let first = makeSummary(offset: 30)
        let second = makeSummary(offset: 0)

        state.load(token: 0, using: summariesLoader([first, second]))
        state.openFirstDetailIfNeeded(autoOpen: true)
        XCTAssertEqual(state.path, [first.id])

        state.popToRoot()
        state.openFirstDetailIfNeeded(autoOpen: true)
        XCTAssertEqual(state.path, [])

        state.openFirstDetailIfNeeded(autoOpen: false)
        XCTAssertEqual(state.path, [])
    }
}
