import SwiftUI

struct HomeRetainedTabPageDescriptor: Equatable {
    let identity: AnyHashable
    let contentRevision: AnyHashable
}

typealias HomeRetainedTabContentProvider = (HomeTab, Bool) -> AnyView

@MainActor
final class HomeRetainedTabPagePresentation: ObservableObject {
    struct Snapshot: Equatable {
        let isActive: Bool
        let contentRevision: AnyHashable
    }

    let tab: HomeTab
    @Published private(set) var snapshot: Snapshot

    private var contentProvider: HomeRetainedTabContentProvider

    init(
        tab: HomeTab,
        isActive: Bool,
        contentRevision: AnyHashable,
        contentProvider: @escaping HomeRetainedTabContentProvider
    ) {
        self.tab = tab
        snapshot = Snapshot(
            isActive: isActive,
            contentRevision: contentRevision
        )
        self.contentProvider = contentProvider
    }

    func updateContentProvider(
        _ contentProvider: @escaping HomeRetainedTabContentProvider
    ) {
        self.contentProvider = contentProvider
    }

    @discardableResult
    func update(
        isActive: Bool,
        contentRevision: AnyHashable
    ) -> Bool {
        let nextSnapshot = Snapshot(
            isActive: isActive,
            contentRevision: contentRevision
        )
        guard snapshot != nextSnapshot else { return false }
        snapshot = nextSnapshot
        return true
    }

    func content() -> AnyView {
        contentProvider(tab, snapshot.isActive)
    }
}

@MainActor
struct HomeRetainedTabPageRoot: View {
    @ObservedObject var presentation: HomeRetainedTabPagePresentation

    var body: some View {
        presentation.content()
    }
}
