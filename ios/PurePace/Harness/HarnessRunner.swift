import Foundation
import PurePaceRunCore

/// 无 UI Harness 的纯 Foundation 编排：direct 流回放与 resume 恢复。
/// CoreLocation 模式的平台适配在 `HarnessLocationSource.swift`，同样只消费 `HarnessCore`。
struct HarnessRunner: Sendable {
    let configuration: HarnessConfiguration

    @discardableResult
    func run() -> HarnessStatus {
        switch configuration.mode {
        case .direct:
            return runDirect()
        case .resume:
            return runResume()
        case .corelocation:
            // 该模式的驱动在平台适配器；这里只产出初始 status，便于下游尽早可观测。
            let core = HarnessCore(
                mode: .corelocation,
                checkpointStore: RunCheckpointStore(fileURL: configuration.checkpointURL),
                appendsCheckpoints: true
            )
            return persist(core.status())
        }
    }

    // MARK: - direct

    private func runDirect() -> HarnessStatus {
        var core = HarnessCore(
            mode: .direct,
            checkpointStore: RunCheckpointStore(fileURL: configuration.checkpointURL),
            appendsCheckpoints: true
        )
        guard let streamURL = configuration.streamURL else {
            core.recordError(code: "missingArgument", message: "direct 模式缺少 --stream")
            return persist(core.status())
        }
        let contents: String
        do {
            contents = try String(contentsOf: streamURL, encoding: .utf8)
        } catch {
            core.recordError(
                code: "streamUnreadable",
                message: "无法读取 JSONL 直接流: \(error.localizedDescription)"
            )
            return persist(core.status())
        }

        _ = persist(core.status())
        var lineNumber = 0
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            lineNumber += 1
            if core.isFinished {
                break
            }
            do {
                guard let event = try HarnessStreamParser.parse(line: String(rawLine), lineNumber: lineNumber) else {
                    continue
                }
                apply(event, to: &core)
            } catch let streamError as HarnessStreamError {
                core.recordError(code: streamError.code, message: streamError.message)
                break
            } catch {
                core.recordError(
                    code: HarnessStreamParser.invalidLineCode,
                    message: "第 \(lineNumber) 行: \(error.localizedDescription)"
                )
                break
            }
            _ = persist(core.status())
        }
        return persist(core.status())
    }

    private func apply(_ event: HarnessStreamEvent, to core: inout HarnessCore) {
        switch event {
        case let .start(date):
            core.start(at: date)
        case let .pause(date):
            core.pause(at: date)
        case let .resume(date):
            core.resume(at: date)
        case let .finish(date):
            core.finish(at: date)
        case let .sample(sample):
            core.ingest(sample.sample, accuracyMeters: sample.accuracyMeters)
        }
    }

    // MARK: - resume

    private func runResume() -> HarnessStatus {
        let store = RunCheckpointStore(fileURL: configuration.checkpointURL)
        do {
            if let checkpoint = try store.loadLatest() {
                let core = HarnessCore(
                    resuming: checkpoint,
                    checkpointPath: configuration.checkpointURL.path
                )
                return persist(core.status())
            }
            var core = emptyResumeCore()
            core.recordError(
                code: "checkpointMissing",
                message: "未找到可用 checkpoint: \(configuration.checkpointURL.path)"
            )
            return persist(core.status())
        } catch {
            var core = emptyResumeCore()
            core.recordError(
                code: "checkpointMissing",
                message: "checkpoint 无法读取: \(error.localizedDescription)"
            )
            return persist(core.status())
        }
    }

    private func emptyResumeCore() -> HarnessCore {
        HarnessCore(mode: .resume, checkpointStore: nil, appendsCheckpoints: false)
    }

    @discardableResult
    private func persist(_ status: HarnessStatus) -> HarnessStatus {
        try? HarnessStatusWriter.write(status, to: configuration.statusURL)
        return status
    }
}

/// 参数失败时也要写出可观测 error status（有 `--status` 时）。
enum HarnessBootstrap {
    @discardableResult
    static func writeArgumentFailure(_ activation: HarnessActivation) -> HarnessStatus? {
        guard case let .invalid(mode, statusURL, error) = activation, let statusURL else {
            return nil
        }
        let status = HarnessStatus.failure(
            mode: mode?.rawValue,
            error: HarnessStatusError(code: error.code, message: error.message)
        )
        try? HarnessStatusWriter.write(status, to: statusURL)
        return status
    }
}
