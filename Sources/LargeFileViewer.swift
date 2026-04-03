import AppKit
import SwiftUI

struct LargeFileViewer: View {
    private enum Source {
        case text(String)
        case file(url: URL, fileSize: Int)
    }

    private let source: Source
    var wordWrap: Bool
    var font: NSFont
    var showLineNumbers: Bool
    @Binding var cursorPosition: CursorPosition
    @Binding var selectedRange: NSRange?
    var selectedRangeScrollRequestID: Int

    init(
        text: String,
        wordWrap: Bool,
        font: NSFont,
        showLineNumbers: Bool,
        cursorPosition: Binding<CursorPosition>,
        selectedRange: Binding<NSRange?>,
        selectedRangeScrollRequestID: Int
    ) {
        self.source = .text(text)
        self.wordWrap = wordWrap
        self.font = font
        self.showLineNumbers = showLineNumbers
        self._cursorPosition = cursorPosition
        self._selectedRange = selectedRange
        self.selectedRangeScrollRequestID = selectedRangeScrollRequestID
    }

    init(
        fileURL: URL,
        fileSize: Int,
        wordWrap: Bool,
        font: NSFont,
        showLineNumbers: Bool,
        cursorPosition: Binding<CursorPosition>,
        selectedRange: Binding<NSRange?>,
        selectedRangeScrollRequestID: Int
    ) {
        self.source = .file(url: fileURL, fileSize: fileSize)
        self.wordWrap = wordWrap
        self.font = font
        self.showLineNumbers = showLineNumbers
        self._cursorPosition = cursorPosition
        self._selectedRange = selectedRange
        self.selectedRangeScrollRequestID = selectedRangeScrollRequestID
    }

    var body: some View {
        switch source {
        case .text(let text):
            LargeFileTextView(
                text: text,
                totalCharacters: text.count,
                baseOffset: 0,
                baseLineNumber: 1,
                wordWrap: wordWrap,
                font: font,
                showLineNumbers: showLineNumbers,
                cursorPosition: $cursorPosition,
                selectedRange: $selectedRange,
                selectedRangeScrollRequestID: selectedRangeScrollRequestID
            )
        case .file(let url, let fileSize):
            SlidingChunkedLargeFileTextView(
                fileURL: url,
                fileSize: fileSize,
                wordWrap: wordWrap,
                font: font,
                showLineNumbers: showLineNumbers,
                cursorPosition: $cursorPosition,
                selectedRange: $selectedRange,
                selectedRangeScrollRequestID: selectedRangeScrollRequestID
            )
        }
    }
}

private struct SlidingChunkedLargeFileTextView: NSViewRepresentable {
    let fileURL: URL
    let fileSize: Int
    var wordWrap: Bool
    var font: NSFont
    var showLineNumbers: Bool
    @Binding var cursorPosition: CursorPosition
    @Binding var selectedRange: NSRange?
    var selectedRangeScrollRequestID: Int

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(
            containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = false
        textView.usesFindBar = false
        textView.isIncrementalSearchingEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = font
        textView.string = ""
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 12, height: 8)
        scrollView.documentView = textView

        let ruler = LineNumberRulerView(scrollView: scrollView, orientation: .verticalRuler)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.hasHorizontalRuler = false
        scrollView.rulersVisible = showLineNumbers
        ruler.clientView = textView
        ruler.observeScrollNotifications()

        applyWordWrap(textView: textView, scrollView: scrollView)
        context.coordinator.attach(scrollView: scrollView, textView: textView)
        context.coordinator.loadInitialChunkIfNeeded()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.font != font {
            textView.font = font
        }

        applyWordWrap(textView: textView, scrollView: scrollView)
        context.coordinator.updateLineNumbers()
        scrollView.rulersVisible = showLineNumbers

        let shouldForceScroll = context.coordinator.lastSelectedRangeScrollRequestID != selectedRangeScrollRequestID
        if let selectedRange,
           let localRange = context.coordinator.localRange(for: selectedRange),
           (textView.selectedRange() != localRange || shouldForceScroll) {
            textView.setSelectedRange(localRange)
            textView.scrollRangeToVisible(localRange)
            context.coordinator.updateCursor(textView)
            context.coordinator.lastSelectedRangeScrollRequestID = selectedRangeScrollRequestID
        }
    }

    private func applyWordWrap(textView: NSTextView, scrollView: NSScrollView) {
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
        var parent: SlidingChunkedLargeFileTextView

        private weak var scrollView: NSScrollView?
        private weak var textView: NSTextView?
        private weak var observedContentView: NSClipView?

        private var chunks: [LargeFileChunk] = []
        private var isLoadingPreviousChunk = false
        private var isLoadingNextChunk = false
        private var isAdjustingView = false
        private var baseLineNumber = 1
        private var lineStarts: [Int] = [0]
        private var loadedLineCount = 1
        var lastSelectedRangeScrollRequestID = 0

        init(_ parent: SlidingChunkedLargeFileTextView) {
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

        func attach(scrollView: NSScrollView, textView: NSTextView) {
            guard self.textView !== textView else { return }

            if let observedContentView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: observedContentView
                )
            }

            self.scrollView = scrollView
            self.textView = textView
            self.observedContentView = scrollView.contentView
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollViewBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        func loadInitialChunkIfNeeded() {
            guard chunks.isEmpty else { return }
            loadChunk(at: 0, direction: .replace)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let localRange = textView.selectedRange()
            parent.selectedRange = NSRange(
                location: currentBaseOffset + localRange.location,
                length: localRange.length
            )
            updateCursor(textView)
        }

        func updateCursor(_ textView: NSTextView) {
            let location = min(textView.selectedRange().location, textView.string.utf16.count)
            let localLineIndex = lineIndex(for: location)
            let lineStart = lineStarts[min(localLineIndex, max(lineStarts.count - 1, 0))]
            let updated = CursorPosition(
                line: baseLineNumber + localLineIndex,
                col: max(location - lineStart, 0) + 1,
                location: min(currentBaseOffset + location, parent.fileSize),
                totalLines: baseLineNumber + max(loadedLineCount - 1, 0),
                totalCharacters: parent.fileSize
            )

            if parent.cursorPosition != updated {
                parent.cursorPosition = updated
            }
        }

        func localRange(for globalRange: NSRange) -> NSRange? {
            let localStart = globalRange.location - currentBaseOffset
            guard localStart >= 0,
                  let textView,
                  localStart <= textView.string.utf16.count else {
                return nil
            }
            return NSRange(location: localStart, length: globalRange.length)
        }

        func updateLineNumbers() {
            guard let scrollView,
                  let ruler = scrollView.verticalRulerView as? LineNumberRulerView else { return }
            ruler.lineCount = loadedLineCount
            ruler.editorFont = parent.font
            ruler.currentLine = parent.cursorPosition.line
            ruler.lineStarts = lineStarts
            ruler.baseLineNumber = baseLineNumber
            ruler.ruleThickness = ruler.requiredWidth
            scrollView.rulersVisible = parent.showLineNumbers
            ruler.needsDisplay = true
        }

        @objc private func scrollViewBoundsDidChange(_ notification: Notification) {
            guard !isAdjustingView else { return }
            maybeLoadMoreForVisibleRegion()
        }

        private var currentBaseOffset: Int {
            Int(min(chunks.first?.startOffset ?? 0, UInt64(Int.max)))
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

        private func refreshLineMetrics() {
            guard let textView else { return }
            let nsText = textView.string as NSString
            var starts: [Int] = [0]
            var searchLocation = 0

            while searchLocation < nsText.length {
                let lineRange = nsText.lineRange(for: NSRange(location: searchLocation, length: 0))
                let nextLocation = NSMaxRange(lineRange)
                if nextLocation < nsText.length {
                    starts.append(nextLocation)
                }
                searchLocation = nextLocation
            }

            lineStarts = starts
            loadedLineCount = max(starts.count, 1)
        }

        private func maybeLoadMoreForVisibleRegion() {
            guard let scrollView,
                  let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  !chunks.isEmpty else { return }

            layoutManager.ensureLayout(for: textContainer)

            let visibleRect = scrollView.contentView.documentVisibleRect
            let contentHeight = max(layoutManager.usedRect(for: textContainer).height, visibleRect.height)
            let threshold = max(LunaPadMemoryBudget.largeFileViewerPrefetchDistance, visibleRect.height * 0.25)

            if visibleRect.maxY >= contentHeight - threshold,
               chunks.last?.hasNext == true,
               !isLoadingNextChunk {
                loadChunk(at: chunks.last?.endOffset ?? 0, direction: .append)
            }

            if visibleRect.minY <= threshold,
               chunks.first?.hasPrevious == true,
               !isLoadingPreviousChunk {
                let previousStart = chunks.first!.startOffset > UInt64(LunaPadMemoryBudget.largeFileViewerChunkBytes)
                    ? chunks.first!.startOffset - UInt64(LunaPadMemoryBudget.largeFileViewerChunkBytes)
                    : 0
                loadChunk(at: previousStart, direction: .prepend)
            }
        }

        private enum LoadDirection {
            case replace
            case append
            case prepend
        }

        private func loadChunk(at offset: UInt64, direction: LoadDirection) {
            let fileURL = parent.fileURL
            switch direction {
            case .replace:
                break
            case .append:
                isLoadingNextChunk = true
            case .prepend:
                isLoadingPreviousChunk = true
            }

            Task {
                do {
                    let chunk = try await Task.detached(priority: .userInitiated) {
                        try LunaPadMemoryBudget.loadLargeFileChunk(from: fileURL, startingAt: offset)
                    }.value

                    await MainActor.run {
                        switch direction {
                        case .replace:
                            replaceVisibleWindow(with: [chunk])
                        case .append:
                            appendChunk(chunk)
                            isLoadingNextChunk = false
                        case .prepend:
                            prependChunk(chunk)
                            isLoadingPreviousChunk = false
                        }
                    }
                } catch {
                    await MainActor.run {
                        isLoadingNextChunk = false
                        isLoadingPreviousChunk = false
                    }
                }
            }
        }

        private func replaceVisibleWindow(with newChunks: [LargeFileChunk]) {
            guard let textView else { return }

            chunks = newChunks
            baseLineNumber = 1
            isAdjustingView = true
            textView.string = newChunks.map(\.text).joined()
            refreshLineMetrics()
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            scrollView?.contentView.scroll(to: .zero)
            if let scrollView {
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            isAdjustingView = false
            updateCursor(textView)
            updateLineNumbers()
            maybeLoadMoreForVisibleRegion()
        }

        private func appendChunk(_ chunk: LargeFileChunk) {
            guard let textView,
                  chunks.last?.endOffset != chunk.endOffset else { return }

            isAdjustingView = true
            textView.string += chunk.text
            chunks.append(chunk)
            refreshLineMetrics()
            trimLeadingChunksIfNeeded()
            isAdjustingView = false
            updateCursor(textView)
            updateLineNumbers()
            maybeLoadMoreForVisibleRegion()
        }

        private func prependChunk(_ chunk: LargeFileChunk) {
            guard let textView,
                  let scrollView,
                  chunks.first?.startOffset != chunk.startOffset else { return }

            let oldVisibleY = scrollView.contentView.bounds.origin.y
            let oldHeight = documentHeight(for: textView)
            let addedCharacters = chunk.text.utf16.count

            isAdjustingView = true
            textView.string = chunk.text + textView.string
            chunks.insert(chunk, at: 0)
            baseLineNumber = max(baseLineNumber - chunk.lineBreakCount, 1)
            refreshLineMetrics()
            if let currentSelection = textView.selectedRanges.first {
                var range = currentSelection.rangeValue
                range.location += addedCharacters
                textView.setSelectedRange(range)
            }

            let newHeight = documentHeight(for: textView)
            let deltaHeight = max(newHeight - oldHeight, 0)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: oldVisibleY + deltaHeight))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            trimTrailingChunksIfNeeded()
            isAdjustingView = false
            updateCursor(textView)
            updateLineNumbers()
            maybeLoadMoreForVisibleRegion()
        }

        private func trimLeadingChunksIfNeeded() {
            guard let textView, let scrollView else { return }

            while chunks.count > LunaPadMemoryBudget.largeFileViewerRetainedChunkCount {
                let removedChunk = chunks.removeFirst()
                let removedCharacters = removedChunk.text.utf16.count
                let oldVisibleY = scrollView.contentView.bounds.origin.y
                let oldHeight = documentHeight(for: textView)
                let nsText = textView.string as NSString
                let remaining = nsText.substring(from: min(removedCharacters, nsText.length))
                textView.string = remaining

                if let currentSelection = textView.selectedRanges.first {
                    var range = currentSelection.rangeValue
                    range.location = max(range.location - removedCharacters, 0)
                    textView.setSelectedRange(range)
                }

                let newHeight = documentHeight(for: textView)
                let deltaHeight = max(oldHeight - newHeight, 0)
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(oldVisibleY - deltaHeight, 0)))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                baseLineNumber += removedChunk.lineBreakCount
                refreshLineMetrics()
            }
        }

        private func trimTrailingChunksIfNeeded() {
            guard let textView else { return }

            while chunks.count > LunaPadMemoryBudget.largeFileViewerRetainedChunkCount {
                let removedChunk = chunks.removeLast()
                let removedCharacters = removedChunk.text.utf16.count
                let nsText = textView.string as NSString
                let keepLength = max(nsText.length - removedCharacters, 0)
                textView.string = nsText.substring(to: keepLength)
                refreshLineMetrics()
            }
        }

        private func documentHeight(for textView: NSTextView) -> CGFloat {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return 0
            }
            layoutManager.ensureLayout(for: textContainer)
            return layoutManager.usedRect(for: textContainer).height
        }
    }
}

private struct LargeFileTextView: NSViewRepresentable {
    let text: String
    let totalCharacters: Int
    let baseOffset: Int
    let baseLineNumber: Int
    var wordWrap: Bool
    var font: NSFont
    var showLineNumbers: Bool
    @Binding var cursorPosition: CursorPosition
    @Binding var selectedRange: NSRange?
    var selectedRangeScrollRequestID: Int

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(
            containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = false
        textView.usesFindBar = false
        textView.isIncrementalSearchingEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = font
        textView.string = text
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 12, height: 8)
        scrollView.documentView = textView

        let ruler = LineNumberRulerView(scrollView: scrollView, orientation: .verticalRuler)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.hasHorizontalRuler = false
        scrollView.rulersVisible = showLineNumbers
        ruler.clientView = textView
        ruler.observeScrollNotifications()

        applyWordWrap(textView: textView, scrollView: scrollView)
        context.coordinator.refreshMetrics(
            text: text,
            totalCharacters: totalCharacters,
            baseOffset: baseOffset,
            baseLineNumber: baseLineNumber
        )
        context.coordinator.updateLineNumbers(scrollView: scrollView, font: font, showLineNumbers: showLineNumbers)
        context.coordinator.updateCursor(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            let savedSelection = textView.selectedRange()
            textView.string = text
            context.coordinator.refreshMetrics(
                text: text,
                totalCharacters: totalCharacters,
                baseOffset: baseOffset,
                baseLineNumber: baseLineNumber
            )
            let clampedSelection = NSRange(location: min(savedSelection.location, text.utf16.count), length: 0)
            textView.setSelectedRange(clampedSelection)
            context.coordinator.updateCursor(textView)
        }

        if textView.font != font {
            textView.font = font
        }

        let shouldForceScroll = context.coordinator.lastSelectedRangeScrollRequestID != selectedRangeScrollRequestID
        if let selectedRange,
           (textView.selectedRange() != selectedRange || shouldForceScroll) {
            textView.setSelectedRange(selectedRange)
            textView.scrollRangeToVisible(selectedRange)
            context.coordinator.updateCursor(textView)
            context.coordinator.lastSelectedRangeScrollRequestID = selectedRangeScrollRequestID
        }

        applyWordWrap(textView: textView, scrollView: scrollView)
        context.coordinator.updateLineNumbers(scrollView: scrollView, font: font, showLineNumbers: showLineNumbers)
    }

    private func applyWordWrap(textView: NSTextView, scrollView: NSScrollView) {
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
        var parent: LargeFileTextView
        private var totalCharacters = 0
        private var baseOffset = 0
        private var baseLineNumber = 1
        private var lineStarts: [Int] = [0]
        private var loadedLineCount = 1
        var lastSelectedRangeScrollRequestID = 0

        init(_ parent: LargeFileTextView) {
            self.parent = parent
        }

        func refreshMetrics(text: String, totalCharacters: Int, baseOffset: Int, baseLineNumber: Int) {
            self.totalCharacters = totalCharacters
            self.baseOffset = baseOffset
            self.baseLineNumber = baseLineNumber

            let nsText = text as NSString
            var starts: [Int] = [0]
            var searchLocation = 0

            while searchLocation < nsText.length {
                let lineRange = nsText.lineRange(for: NSRange(location: searchLocation, length: 0))
                let nextLocation = NSMaxRange(lineRange)
                if nextLocation < nsText.length {
                    starts.append(nextLocation)
                }
                searchLocation = nextLocation
            }

            lineStarts = starts
            loadedLineCount = max(starts.count, 1)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.selectedRange = textView.selectedRange()
            updateCursor(textView)
        }

        func updateLineNumbers(scrollView: NSScrollView, font: NSFont, showLineNumbers: Bool) {
            guard let ruler = scrollView.verticalRulerView as? LineNumberRulerView else { return }
            ruler.lineCount = loadedLineCount
            ruler.editorFont = font
            ruler.currentLine = parent.cursorPosition.line
            ruler.lineStarts = lineStarts
            ruler.baseLineNumber = baseLineNumber
            ruler.ruleThickness = ruler.requiredWidth
            scrollView.rulersVisible = showLineNumbers
            ruler.needsDisplay = true
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

        func updateCursor(_ textView: NSTextView) {
            let location = min(textView.selectedRange().location, textView.string.utf16.count)
            let localLineIndex = lineIndex(for: location)
            let lineStart = lineStarts[min(localLineIndex, max(lineStarts.count - 1, 0))]
            let updated = CursorPosition(
                line: baseLineNumber + localLineIndex,
                col: max(location - lineStart, 0) + 1,
                location: min(baseOffset + location, totalCharacters),
                totalLines: baseLineNumber + max(loadedLineCount - 1, 0),
                totalCharacters: totalCharacters
            )

            if parent.cursorPosition != updated {
                parent.cursorPosition = updated
            }
        }
    }
}
