import SwiftUI
import AppKit

struct ContentView: View {
    @Binding var document: NoteDocument
    @AppStorage("wordWrap") private var wordWrap: Bool = true
    @AppStorage("fontName") private var fontName: String = "Menlo"
    @AppStorage("fontSize") private var fontSize: Double = 13
    @State private var cursorPosition = CursorPosition()
    @State private var selectedRange: NSRange?

    private var editorFont: NSFont {
        NSFont(name: fontName, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    var body: some View {
        VStack(spacing: 0) {
            NoteTextEditor(
                text: $document.text,
                wordWrap: wordWrap,
                font: editorFont,
                cursorPosition: $cursorPosition,
                selectedRange: $selectedRange
            )
            Divider()
            StatusBarView(cursorPosition: cursorPosition)
        }
        .onReceive(NotificationCenter.default.publisher(for: .fontChanged)) { note in
            if let font = note.object as? NSFont {
                fontName = font.fontName
                fontSize = Double(font.pointSize)
            }
        }
    }
}
