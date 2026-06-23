import Foundation

let runtimeSearchFreshnessBarrierMaxReadyRepairs = 4

enum RuntimeProjectionMaintenanceReason: String, Sendable {
    case switcherSessionStarted
    case appLifecycleRefresh
    case homeProjectionMissing
    case searchFreshnessBarrier
}
