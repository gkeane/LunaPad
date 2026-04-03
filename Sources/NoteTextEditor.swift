import AppKit
import SwiftUI

struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    var wordWrap: Bool
    var font: NSFont
    var showLineNumbers: Bool = false
    var isLargeDocument: Bool = false
    var isEditable: Bool = true
    @Binding var cursorPosition: CursorPosition
    @Binding var selectedRange: NSRange?
    var selectedRangeScrollRequestID: Int = 0
    var searchMatches: [NSRange]
    var currentSearchMatch: NSRange?
    var isLog: Bool = false

    func makeNSView(context: Context) -> EditorContainerView {
        let container = EditorContainerView()
        let textView = container.textView

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = !isLargeDocument
        textView.usesFindBar = !isLargeDocument
        textView.isIncrementalSearchingEnabled = !isLargeDocument
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = font
        textView.string = text
        context.coordinator.refreshMetrics(for: text)
        if shouldHighlightLogContent {
            applyLogHighlighting(textView: textView)
        }

        container.updateGutter(
            textLength: text.utf16.count,
            searchMatches: searchMatches,
            currentSearchMatch: currentSearchMatch
        )
        container.updateLineNumbers(
            lineCount: cursorPosition.totalLines,
            font: font,
            showLineNumbers: showLineNumbers,
            currentLine: cursorPosition.line,
            lineStarts: context.coordinator.lineStarts,
            baseLineNumber: 1
        )
        container.applyWordWrapIfNeeded(wordWrap: wordWrap)
        context.coordinator.attach(to: container)
        DispatchQueue.main.async {
            context.coordinator.updateCursor(textView)
        }

        return container
    }

    func updateNSView(_ container: EditorContainerView, context: Context) {
        let textView = container.textView

        if textView.string != text {
            let saved = textView.selectedRange()
            context.coordinator.ignoreChanges = true
            textView.string = text
            context.coordinator.ignoreChanges = false
            context.coordinator.refreshMetrics(for: text)
            let safe = NSRange(location: min(saved.location, text.utf16.count), length: 0)
            textView.setSelectedRange(safe)
            if shouldHighlightLogContent {
                context.coordinator.invalidateVisibleLogHighlightCache()
                applyLogHighlighting(textView: textView)
            }
            context.coordinator.updateCursor(textView)
        }

        if textView.font != font {
            textView.font = font
        }

        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }

        if textView.allowsUndo == isLargeDocument {
            textView.allowsUndo = !isLargeDocument
            textView.usesFindBar = !isLargeDocument
            textView.isIncrementalSearchingEnabled = !isLargeDocument
        }

        let shouldForceScroll = context.coordinator.lastSelectedRangeScrollRequestID != selectedRangeScrollRequestID
        if let selectedRange,
           (textView.selectedRange() != selectedRange || shouldForceScroll) {
            textView.setSelectedRange(selectedRange)
            textView.scrollRangeToVisible(selectedRange)
            context.coordinator.updateCursor(textView)
            context.coordinator.lastSelectedRangeScrollRequestID = selectedRangeScrollRequestID
        }

        container.updateGutter(
            textLength: text.utf16.count,
            searchMatches: searchMatches,
            currentSearchMatch: currentSearchMatch
        )
        container.updateLineNumbers(
            lineCount: cursorPosition.totalLines,
            font: font,
            showLineNumbers: showLineNumbers,
            currentLine: cursorPosition.line,
            lineStarts: context.coordinator.lineStarts,
            baseLineNumber: 1
        )
        container.applyWordWrapIfNeeded(wordWrap: wordWrap)
    }

    private var shouldHighlightLogContent: Bool {
        isLog && text.count <= LunaPadMemoryBudget.logHighlightCharacterLimit
    }

    private func applyLogHighlighting(textView: NSTextView) {
        applyLogHighlighting(textView: textView, range: visibleLogHighlightRange(in: textView))
    }

    private func applyLogHighlighting(textView: NSTextView, range: NSRange) {
        guard let storage = textView.textStorage else { return }
        let string = textView.string
        let nsString = string as NSString
        guard nsString.length > 0 else { return }
        let clampedRange = NSIntersectionRange(range, NSRange(location: 0, length: nsString.length))
        guard clampedRange.length > 0 else { return }
        let lineRange = nsString.lineRange(for: clampedRange)

        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: lineRange)
        nsString.enumerateSubstrings(in: lineRange, options: .byLines) { _, currentLineRange, _, _ in
            guard currentLineRange.length > 0 else { return }
            let upper = nsString.substring(with: currentLineRange).uppercased()
            let color: NSColor
            if upper.contains("ERROR") || upper.contains("FATAL") || upper.contains("CRITICAL") {
                color = .systemRed
            } else if upper.contains("WARN") {
                color = .systemOrange
            } else if upper.contains("DEBUG") {
                color = .secondaryLabelColor
            } else if upper.contains("TRACE") || upper.contains("VERBOSE") {
                color = .tertiaryLabelColor
            } else {
                color = .textColor
            }
            storage.addAttribute(.foregroundColor, value: color, range: currentLineRange)
        }
        storage.endEditing()
    }

    private func visibleLogHighlightRange(in textView: NSTextView) -> NSRange {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return NSRange(location: 0, length: textView.string.utf16.count)
        }

        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let nsString = textView.string as NSString
        let expandedStart = max(charRange.location - LunaPadMemoryBudget.visibleLogHighlightMarginCharacters, 0)
        let expandedEnd = min(
            NSMaxRange(charRange) + LunaPadMemoryBudget.visibleLogHighlightMarginCharacters,
            nsString.length
        )
        return NSRange(location: expandedStart, length: max(expandedEnd - expandedStart, 0))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextEditor
        var ignoreChanges = false
        private weak var observedTextView: NSTextView?
        private weak var observedContentView: NSClipView?
        private var lastHighlightedRange: NSRange?
        private var lastHighlightedTextLength: Int = -1
        private var lineMetricsGeneration = 0
        private var isBuildingLineMetrics = false
        var lastSelectedRangeScrollRequestID = 0

        init(_ parent: NoteTextEditor) {
            self.parent = parent
        }

        deinit {
            if let observedContentView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: observedContentView
                )
            }
        }

        func attach(to container: EditorContainerView) {
            guard observedTextView !== container.textView else { return }

            if let observedContentView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: observedContentView
                )
            }

            observedTextView = container.textView
            observedContentView = container.scrollView.contentView
            lastHighlightedRange = nil
            lastHighlightedTextLength = -1
            container.scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollViewBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: container.scrollView.contentView
            )
        }

        func textDidChange(_ notification: Notification) {
            guard !ignoreChanges, let textView = notification.object as? NSTextView else { return }
            if parent.isLog && textView.string.count <= LunaPadMemoryBudget.logHighlightCharacterLimit {
                applyVisibleLogHighlightIfNeeded(to: textView, force: true)
            }
            refreshMetrics(for: textView.string)
            parent.text = textView.string
            updateCursor(textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.selectedRange = textView.selectedRange()
            updateCursor(textView)
        }

        @objc private func scrollViewBoundsDidChange(_ notification: Notification) {
            guard parent.shouldHighlightLogContent,
                  let textView = observedTextView else { return }
            applyVisibleLogHighlightIfNeeded(to: textView)
        }

        private var cachedTotalLines = 1
        private var cachedTotalCharacters = 0
        private var cachedLineStarts: [Int] = [0]

        var lineStarts: [Int] {
            cachedLineStarts
        }

        func refreshMetrics(for text: String) {
            cachedTotalCharacters = text.count
            guard !parent.isLargeDocument else {
                cachedTotalLines = 0
                cachedLineStarts = [0]
                isBuildingLineMetrics = false
                return
            }

            if text.count >= LunaPadMemoryBudget.asynchronousLineMetricsCharacterLimit {
                buildLineMetricsAsync(for: text)
                return
            }

            isBuildingLineMetrics = false
            applyLineMetrics(computeLineMetrics(for: text))
        }

        private func computeLineMetrics(for text: String) -> (lineStarts: [Int], totalLines: Int) {
            let nsText = text as NSString
            var lineStarts: [Int] = [0]
            lineStarts.reserveCapacity(max(cachedTotalLines, 32))
            var searchLocation = 0

            while searchLocation < nsText.length {
                let lineRange = nsText.lineRange(for: NSRange(location: searchLocation, length: 0))
                let nextLocation = NSMaxRange(lineRange)
                if nextLocation < nsText.length {
                    lineStarts.append(nextLocation)
                }
                searchLocation = nextLocation
            }

            return (lineStarts, max(lineStarts.count, 1))
        }

        private func applyLineMetrics(_ metrics: (lineStarts: [Int], totalLines: Int)) {
            cachedLineStarts = metrics.lineStarts
            cachedTotalLines = metrics.totalLines
        }

        private func buildLineMetricsAsync(for text: String) {
            let generation = lineMetricsGeneration + 1
            lineMetricsGeneration = generation
            isBuildingLineMetrics = true

            Task.detached(priority: .utility) { [text] in
                let metrics = self.computeLineMetrics(for: text)
                await MainActor.run {
                    guard self.lineMetricsGeneration == generation else { return }
                    guard self.cachedTotalCharacters == text.count else { return }
                    self.applyLineMetrics(metrics)
                    self.isBuildingLineMetrics = false
                    if let textView = self.observedTextView {
                        self.updateCursor(textView)
                        textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
                    }
                }
            }
        }

        func updateCursor(_ textView: NSTextView) {
            let location = textView.selectedRange().location
            let string = textView.string
            guard location <= string.utf16.count else { return }

            if parent.isLargeDocument {
                if cachedTotalCharacters != string.count {
                    refreshMetrics(for: string)
                }

                let updatedPosition = CursorPosition(
                    line: 0,
                    col: 0,
                    location: location,
                    totalLines: 0,
                    totalCharacters: cachedTotalCharacters
                )

                if parent.cursorPosition != updatedPosition {
                    parent.cursorPosition = updatedPosition
                }
                return
            }

            if cachedTotalCharacters != string.count {
                refreshMetrics(for: string)
            }

            if isBuildingLineMetrics {
                let updatedPosition = CursorPosition(
                    line: 0,
                    col: 0,
                    location: location,
                    totalLines: 0,
                    totalCharacters: cachedTotalCharacters
                )

                if parent.cursorPosition != updatedPosition {
                    parent.cursorPosition = updatedPosition
                }
                return
            }

            let lineIndex = lineIndex(for: location)
            let lineStart = cachedLineStarts[lineIndex]
            let lineNumber = lineIndex + 1
            let column = max(location - lineStart, 0) + 1

            let updatedPosition = CursorPosition(
                line: lineNumber,
                col: column,
                location: location,
                totalLines: cachedTotalLines,
                totalCharacters: cachedTotalCharacters
            )

            if parent.cursorPosition != updatedPosition {
                parent.cursorPosition = updatedPosition
            }
        }

        private func lineIndex(for location: Int) -> Int {
            guard !cachedLineStarts.isEmpty else { return 0 }

            var low = 0
            var high = cachedLineStarts.count - 1
            var best = 0

            while low <= high {
                let mid = (low + high) / 2
                if cachedLineStarts[mid] <= location {
                    best = mid
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }

            return best
        }

        func applyVisibleLogHighlightIfNeeded(to textView: NSTextView, force: Bool = false) {
            let visibleRange = parent.visibleLogHighlightRange(in: textView)
            let textLength = textView.string.utf16.count

            if !force,
               let lastHighlightedRange,
               NSEqualRanges(lastHighlightedRange, visibleRange),
               lastHighlightedTextLength == textLength {
                return
            }

            parent.applyLogHighlighting(textView: textView, range: visibleRange)
            lastHighlightedRange = visibleRange
            lastHighlightedTextLength = textLength
        }

        func invalidateVisibleLogHighlightCache() {
            lastHighlightedRange = nil
            lastHighlightedTextLength = -1
        }
    }
}

// Custom NSTextView subclass that rejects file drops.
// Default NSTextView accepts dragged files and inserts their paths as text,
// which corrupts the document content.
private final class LunaPadTextView: NSTextView {
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.availableType(from: [.fileURL]) != nil {
            return []
        }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if sender.draggingPasteboard.availableType(from: [.fileURL]) != nil {
            return false
        }
        return super.performDragOperation(sender)
    }
}

final class EditorContainerView: NSView {
    let scrollView: NSScrollView
    let textView: NSTextView
    private let gutterView = SearchGutterView()
    private let gutterWidth: CGFloat = 12
    private var lastGutterState = GutterState()
    private var lastLineNumberState = LineNumberState()
    private var lastWordWrapState = WordWrapState()

    override init(frame frameRect: NSRect) {
        // Build scroll+text view manually so we can use LunaPadTextView.
        // NSTextView.scrollableTextView() doesn't allow specifying a custom class.
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let tv = LunaPadTextView(frame: .zero, textContainer: textContainer)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainerInset = NSSize(width: 12, height: 8)

        let sv = NSScrollView()
        sv.hasVerticalScroller = true
        sv.autohidesScrollers = true
        sv.borderType = .noBorder
        // Wire up line-number ruler. NSScrollView positions it automatically,
        // so no custom layout() manipulation of the scroll view's frame is needed.
        let ruler = LineNumberRulerView(scrollView: sv, orientation: .verticalRuler)
        sv.verticalRulerView = ruler
        sv.hasVerticalRuler = true
        sv.hasHorizontalRuler = false
        sv.rulersVisible = false
        sv.documentView = tv
        // clientView must be set explicitly — NSScrollView does not do this
        // automatically when documentView is assigned before rulersVisible is true.
        ruler.clientView = tv

        self.scrollView = sv
        self.textView = tv
        super.init(frame: frameRect)

        // Observe scroll so the ruler redraws as the user scrolls.
        ruler.observeScrollNotifications()

        addSubview(sv)
        addSubview(gutterView)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let visibleGutterWidth: CGFloat = gutterView.isHidden ? 0 : gutterWidth
        scrollView.frame = CGRect(
            x: 0,
            y: 0,
            width: max(bounds.width - visibleGutterWidth, 0),
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
        let newState = GutterState(
            textLength: max(textLength, 1),
            searchMatches: searchMatches,
            currentSearchMatch: currentSearchMatch
        )
        guard newState != lastGutterState else { return }

        let visibilityChanged = lastGutterState.isHidden != newState.isHidden
        lastGutterState = newState
        gutterView.textLength = newState.textLength
        gutterView.searchMatches = newState.searchMatches
        gutterView.currentSearchMatch = newState.currentSearchMatch
        gutterView.isHidden = newState.isHidden
        if visibilityChanged {
            needsLayout = true
        }
        gutterView.needsDisplay = true
    }

    func updateLineNumbers(
        lineCount: Int,
        font: NSFont,
        showLineNumbers: Bool,
        currentLine: Int,
        lineStarts: [Int],
        baseLineNumber: Int
    ) {
        guard let ruler = scrollView.verticalRulerView as? LineNumberRulerView else { return }
        let newState = LineNumberState(
            lineCount: max(lineCount, 1),
            fontName: font.fontName,
            fontSize: font.pointSize,
            showLineNumbers: showLineNumbers,
            currentLine: currentLine,
            lineStarts: lineStarts,
            baseLineNumber: max(baseLineNumber, 1)
        )
        guard newState != lastLineNumberState else { return }

        lastLineNumberState = newState
        ruler.lineCount = newState.lineCount
        ruler.editorFont = font
        ruler.currentLine = newState.currentLine
        ruler.lineStarts = newState.lineStarts
        ruler.baseLineNumber = newState.baseLineNumber
        ruler.ruleThickness = ruler.requiredWidth
        scrollView.rulersVisible = newState.showLineNumbers
        ruler.needsDisplay = true
    }

    func applyWordWrapIfNeeded(wordWrap: Bool) {
        let contentWidth = scrollView.contentSize.width
        let newState = WordWrapState(wordWrap: wordWrap, contentWidth: contentWidth)
        guard newState != lastWordWrapState else { return }

        lastWordWrapState = newState
        if wordWrap {
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = CGSize(
                width: contentWidth,
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
}

private struct GutterState: Equatable {
    var textLength: Int = 1
    var searchMatches: [NSRange] = []
    var currentSearchMatch: NSRange?

    var isHidden: Bool {
        searchMatches.isEmpty
    }
}

private struct LineNumberState: Equatable {
    var lineCount: Int = 1
    var fontName: String = ""
    var fontSize: CGFloat = 0
    var showLineNumbers = false
    var currentLine: Int = 1
    var lineStarts: [Int] = [0]
    var baseLineNumber: Int = 1
}

private struct WordWrapState: Equatable {
    var wordWrap = true
    var contentWidth: CGFloat = 0
}

// Line numbers use NSScrollView's built-in ruler infrastructure (NSRulerView).
// The scroll view positions the ruler inside itself automatically — the scroll
// view's own frame in the SwiftUI/NSViewRepresentable hierarchy is untouched,
// so the workspace strip and file tab strip above remain unaffected.
final class LineNumberRulerView: NSRulerView {
    var lineCount: Int = 1
    var editorFont: NSFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    var currentLine: Int = 1
    var lineStarts: [Int] = [0]
    var baseLineNumber: Int = 1

    // NSTextView is flipped (Y increases downward). The ruler must match so
    // our Y coordinates align with the layout manager's fragment rects.
    override var isFlipped: Bool { true }

    override init(scrollView: NSScrollView?, orientation: NSRulerView.Orientation) {
        super.init(scrollView: scrollView, orientation: orientation)
        ruleThickness = 40
    }

    required init(coder: NSCoder) { fatalError("init(coder:) not supported") }

    /// Call once after the scroll view's contentView is ready.
    func observeScrollNotifications() {
        guard let sv = scrollView else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: sv.contentView
        )
    }

    @objc private func scrollViewBoundsDidChange(_ notification: Notification) {
        needsDisplay = true
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private var displayFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: max(editorFont.pointSize - 2, 10), weight: .regular)
    }

    var requiredWidth: CGFloat {
        let highestLineNumber = max(baseLineNumber + max(lineCount - 1, 0), 1)
        let digitCount = max(String(highestLineNumber).count, 2)
        let sample = String(repeating: "8", count: digitCount) as NSString
        let size = sample.size(withAttributes: [.font: displayFont])
        return ceil(size.width + 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        // The ruler draws in its own coordinate space (origin at top-left when
        // isFlipped=true, Y=0 at the top of the VISIBLE area). To map from
        // layout manager fragment rects (document coordinates) to ruler
        // coordinates we subtract the scroll offset (visibleRect.minY).
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        NSColor.separatorColor.setStroke()
        let sep = NSBezierPath()
        sep.move(to: CGPoint(x: bounds.maxX - 0.5, y: dirtyRect.minY))
        sep.line(to: CGPoint(x: bounds.maxX - 0.5, y: dirtyRect.maxY))
        sep.lineWidth = 1
        sep.stroke()

        guard let textView = clientView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let contentView = scrollView?.contentView else { return }

        // visibleRect.minY is the document-space scroll offset.
        let visibleMinY = contentView.documentVisibleRect.minY
        let originY = textView.textContainerOrigin.y
        let text = textView.string as NSString

        if text.length == 0 {
            let rulerY = originY - visibleMinY
            drawLineNumber(1, at: rulerY, isCurrent: true)
            return
        }

        let visibleRect = contentView.documentVisibleRect
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(
            forGlyphRange: visibleGlyphRange,
            actualGlyphRange: nil
        )

        let firstVisibleLineIndex = lineIndex(for: max(visibleCharRange.location, 0))
        let lastVisibleCharacter = min(max(NSMaxRange(visibleCharRange), 0), text.length)
        let lastVisibleLineIndex = lineIndex(for: lastVisibleCharacter)
        let lastLineIndexToDraw = min(max(lastVisibleLineIndex + 1, firstVisibleLineIndex), max(lineStarts.count - 1, 0))

        for lineIndex in firstVisibleLineIndex...lastLineIndexToDraw {
            let lineStart = lineStarts[lineIndex]
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: lineStart)
            let fragmentRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: nil
            )
            let rulerY = fragmentRect.minY + originY - visibleMinY
            if rulerY > bounds.height {
                break
            }
            if rulerY + fragmentRect.height >= 0 {
                let displayedLine = baseLineNumber + lineIndex
                drawLineNumber(displayedLine, at: rulerY, isCurrent: displayedLine == currentLine)
            }
        }

        if text.length > 0,
           text.character(at: text.length - 1) == 10 {
            let extraRect = layoutManager.extraLineFragmentRect
            if extraRect != .zero {
                let extraLineNumber = baseLineNumber + lineStarts.count
                let rulerY = extraRect.minY + originY - visibleMinY
                if rulerY + extraRect.height >= 0 && rulerY <= bounds.height {
                    drawLineNumber(extraLineNumber, at: rulerY, isCurrent: extraLineNumber == currentLine)
                }
            }
        }
    }

    private func lineIndex(for location: Int) -> Int {
        guard !lineStarts.isEmpty else { return 0 }

        var low = 0
        var high = lineStarts.count - 1
        var best = 0

        while low <= high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= location {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return best
    }

    private func drawLineNumber(_ number: Int, at y: CGFloat, isCurrent: Bool) {
        let ps = NSMutableParagraphStyle()
        ps.alignment = .right
        let attrs: [NSAttributedString.Key: Any] = [
            .font: displayFont,
            .foregroundColor: isCurrent ? NSColor.labelColor : NSColor.secondaryLabelColor,
            .paragraphStyle: ps
        ]
        let lineHeight = displayFont.ascender - displayFont.descender + displayFont.leading
        let rect = CGRect(x: 0, y: y + 1, width: bounds.width - 6, height: max(lineHeight, 14))
        ("\(number)" as NSString).draw(in: rect, withAttributes: attrs)
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
    var location: Int = 0
    var totalLines: Int = 1
    var totalCharacters: Int = 0
}
