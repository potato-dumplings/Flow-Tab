import AppKit
import FlowTabCore

extension LiveSwitcherModel {
    enum TerminateSelectedAppResult {
        case notHandled
        case updatedSession
        case sessionEnded
    }

    struct PendingTerminateRequest: Equatable {
        struct AppInstanceIdentity: Equatable {
            let appID: String
            let pid: pid_t
            let generation: UInt64

            func matchesTerminatedInstance(appID: String, pid: pid_t) -> Bool {
                self.appID == appID && self.pid == pid
            }
        }

        let appInstance: AppInstanceIdentity
        let preferredSelectedAppID: String?

        var appID: String {
            appInstance.appID
        }

        var pid: pid_t {
            appInstance.pid
        }

        var generation: UInt64 {
            appInstance.generation
        }

        init(
            appID: String,
            pid: pid_t,
            generation: UInt64,
            preferredSelectedAppID: String?
        ) {
            appInstance = AppInstanceIdentity(
                appID: appID,
                pid: pid,
                generation: generation
            )
            self.preferredSelectedAppID = preferredSelectedAppID
        }

        func matchesTerminatedInstance(appID: String, pid: pid_t) -> Bool {
            appInstance.matchesTerminatedInstance(appID: appID, pid: pid)
        }
    }

    enum ProjectionInvalidationReason: String, Equatable {
        case startSession
        case startFocusedWindowSession
        case commitSelection
        case resetSession
        case resetRuntimeState
        case explicitRuntimeProjectionMaintenanceInvalidation
        case explicitSelectedAppWindowProjectionInvalidation
    }

    enum ProjectionInvalidationScope: String, Equatable {
        case runtimeProjectionMaintenance
        case selectedAppWindowProjection
    }

    struct ProjectionInvalidationRecord: Equatable {
        let reason: ProjectionInvalidationReason
        let scope: ProjectionInvalidationScope
        let maintenanceGeneration: UInt64
        let selectedAppWindowProjectionGeneration: UInt64
        let clearedDeferredMaintenanceRequest: Bool

        var logMessage: String {
            [
                "projectionInvalidation",
                "scope=\(scope.rawValue)",
                "reason=\(reason.rawValue)",
                "maintenanceGeneration=\(maintenanceGeneration)",
                "selectedAppWindowProjectionGeneration=\(selectedAppWindowProjectionGeneration)",
                "clearedDeferredMaintenanceRequest=\(clearedDeferredMaintenanceRequest ? 1 : 0)"
            ].joined(separator: " ")
        }
    }

    struct RuntimeProjectionMaintenanceDiagnostic: Equatable {
        let result: String
        let generation: UInt64
        let currentGeneration: UInt64
        let reason: ProjectionInvalidationReason
        let trigger: String
        let applyGeneration: UInt64?
        let totalMs: String

        var logMessage: String {
            [
                "runtimeProjectionMaintenance",
                "result=\(result)",
                "generation=\(generation)",
                "currentGeneration=\(currentGeneration)",
                "reason=\(reason.rawValue)",
                "trigger=\(trigger)",
                "applyGeneration=\(applyGeneration.map(String.init) ?? "nil")",
                "totalMs=\(totalMs)"
            ].joined(separator: " ")
        }
    }

    struct AppSwitcherSessionLoadDiagnostic: Equatable {
        let result: String
        let event: String
        let trigger: String
        let appCount: Int
        let windowCount: Int
        let projectionMs: Double
        let recencyMs: Double
        let sessionBuildMs: Double
        let indexMs: Double
        let publishMs: Double

        var totalMs: Double {
            projectionMs
                + recencyMs
                + sessionBuildMs
                + indexMs
                + publishMs
        }
    }

    struct AppSwitcherSessionStartDiagnostic: Equatable {
        let result: String
        let directoryRefreshMs: Double
        let invalidationMs: Double
        let stateResetMs: Double
        let projectionLoadMs: Double
        let maintenanceRequestMs: Double

        var totalMs: Double {
            directoryRefreshMs
                + invalidationMs
                + stateResetMs
                + projectionLoadMs
                + maintenanceRequestMs
        }
    }

    struct SearchIndexReadDiagnostic: Equatable {
        let reason: String
        let readiness: RuntimeSearchIndexReadiness
        let resultState: RuntimeSearchIndexResultState
        let appCount: Int
        let windowCount: Int
        let committedIndexCoversCurrentGeneration: Bool
        let dirtyAppCount: Int
        let dirtyPIDCount: Int
        let dirtyCGWindowIDCount: Int
        let pendingRepairScopeCount: Int
        let requestedFreshnessBarrier: Bool

        var searchTraceFields: String {
            [
                "searchIndexReadiness=\(readiness.rawValue)",
                "searchIndexResultState=\(resultState.rawValue)",
                "searchIndexDegraded=\(resultState == .degradedStaleCommittedResult ? 1 : 0)",
                "searchIndexCoversCurrentGeneration=\(committedIndexCoversCurrentGeneration ? 1 : 0)",
                "searchFreshnessBarrierRequested=\(requestedFreshnessBarrier ? 1 : 0)"
            ].joined(separator: " ")
        }

        var logMessage: String {
            [
                "searchIndexSource",
                "reason=\(reason)",
                "source=committedRuntimeIndex",
                "readiness=\(readiness.rawValue)",
                "resultState=\(resultState.rawValue)",
                "apps=\(appCount)",
                "windows=\(windowCount)",
                "committedIndexCoversCurrentGeneration=\(committedIndexCoversCurrentGeneration ? 1 : 0)",
                "degraded=\(resultState == .degradedStaleCommittedResult ? 1 : 0)",
                "dirtyApps=\(dirtyAppCount)",
                "dirtyPIDs=\(dirtyPIDCount)",
                "dirtyCGWindowIDs=\(dirtyCGWindowIDCount)",
                "pendingScopes=\(pendingRepairScopeCount)",
                "freshnessBarrierRequested=\(requestedFreshnessBarrier ? 1 : 0)"
            ].joined(separator: " ")
        }
    }

    struct SearchResultPublicationDiagnostic: Equatable {
        let query: String
        let debounceMilliseconds: Double
        let computationMilliseconds: Double
        let publishedAtMilliseconds: Double
    }

}
