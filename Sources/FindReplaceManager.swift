import Foundation

@MainActor
final class FindReplaceManager: ObservableObject {
    @Published var isOpen = false
    @Published var findText = ""
    @Published var replaceText = ""
    @Published var caseSensitive = false
    @Published var wholeWords = false
    @Published var matchCount = 0
    @Published var currentMatchIndex = 0
    @Published var modeDescription: String = ""

    private var matches: [NSRange] = []
    private var matchUpdateTask: Task<Void, Never>?
    private var matchUpdateGeneration = 0

    var currentMatch: NSRange? {
        guard matches.indices.contains(currentMatchIndex) else { return nil }
        return matches[currentMatchIndex]
    }

    var allMatches: [NSRange] {
        matches
    }

    func scheduleMatchUpdate(
        in text: String,
        isLargeDocument: Bool = false,
        onComplete: ((NSRange?) -> Void)? = nil
    ) {
        matchUpdateTask?.cancel()
        matchUpdateGeneration &+= 1
        let generation = matchUpdateGeneration

        if isLargeDocument {
            clearIndexedMatches(modeDescription: findText.isEmpty ? "" : "On-demand")
            onComplete?(currentMatch)
            return
        }

        guard let regex = makeRegex(), !findText.isEmpty else {
            clearIndexedMatches(modeDescription: "")
            onComplete?(currentMatch)
            return
        }

        let previousLocation = currentMatch?.location
        clearIndexedMatches(modeDescription: "Indexing…")
        let capturedText = text
        matchUpdateTask = Task(priority: .utility) {
            let computedMatches = await Task.detached(priority: .utility) {
                Self.findAllMatches(in: capturedText, using: regex)
            }.value

            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.matchUpdateGeneration == generation else { return }
                self.applyMatchUpdate(
                    matches: computedMatches,
                    previousLocation: previousLocation,
                    modeDescription: ""
                )
                onComplete?(self.currentMatch)
            }
        }
    }

    func updateMatchesSynchronously(in text: String, isLargeDocument: Bool = false) {
        matchUpdateTask?.cancel()
        matchUpdateGeneration &+= 1

        if isLargeDocument {
            clearIndexedMatches(modeDescription: findText.isEmpty ? "" : "On-demand")
            return
        }

        let previousLocation = currentMatch?.location
        applyMatchUpdate(
            matches: Self.findAllMatches(in: text, using: makeRegex()),
            previousLocation: previousLocation,
            modeDescription: ""
        )
    }

    func findNext(in text: String) -> NSRange? {
        updateMatchesSynchronously(in: text)
        guard !matches.isEmpty else { return nil }
        let next = (currentMatchIndex + 1) % matches.count
        currentMatchIndex = next
        return matches[next]
    }

    func findNextAsync(in text: String) async -> NSRange? {
        await navigateIndexedMatches(in: text, direction: .next)
    }

    func findPrevious(in text: String) -> NSRange? {
        updateMatchesSynchronously(in: text)
        guard !matches.isEmpty else { return nil }
        let prev = currentMatchIndex == 0 ? matches.count - 1 : currentMatchIndex - 1
        currentMatchIndex = prev
        return matches[prev]
    }

    func findPreviousAsync(in text: String) async -> NSRange? {
        await navigateIndexedMatches(in: text, direction: .previous)
    }

    func findNextOnDemand(in text: String, after location: Int) -> NSRange? {
        guard let regex = makeRegex(), !findText.isEmpty else {
            clearIndexedMatches(modeDescription: "")
            return nil
        }

        let nsText = text as NSString
        let start = min(max(location, 0), nsText.length)
        let primaryRange = NSRange(location: start, length: nsText.length - start)
        let wrappedRange = NSRange(location: 0, length: start)

        if let match = regex.firstMatch(in: text, options: [], range: primaryRange)?.range
            ?? regex.firstMatch(in: text, options: [], range: wrappedRange)?.range {
            matches = [match]
            matchCount = 1
            currentMatchIndex = 0
            modeDescription = "On-demand"
            return match
        }

        clearIndexedMatches(modeDescription: "On-demand")
        return nil
    }

    func findPreviousOnDemand(in text: String, before location: Int) -> NSRange? {
        guard let regex = makeRegex(), !findText.isEmpty else {
            clearIndexedMatches(modeDescription: "")
            return nil
        }

        let nsText = text as NSString
        let end = min(max(location, 0), nsText.length)
        let primaryRange = NSRange(location: 0, length: end)
        let wrappedRange = NSRange(location: end, length: nsText.length - end)

        if let match = lastMatch(using: regex, in: text, range: primaryRange)
            ?? lastMatch(using: regex, in: text, range: wrappedRange) {
            matches = [match]
            matchCount = 1
            currentMatchIndex = 0
            modeDescription = "On-demand"
            return match
        }

        clearIndexedMatches(modeDescription: "On-demand")
        return nil
    }

    func replaceCurrent(in text: String) -> String {
        updateMatchesSynchronously(in: text)
        guard let range = currentMatch else { return text }
        let nsText = text as NSString
        return nsText.replacingCharacters(in: range, with: replaceText)
    }

    func replaceCurrentAsync(in text: String) async -> String {
        matchUpdateTask?.cancel()
        matchUpdateGeneration &+= 1

        guard let regex = makeRegex(), !findText.isEmpty else {
            clearIndexedMatches(modeDescription: "")
            return text
        }

        let previousLocation = currentMatch?.location
        let replacement = replaceText
        return await Task.detached(priority: .userInitiated) {
            Self.replaceCurrentMatch(
                in: text,
                using: regex,
                replacingWith: replacement,
                previousLocation: previousLocation
            )
        }.value
    }

    func replaceAll(in text: String) -> String {
        updateMatchesSynchronously(in: text)
        guard !matches.isEmpty else { return text }
        var result = text as NSString
        for range in matches.reversed() {
            result = result.replacingCharacters(in: range, with: replaceText) as NSString
        }
        return String(result)
    }

    func replaceAllAsync(in text: String) async -> String {
        matchUpdateTask?.cancel()
        matchUpdateGeneration &+= 1

        guard let regex = makeRegex(), !findText.isEmpty else {
            clearIndexedMatches(modeDescription: "")
            return text
        }

        let replacement = replaceText
        return await Task.detached(priority: .userInitiated) {
            Self.replaceAllMatches(
                in: text,
                using: regex,
                replacingWith: replacement
            )
        }.value
    }

    private func navigateIndexedMatches(in text: String, direction: NavigationDirection) async -> NSRange? {
        matchUpdateTask?.cancel()
        matchUpdateGeneration &+= 1
        let generation = matchUpdateGeneration

        guard let regex = makeRegex(), !findText.isEmpty else {
            clearIndexedMatches(modeDescription: "")
            return nil
        }

        let previousLocation = currentMatch?.location
        modeDescription = "Indexing…"
        let capturedText = text
        let result = await Task.detached(priority: .userInitiated) {
            Self.computeNavigationResult(
                in: capturedText,
                using: regex,
                previousLocation: previousLocation,
                direction: direction
            )
        }.value

        guard matchUpdateGeneration == generation else { return nil }
        applyMatchUpdate(
            matches: result.matches,
            previousLocation: nil,
            modeDescription: ""
        )

        if let selectedIndex = result.selectedIndex,
           matches.indices.contains(selectedIndex) {
            currentMatchIndex = selectedIndex
            return matches[selectedIndex]
        }

        return nil
    }

    private func applyMatchUpdate(matches: [NSRange], previousLocation: Int?, modeDescription: String) {
        self.matches = matches
        matchCount = matches.count
        self.modeDescription = modeDescription

        guard !matches.isEmpty else {
            currentMatchIndex = 0
            return
        }

        if let previousLocation,
           let matchIndex = matches.firstIndex(where: { $0.location == previousLocation }) {
            currentMatchIndex = matchIndex
        } else {
            currentMatchIndex = min(currentMatchIndex, matches.count - 1)
        }
    }

    private func clearIndexedMatches(modeDescription: String) {
        matches = []
        matchCount = 0
        currentMatchIndex = 0
        self.modeDescription = modeDescription
    }

    private enum NavigationDirection {
        case next
        case previous
    }

    private struct NavigationResult {
        var matches: [NSRange]
        var selectedIndex: Int?
    }

    nonisolated private static func findAllMatches(in text: String, using regex: NSRegularExpression?) -> [NSRange] {
        guard let regex else { return [] }
        let nsText = text as NSString
        var collected: [NSRange] = []
        collected.reserveCapacity(min(LunaPadMemoryBudget.maxTrackedSearchMatches, 128))
        regex.enumerateMatches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) { match, _, stop in
            guard let match else { return }
            collected.append(match.range)
            if collected.count >= LunaPadMemoryBudget.maxTrackedSearchMatches {
                stop.pointee = true
            }
        }
        return collected
    }

    nonisolated private static func computeNavigationResult(
        in text: String,
        using regex: NSRegularExpression,
        previousLocation: Int?,
        direction: NavigationDirection
    ) -> NavigationResult {
        let matches = findAllMatches(in: text, using: regex)
        guard !matches.isEmpty else {
            return NavigationResult(matches: [], selectedIndex: nil)
        }

        let baseIndex = previousLocation.flatMap { location in
            matches.firstIndex(where: { $0.location == location })
        }

        let selectedIndex: Int
        switch direction {
        case .next:
            if let baseIndex {
                selectedIndex = (baseIndex + 1) % matches.count
            } else {
                selectedIndex = 0
            }
        case .previous:
            if let baseIndex {
                selectedIndex = baseIndex == 0 ? matches.count - 1 : baseIndex - 1
            } else {
                selectedIndex = matches.count - 1
            }
        }

        return NavigationResult(matches: matches, selectedIndex: selectedIndex)
    }

    nonisolated private static func replaceCurrentMatch(
        in text: String,
        using regex: NSRegularExpression,
        replacingWith replacement: String,
        previousLocation: Int?
    ) -> String {
        let matches = findAllMatches(in: text, using: regex)
        guard !matches.isEmpty else { return text }

        let targetIndex = previousLocation.flatMap { location in
            matches.firstIndex(where: { $0.location == location })
        } ?? 0
        guard matches.indices.contains(targetIndex) else { return text }

        let nsText = text as NSString
        return nsText.replacingCharacters(in: matches[targetIndex], with: replacement)
    }

    nonisolated private static func replaceAllMatches(
        in text: String,
        using regex: NSRegularExpression,
        replacingWith replacement: String
    ) -> String {
        let matches = findAllMatches(in: text, using: regex)
        guard !matches.isEmpty else { return text }

        var result = text as NSString
        for range in matches.reversed() {
            result = result.replacingCharacters(in: range, with: replacement) as NSString
        }
        return String(result)
    }

    private func makeRegex() -> NSRegularExpression? {
        guard !findText.isEmpty else { return nil }
        let pattern = wholeWords
            ? "\\b\(NSRegularExpression.escapedPattern(for: findText))\\b"
            : NSRegularExpression.escapedPattern(for: findText)
        let options: NSRegularExpression.Options = caseSensitive ? [] : .caseInsensitive
        return try? NSRegularExpression(pattern: pattern, options: options)
    }

    private func lastMatch(using regex: NSRegularExpression, in text: String, range: NSRange) -> NSRange? {
        guard range.length > 0 else { return nil }
        var result: NSRange?
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            result = match?.range
        }
        return result
    }
}
