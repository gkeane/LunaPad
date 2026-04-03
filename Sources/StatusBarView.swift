import SwiftUI

struct StatusBarView: View {
    @AppStorage("showLineNumbers") private var showLineNumbers: Bool = false
    var cursorPosition: CursorPosition
    var isLargeDocument: Bool = false
    var canToggleLineNumbers: Bool = true

    var body: some View {
        HStack(spacing: 18) {
            Text("Characters: \(cursorPosition.totalCharacters)")
            Text("Location: \(cursorPosition.location)")

            if isLargeDocument {
                Text("Large File Mode")
                if cursorPosition.totalLines > 0 {
                    Text("Loaded Lines: \(cursorPosition.totalLines)")
                }
                if cursorPosition.line > 0 {
                    Text("Line: \(cursorPosition.line)")
                }
            } else {
                Text("Lines: \(cursorPosition.totalLines)")
                Text("Line: \(cursorPosition.line)")
            }

            Spacer()

            Button(action: { showLineNumbers.toggle() }) {
                Image(systemName: "list.number")
                    .font(.system(size: 11, weight: showLineNumbers ? .semibold : .regular))
                    .foregroundStyle(
                        canToggleLineNumbers
                        ? (showLineNumbers ? Color.accentColor : Color.secondary)
                        : Color.secondary.opacity(0.55)
                    )
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(!canToggleLineNumbers)
            .help(
                canToggleLineNumbers
                ? (showLineNumbers ? "Hide line numbers" : "Show line numbers")
                : "Line numbers are unavailable in chunked safe mode"
            )
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { Divider() }
    }
}
