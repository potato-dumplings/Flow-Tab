#if FLOWTAB_TESTING
import Foundation
import FlowTabCore

struct RuntimeFullRepairProjectionPayload {
    let apps: [AppSwitchCandidate]
    let contextsByID: [String: RuntimeAppContext]
    let appDirectoryEntries: [RuntimeAppDirectoryEntry]

    init(
        apps: [AppSwitchCandidate],
        contextsByID: [String: RuntimeAppContext],
        appDirectoryEntries: [RuntimeAppDirectoryEntry]
    ) {
        self.apps = apps
        self.contextsByID = contextsByID
        self.appDirectoryEntries = appDirectoryEntries
    }
}

enum RuntimeFullRepairProjectionAssembler {
    static func payload(
        fromCurrentAppWindowProjectionInputs inputs: [RuntimeCurrentAppWindowProjectionAssemblyInput],
        appDirectoryEntries: [RuntimeAppDirectoryEntry],
        duplicateContextHandler: ((String) -> Void)? = nil
    ) -> RuntimeFullRepairProjectionPayload {
        payload(
            fromCurrentAppWindowPayloads: inputs.map(RuntimeCurrentAppWindowPayload.init(assemblyInput:)),
            appDirectoryEntries: appDirectoryEntries,
            duplicateContextHandler: duplicateContextHandler
        )
    }

    private static func payload(
        fromCurrentAppWindowPayloads currentAppWindowPayloads: [RuntimeCurrentAppWindowPayload],
        appDirectoryEntries: [RuntimeAppDirectoryEntry],
        duplicateContextHandler: ((String) -> Void)? = nil
    ) -> RuntimeFullRepairProjectionPayload {
        let rows = currentAppWindowPayloads
            .map { payload in
                (candidate: payload.candidate, context: payload.context)
            }
            .sorted { lhs, rhs in
                if lhs.candidate.lastActiveAt == rhs.candidate.lastActiveAt {
                    return lhs.candidate.displayName.localizedCaseInsensitiveCompare(
                        rhs.candidate.displayName
                    ) == .orderedAscending
                }
                return lhs.candidate.lastActiveAt > rhs.candidate.lastActiveAt
            }

        var contextsByID: [String: RuntimeAppContext] = [:]
        for row in rows {
            if contextsByID[row.context.appID] != nil {
                duplicateContextHandler?(row.context.appID)
            }
            contextsByID[row.context.appID] = row.context
        }

        return RuntimeFullRepairProjectionPayload(
            apps: rows.map(\.candidate),
            contextsByID: contextsByID,
            appDirectoryEntries: appDirectoryEntries
        )
    }
}
#endif
