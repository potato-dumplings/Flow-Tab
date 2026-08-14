import Foundation

struct RuntimeWindowFilteredArtifactLogRecord: Equatable {
    enum Kind: String {
        case fullscreenHostArtifacts =
            "filtered-fullscreen-host-artifacts"
        case fullscreenSiblingArtifacts =
            "filtered-fullscreen-sibling-artifacts"
        case fullscreenDuplicateSurfaces =
            "filtered-fullscreen-duplicate-surfaces"
        case cgOnlyCoveredByActivation =
            "filtered-cg-only-covered-by-activation"
    }

    let appName: String
    let processIdentifier: pid_t
    let kind: Kind
    let stage: String
    let droppedCount: Int

    var logMessage: String {
        "\(appName) \(kind.rawValue) "
            + "stage=\(stage) dropped=\(droppedCount) "
            + "pid=\(processIdentifier)"
    }

    static func records(
        appName: String,
        kind: Kind,
        stage: String,
        droppedEntries: [RuntimeWindowListEntry]
    ) -> [Self] {
        Dictionary(grouping: droppedEntries, by: \.ownerPID)
            .filter { processIdentifier, _ in
                processIdentifier > 0
            }
            .sorted { lhs, rhs in
                lhs.key < rhs.key
            }
            .map { processIdentifier, entries in
                Self(
                    appName: appName,
                    processIdentifier: processIdentifier,
                    kind: kind,
                    stage: stage,
                    droppedCount: entries.count
                )
            }
    }

    static func publish(
        appName: String,
        kind: Kind,
        stage: String,
        droppedEntries: [RuntimeWindowListEntry]
    ) {
        records(
            appName: appName,
            kind: kind,
            stage: stage,
            droppedEntries: droppedEntries
        )
        .forEach {
            RuntimeLog.debug(.axMatch, $0.logMessage)
        }
    }
}
