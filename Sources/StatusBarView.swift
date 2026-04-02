import SwiftUI

struct StatusBarView: View {
    var cursorPosition: CursorPosition

    var body: some View {
        HStack {
            Spacer()
            Text("Ln \(cursorPosition.line), Col \(cursorPosition.col)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
        }
        .background(.bar)
    }
}
