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

    private var matches: [NSRange] = []

    var currentMatch: NSRange? {
        guard matches.indices.contains(currentMatchIndex) else { return nil }
        return matches[currentMatchIndex]
    }

    func updateMatches(in text: String) {
        let previousLocation = currentMatch?.location
        matches = findAllMatches(in: text)
        matchCount = matches.count

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

    func findNext(in text: String) -> NSRange? {
        updateMatches(in: text)
        guard !matches.isEmpty else { return nil }
        let next = (currentMatchIndex + 1) % matches.count
        currentMatchIndex = next
        return matches[next]
    }

    func findPrevious(in text: String) -> NSRange? {
        updateMatches(in: text)
        guard !matches.isEmpty else { return nil }
        let prev = currentMatchIndex == 0 ? matches.count - 1 : currentMatchIndex - 1
        currentMatchIndex = prev
        return matches[prev]
    }

    func replaceCurrent(in text: String) -> String {
        updateMatches(in: text)
        guard let range = currentMatch else { return text }
        let nsText = text as NSString
        return nsText.replacingCharacters(in: range, with: replaceText)
    }

    func replaceAll(in text: String) -> String {
        updateMatches(in: text)
        guard !matches.isEmpty else { return text }
        var result = text as NSString
        for range in matches.reversed() {
            result = result.replacingCharacters(in: range, with: replaceText) as NSString
        }
        return String(result)
    }

    private func findAllMatches(in text: String) -> [NSRange] {
        guard !findText.isEmpty else { return [] }
        let nsText = text as NSString
        let pattern = wholeWords ? "\\b\(NSRegularExpression.escapedPattern(for: findText))\\b" : NSRegularExpression.escapedPattern(for: findText)
        let options: NSRegularExpression.Options = caseSensitive ? [] : .caseInsensitive

        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        return regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)).map { $0.range }
    }
}
