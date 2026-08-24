public struct ApplicationDirectoryMembership: Equatable, Sendable {
    public let directoryAppIDs: Set<String>
    public let switcherEligibleAppIDs: Set<String>

    public init(
        directoryAppIDs: Set<String>,
        switcherEligibleAppIDs: Set<String>
    ) {
        self.directoryAppIDs = directoryAppIDs
        self.switcherEligibleAppIDs = switcherEligibleAppIDs.intersection(directoryAppIDs)
    }

    public func requiredExistingSwitcherAppIDs(
        existingAppIDs: Set<String>,
        permittedMissingAppIDs: Set<String> = []
    ) -> Set<String> {
        existingAppIDs
            .intersection(switcherEligibleAppIDs)
            .subtracting(permittedMissingAppIDs)
    }
}
