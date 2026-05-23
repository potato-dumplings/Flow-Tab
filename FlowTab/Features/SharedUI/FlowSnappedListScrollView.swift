import SwiftUI

enum FlowSnappedListLayout {
    static let defaultMinHeight: CGFloat = 180
}

struct FlowSnappedListScrollView<Rows: View>: View {
    let rowCount: Int
    let rowHeight: CGFloat
    let rowSpacing: CGFloat
    let minHeight: CGFloat
    let accessibilityIdentifier: String
    let rows: Rows

    init(
        rowCount: Int,
        rowHeight: CGFloat,
        rowSpacing: CGFloat = 0,
        minHeight: CGFloat = FlowSnappedListLayout.defaultMinHeight,
        accessibilityIdentifier: String,
        @ViewBuilder rows: () -> Rows
    ) {
        self.rowCount = rowCount
        self.rowHeight = rowHeight
        self.rowSpacing = rowSpacing
        self.minHeight = minHeight
        self.accessibilityIdentifier = accessibilityIdentifier
        self.rows = rows()
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: rowSpacing) {
                        rows
                    }
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.visible)
                .accessibilityIdentifier(accessibilityIdentifier)
                .frame(maxWidth: .infinity)
                .frame(height: viewportHeight(for: proxy.size.height))

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity)
    }

    private var contentHeight: CGFloat {
        guard rowCount > 0 else { return 0 }
        return CGFloat(rowCount) * rowHeight
            + CGFloat(max(0, rowCount - 1)) * rowSpacing
    }

    private func viewportHeight(for availableHeight: CGFloat) -> CGFloat {
        let availableHeight = max(0, availableHeight)
        guard rowCount > 0, availableHeight > 0 else { return 0 }

        let rowStride = rowHeight + rowSpacing
        guard rowStride > 0 else { return 0 }

        let visibleRowCount = max(
            1,
            Int(floor((availableHeight + rowSpacing) / rowStride))
        )
        let snappedHeight = CGFloat(visibleRowCount) * rowHeight
            + CGFloat(max(0, visibleRowCount - 1)) * rowSpacing

        return min(contentHeight, min(snappedHeight, availableHeight))
    }
}
