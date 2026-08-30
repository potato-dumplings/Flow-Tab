import SwiftUI

struct HomeRetainedTabPageDescriptor: Equatable {
    let identity: AnyHashable
    let contentRevision: AnyHashable
}

typealias HomeRetainedTabContentProvider = (
    HomeTab,
    HomeRetainedTabLifecycle
) -> AnyView

@MainActor
final class HomeRetainedTabPagePresentation: ObservableObject {
    struct Snapshot: Equatable {
        let contentRevision: AnyHashable
    }

    let tab: HomeTab
    let lifecycle: HomeRetainedTabLifecycle
    @Published private(set) var snapshot: Snapshot

    private var contentProvider: HomeRetainedTabContentProvider

    init(
        tab: HomeTab,
        lifecycle: HomeRetainedTabLifecycle,
        contentRevision: AnyHashable,
        contentProvider: @escaping HomeRetainedTabContentProvider
    ) {
        self.tab = tab
        self.lifecycle = lifecycle
        snapshot = Snapshot(
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
    func update(contentRevision: AnyHashable) -> Bool {
        let nextSnapshot = Snapshot(
            contentRevision: contentRevision
        )
        guard snapshot != nextSnapshot else { return false }
        snapshot = nextSnapshot
        return true
    }

    func content() -> AnyView {
        contentProvider(tab, lifecycle)
    }
}

@MainActor
struct HomeRetainedTabPageRoot: View {
    @ObservedObject var presentation: HomeRetainedTabPagePresentation

    var body: some View {
        presentation.content()
    }
}
