import AppKit
import SwiftUI

struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    var wordWrap: Bool
    var font: NSFont
    @Binding var cursorPosition: CursorPosition
    @Binding var selectedRange: NSRange?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = font
        textView.string = text

        applyWordWrap(textView: textView, scrollView: scrollView, wordWrap: wordWrap)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            let saved = textView.selectedRange()
            context.coordinator.ignoreChanges = true
            textView.string = text
            context.coordinator.ignoreChanges = false
            let safe = NSRange(location: min(saved.location, text.count), length: 0)
            textView.setSelectedRange(safe)
        }

        if textView.font != font {
            textView.font = font
        }

        if let selectedRange, textView.selectedRange() != selectedRange {
            textView.setSelectedRange(selectedRange)
            textView.scrollRangeToVisible(selectedRange)
        }

        applyWordWrap(textView: textView, scrollView: scrollView, wordWrap: wordWrap)
    }

    private func applyWordWrap(textView: NSTextView, scrollView: NSScrollView, wordWrap: Bool) {
        if wordWrap {
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = CGSize(
                width: scrollView.contentSize.width,
                height: .greatestFiniteMagnitude
            )
            textView.isHorizontallyResizable = false
            scrollView.hasHorizontalScroller = false
        } else {
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.isHorizontallyResizable = true
            scrollView.hasHorizontalScroller = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextEditor
        var ignoreChanges = false

        init(_ parent: NoteTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !ignoreChanges, let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            updateCursor(textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.selectedRange = textView.selectedRange()
            updateCursor(textView)
        }

        private func updateCursor(_ textView: NSTextView) {
            let location = textView.selectedRange().location
            let string = textView.string
            guard location <= string.count else { return }
            let prefix = String(string.prefix(location))
            let lines = prefix.components(separatedBy: "\n")
            parent.cursorPosition = CursorPosition(
                line: lines.count,
                col: (lines.last?.count ?? 0) + 1
            )
        }
    }
}

struct CursorPosition: Equatable {
    var line: Int = 1
    var col: Int = 1
}
