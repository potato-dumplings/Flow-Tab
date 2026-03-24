import SwiftUI
import AppKit

struct ContentView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .underPageBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 10) {
                Text("FlowTab")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("应用在后台运行，按 Option + Tab 呼出切换面板")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 420, minHeight: 240)
    }
}
