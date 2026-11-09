import CoreLocation
import Foundation

/// 定位精度授权的纯数据镜像（`full` / `reduced`）。
enum RunLocationAccuracy: String, Sendable, Equatable {
    case full
    case reduced

    /// 与 `CLAccuracyAuthorization` 原始值一致的整数映射（遥测自证用）。
    var clRawValue: Int {
        switch self {
        case .full: return 0
        case .reduced: return 1
        }
    }

    init(_ accuracy: CLAccuracyAuthorization) {
        switch accuracy {
        case .fullAccuracy: self = .full
        case .reducedAccuracy: self = .reduced
        @unknown default: self = .reduced
        }
    }
}

/// 系统授权探针接缝：与采样源解耦，使 `-uiTestLocation` 下采样可为 `simulated`
/// 而授权仍反映系统真实值。
@MainActor
protocol SystemAuthorizationProbing: AnyObject {
    var authorizationStatus: RunLocationAuthorization { get }
    var accuracyAuthorization: RunLocationAccuracy { get }
}

/// 生产实现：直读进程内 `CLLocationManager` 的授权与精度状态。
@MainActor
final class SystemAuthorizationProbe: SystemAuthorizationProbing {
    private let manager: CLLocationManager

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
    }

    var authorizationStatus: RunLocationAuthorization {
        RunLocationAuthorization(status: manager.authorizationStatus)
    }

    var accuracyAuthorization: RunLocationAccuracy {
        RunLocationAccuracy(manager.accuracyAuthorization)
    }
}
