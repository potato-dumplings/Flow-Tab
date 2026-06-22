final class RuntimeProjectionRepairProvider: RuntimeProjectionRepairProviding {
    let snapshotProvider: RuntimeSnapshotProvider

    init(snapshotProvider: RuntimeSnapshotProvider = RuntimeSnapshotProvider()) {
        self.snapshotProvider = snapshotProvider
    }
}
