import AppKit
import SwiftUI

struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    var wordWrap: Bool
    var font: NSFont
    @Binding var cursorPosition: CursorPosition
    @Binding var selectedRange: NSRange?
    var searchMatches: [NSRange]
    var currentSearchMatch: NSRange?

    func makeNSView(context: Context) -> EditorContainerView {
        let container = EditorContainerView()
        let textView = container.textView

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

        container.updateGutter(
            textLength: text.utf16.count,
            searchMatches: searchMatches,
            currentSearchMatch: currentSearchMatch
        )
        applyWordWrap(textView: textView, scrollView: container.scrollView, wordWrap: wordWrap)

        return container
    }

    func updateNSView(_ container: EditorContainerView, context: Context) {
        let textView = container.textView

        if textView.string != text {
            let saved = textView.selectedRange()
            context.coordinator.ignoreChanges = true
            textView.string = text
            context.coordinator.ignoreChanges = false
            let safe = NSRange(location: min(saved.location, text.utf16.count), length: 0)
            textView.setSelectedRange(safe)
        }

        if textView.font != font {
            textView.font = font
        }

        if let selectedRange, textView.selectedRange() != selectedRange {
            textView.setSelectedRange(selectedRange)
            textView.scrollRangeToVisible(selectedRange)
        }

        container.updateGutter(
            textLength: text.utf16.count,
            searchMatches: searchMatches,
            currentSearchMatch: currentSearchMatch
        )
        applyWordWrap(textView: textView, scrollView: container.scrollView, wordWrap: wordWrap)
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

    final class Coordinator: NSObject, NSTextViewDelegate {
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
            guard location <= string.utf16.count else { return }

            let utf16View = string.utf16
            let safeIndex = utf16View.index(utf16View.startIndex, offsetBy: location)
            let prefixUTF16 = utf16View[..<safeIndex]
            let prefix = String(decoding: prefixUTF16, as: UTF16.self)
            let lines = prefix.components(separatedBy: "\n")

            parent.cursorPosition = CursorPosition(
                line: lines.count,
                col: (lines.last?.count ?? 0) + 1
            )
        }
    }
}

final class EditorContainerView: NSView {
    let scrollView: NSScrollView
    let textView: NSTextView
    private let gutterView = SearchGutterView()
    private let gutterWidth: CGFloat = 12

    override init(frame frameRect: NSRect) {
        let scrollView = NSTextView.scrollableTextView()
        self.scrollView = scrollView
        self.textView = scrollView.documentView as? NSTextView ?? NSTextView()
        super.init(frame: frameRect)

        addSubview(scrollView)
        addSubview(gutterView)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        let visibleGutterWidth: CGFloat = gutterView.isHidden ? 0 : gutterWidth
        scrollView.frame = CGRect(
            x: 0,
            y: 0,
            width: bounds.width - visibleGutterWidth,
            height: bounds.height
        )
        gutterView.frame = CGRect(
            x: bounds.width - visibleGutterWidth,
            y: 0,
            width: visibleGutterWidth,
            height: bounds.height
        )
    }

    func updateGutter(textLength: Int, searchMatches: [NSRange], currentSearchMatch: NSRange?) {
        gutterView.textLength = max(textLength, 1)
        gutterView.searchMatches = searchMatches
        gutterView.currentSearchMatch = currentSearchMatch
        gutterView.isHidden = searchMatches.isEmpty
        needsLayout = true
        gutterView.needsDisplay = true
    }
}

final class SearchGutterView: NSView {
    var textLength: Int = 1
    var searchMatches: [NSRange] = []
    var currentSearchMatch: NSRange?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !searchMatches.isEmpty, bounds.height > 0 else { return }

        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()

        for match in searchMatches {
            drawMarker(
                for: match,
                color: NSColor.secondaryLabelColor.withAlphaComponent(0.45),
                thickness: 2
            )
        }

        if let currentSearchMatch {
            drawMarker(
                for: currentSearchMatch,
                color: NSColor.controlAccentColor,
                thickness: 4
            )
        }
    }

    private func drawMarker(for range: NSRange, color: NSColor, thickness: CGFloat) {
        let ratio = CGFloat(range.location) / CGFloat(max(textLength, 1))
        let y = ratio * max(bounds.height - thickness, 0)
        let rect = CGRect(
            x: 2,
            y: y,
            width: max(bounds.width - 4, 2),
            height: thickness
        )

        let path = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
        color.setFill()
        path.fill()
    }
}

struct CursorPosition: Equatable {
    var line: Int = 1
    var col: Int = 1
}
