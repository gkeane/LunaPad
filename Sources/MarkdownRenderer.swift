import WebKit
import SwiftUI

// MARK: - WKWebView-based markdown preview

struct MarkdownPreviewView: NSViewRepresentable {
    let text: String
    var lunaMode: LunaMode = .system

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = markdownToHTML(text, lunaMode: lunaMode)
        webView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - Markdown → HTML

private func markdownToHTML(_ markdown: String, lunaMode: LunaMode) -> String {
    let body = convertMarkdown(markdown)
    let themeCSS = markdownThemeCSS(for: lunaMode)
    return """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    \(themeCSS)
    body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        font-size: 14px;
        line-height: 1.65;
        padding: 20px 24px;
        max-width: 900px;
    }
    h1, h2, h3, h4, h5, h6 { font-weight: 600; margin-top: 1.2em; margin-bottom: 0.4em; line-height: 1.3; }
    h1 { font-size: 1.8em; border-bottom: 1px solid var(--divider-color); padding-bottom: 0.2em; }
    h2 { font-size: 1.4em; border-bottom: 1px solid var(--subtle-divider-color); padding-bottom: 0.15em; }
    h3 { font-size: 1.15em; }
    h4 { font-size: 1em; }
    p { margin-top: 0.6em; margin-bottom: 0.6em; }
    ul, ol { margin: 0.5em 0 0.5em 1.6em; }
    li { margin: 0.2em 0; }
    li > ul, li > ol { margin-top: 0.2em; margin-bottom: 0.2em; }
    code { font-family: "SF Mono", Menlo, Monaco, monospace; font-size: 0.88em;
           background: var(--code-background); color: var(--code-foreground);
           padding: 0.15em 0.35em; border-radius: 3px; }
    pre { font-family: "SF Mono", Menlo, Monaco, monospace; font-size: 0.88em;
          background: var(--code-background); color: var(--code-foreground);
          padding: 12px 14px; border-radius: 5px;
          overflow-x: auto; margin: 0.8em 0; white-space: pre; }
    pre code { background: none; padding: 0; border-radius: 0; }
    table { border-collapse: collapse; margin: 0.8em 0; width: 100%; }
    th, td { border: 1px solid var(--table-border-color); padding: 6px 12px; text-align: left; }
    th { background: var(--table-header-background); font-weight: 600; }
    tr:nth-child(even) { background: var(--table-stripe-background); }
    blockquote { border-left: 3px solid var(--blockquote-border-color);
                 padding-left: 12px; color: var(--blockquote-foreground); margin: 0.6em 0; }
    hr { border: none; border-top: 1px solid var(--divider-color); margin: 1.2em 0; }
    a { color: var(--link-color); text-decoration: none; }
    a:hover { text-decoration: underline; }
    img { max-width: 100%; }
    </style>
    </head>
    <body>\(body)</body>
    </html>
    """
}

private func markdownThemeCSS(for lunaMode: LunaMode) -> String {
    switch lunaMode {
    case .system:
        return """
        body {
            color: #1a1a1a;
            --divider-color: #d8d8d8;
            --subtle-divider-color: #e8e8e8;
            --code-background: #f3f3f3;
            --code-foreground: #1f1f1f;
            --table-border-color: #cccccc;
            --table-header-background: #f2f2f2;
            --table-stripe-background: #fafafa;
            --blockquote-border-color: #cccccc;
            --blockquote-foreground: #666666;
            --link-color: #0969da;
        }
        @media (prefers-color-scheme: dark) {
            body {
                color: #e0e0e0;
                --divider-color: #444444;
                --subtle-divider-color: #3a3a3a;
                --code-background: #2a2a2a;
                --code-foreground: #e0e0e0;
                --table-border-color: #505050;
                --table-header-background: #2a2a2a;
                --table-stripe-background: #1e1e1e;
                --blockquote-border-color: #555555;
                --blockquote-foreground: #aaaaaa;
                --link-color: #7ab8ff;
            }
        }
        """
    case .light:
        return """
        body {
            color: #1a1a1a;
            --divider-color: #d8d8d8;
            --subtle-divider-color: #e8e8e8;
            --code-background: #f3f3f3;
            --code-foreground: #1f1f1f;
            --table-border-color: #cccccc;
            --table-header-background: #f2f2f2;
            --table-stripe-background: #fafafa;
            --blockquote-border-color: #cccccc;
            --blockquote-foreground: #666666;
            --link-color: #0969da;
        }
        """
    case .dark:
        return """
        body {
            color: #e0e0e0;
            --divider-color: #444444;
            --subtle-divider-color: #3a3a3a;
            --code-background: #2a2a2a;
            --code-foreground: #e0e0e0;
            --table-border-color: #505050;
            --table-header-background: #2a2a2a;
            --table-stripe-background: #1e1e1e;
            --blockquote-border-color: #555555;
            --blockquote-foreground: #aaaaaa;
            --link-color: #7ab8ff;
        }
        """
    }
}

private func convertMarkdown(_ markdown: String) -> String {
    let lines = markdown.components(separatedBy: "\n")
    var output = ""
    var i = 0

    // State
    var inFencedCode = false
    var codeLang = ""
    var codeBuffer = ""
    var inTable = false
    var listStack: [ListType] = []  // stack of active list types
    var inBlockquote = false
    var paragraphLines: [String] = []

    enum ListType { case unordered, ordered }

    func flushParagraph() {
        guard !paragraphLines.isEmpty else { return }
        let joined = paragraphLines.joined(separator: "\n")
        output += "<p>\(inline(joined))</p>\n"
        paragraphLines = []
    }

    func closeLists() {
        while let top = listStack.last {
            output += top == .unordered ? "</ul>\n" : "</ol>\n"
            listStack.removeLast()
        }
    }

    func closeBlockquote() {
        if inBlockquote {
            output += "</blockquote>\n"
            inBlockquote = false
        }
    }

    func closeTable() {
        if inTable {
            output += "</tbody></table>\n"
            inTable = false
        }
    }

    func isTableRow(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("|") && t.hasSuffix("|") && t.count >= 3
    }

    func isSeparatorRow(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard isTableRow(t) else { return false }
        let inner = t.dropFirst().dropLast()
        return inner.allSatisfy { $0 == "-" || $0 == ":" || $0 == "|" || $0 == " " }
    }

    func parseTableRow(_ line: String, isHeader: Bool) -> String {
        let t = line.trimmingCharacters(in: .whitespaces)
        let inner = String(t.dropFirst().dropLast())
        let cells = inner.components(separatedBy: "|")
        let tag = isHeader ? "th" : "td"
        let cellsHTML = cells.map { "<\(tag)>\(inline($0.trimmingCharacters(in: .whitespaces)))</\(tag)>" }.joined()
        return "<tr>\(cellsHTML)</tr>\n"
    }

    while i < lines.count {
        let rawLine = lines[i]
        let line = rawLine

        // ── Fenced code block ──────────────────────────────────────────
        if line.hasPrefix("```") || line.hasPrefix("~~~") {
            if inFencedCode {
                let escaped = htmlEscape(codeBuffer.hasSuffix("\n") ? String(codeBuffer.dropLast()) : codeBuffer)
                let langAttr = codeLang.isEmpty ? "" : " class=\"language-\(htmlEscape(codeLang))\""
                output += "<pre><code\(langAttr)>\(escaped)</code></pre>\n"
                inFencedCode = false
                codeBuffer = ""
                codeLang = ""
            } else {
                flushParagraph()
                closeLists()
                closeBlockquote()
                closeTable()
                let marker = line.hasPrefix("```") ? "```" : "~~~"
                codeLang = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                inFencedCode = true
            }
            i += 1
            continue
        }

        if inFencedCode {
            codeBuffer += line + "\n"
            i += 1
            continue
        }

        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // ── Blank line ─────────────────────────────────────────────────
        if trimmed.isEmpty {
            flushParagraph()
            closeLists()
            closeBlockquote()
            closeTable()
            i += 1
            continue
        }

        // ── Horizontal rule ────────────────────────────────────────────
        let hrCheck = trimmed.replacingOccurrences(of: " ", with: "")
        if (hrCheck == "---" || hrCheck == "***" || hrCheck == "___") && listStack.isEmpty {
            flushParagraph()
            closeTable()
            output += "<hr>\n"
            i += 1
            continue
        }

        // ── ATX Heading ────────────────────────────────────────────────
        if trimmed.hasPrefix("#") {
            let level = trimmed.prefix(while: { $0 == "#" }).count
            if level <= 6 && trimmed.count > level {
                let next = trimmed[trimmed.index(trimmed.startIndex, offsetBy: level)]
                if next == " " {
                    flushParagraph()
                    closeLists()
                    closeBlockquote()
                    closeTable()
                    let text = String(trimmed.dropFirst(level + 1)).trimmingCharacters(in: .whitespaces)
                    output += "<h\(level)>\(inline(text))</h\(level)>\n"
                    i += 1
                    continue
                }
            }
        }

        // ── Blockquote ─────────────────────────────────────────────────
        if trimmed.hasPrefix("> ") || trimmed == ">" {
            flushParagraph()
            closeLists()
            closeTable()
            if !inBlockquote {
                output += "<blockquote>\n"
                inBlockquote = true
            }
            let content = trimmed.hasPrefix("> ") ? String(trimmed.dropFirst(2)) : ""
            output += "<p>\(inline(content))</p>\n"
            i += 1
            continue
        } else if inBlockquote && !trimmed.isEmpty {
            closeBlockquote()
        }

        // ── Table ──────────────────────────────────────────────────────
        if isTableRow(trimmed) {
            // Peek ahead: if next line is separator row, this is the header
            let nextLine = i + 1 < lines.count ? lines[i + 1].trimmingCharacters(in: .whitespaces) : ""
            if !inTable && isSeparatorRow(nextLine) {
                flushParagraph()
                closeLists()
                output += "<table><thead>\n"
                output += parseTableRow(trimmed, isHeader: true)
                output += "</thead><tbody>\n"
                inTable = true
                i += 2  // skip header + separator
                continue
            } else if inTable && !isSeparatorRow(trimmed) {
                output += parseTableRow(trimmed, isHeader: false)
                i += 1
                continue
            }
        } else if inTable {
            closeTable()
        }

        // ── List ───────────────────────────────────────────────────────
        let ulMatch = unorderedListPrefix(trimmed)
        let olMatch = orderedListPrefix(trimmed)

        if let content = ulMatch {
            flushParagraph()
            closeBlockquote()
            closeTable()
            if listStack.last != .unordered {
                if listStack.last == .ordered { output += "</ol>\n"; listStack.removeLast() }
                output += "<ul>\n"
                listStack.append(.unordered)
            }
            output += "<li>\(inline(content))</li>\n"
            i += 1
            continue
        }

        if let content = olMatch {
            flushParagraph()
            closeBlockquote()
            closeTable()
            if listStack.last != .ordered {
                if listStack.last == .unordered { output += "</ul>\n"; listStack.removeLast() }
                output += "<ol>\n"
                listStack.append(.ordered)
            }
            output += "<li>\(inline(content))</li>\n"
            i += 1
            continue
        }

        // ── Paragraph text ─────────────────────────────────────────────
        closeLists()
        closeTable()
        paragraphLines.append(line)
        i += 1
    }

    // Flush remaining state
    flushParagraph()
    closeLists()
    closeBlockquote()
    closeTable()
    if inFencedCode {
        let escaped = htmlEscape(codeBuffer)
        output += "<pre><code>\(escaped)</code></pre>\n"
    }

    return output
}

// ── Inline formatting ──────────────────────────────────────────────────────

private func inline(_ text: String) -> String {
    var s = htmlEscape(text)

    // Inline code (must come before bold/italic)
    s = replacePattern(s, regex: "`([^`]+)`") { "<code>\($0[1])</code>" }

    // Bold+italic ***text***
    s = replacePattern(s, regex: "\\*{3}([^*]+)\\*{3}") { "<strong><em>\($0[1])</em></strong>" }
    s = replacePattern(s, regex: "_{3}([^_]+)_{3}") { "<strong><em>\($0[1])</em></strong>" }

    // Bold **text** or __text__
    s = replacePattern(s, regex: "\\*{2}([^*]+)\\*{2}") { "<strong>\($0[1])</strong>" }
    s = replacePattern(s, regex: "__([^_]+)__") { "<strong>\($0[1])</strong>" }

    // Italic *text* or _text_ (single, not double)
    s = replacePattern(s, regex: "\\*([^*]+)\\*") { "<em>\($0[1])</em>" }
    s = replacePattern(s, regex: "(?<![_a-zA-Z0-9])_([^_]+)_(?![_a-zA-Z0-9])") { "<em>\($0[1])</em>" }

    // Strikethrough ~~text~~
    s = replacePattern(s, regex: "~~([^~]+)~~") { "<del>\($0[1])</del>" }

    // Links [text](url)
    s = replacePattern(s, regex: "\\[([^\\]]+)\\]\\(([^)]+)\\)") { "<a href=\"\($0[2])\">\($0[1])</a>" }

    // Images ![alt](url)
    s = replacePattern(s, regex: "!\\[([^\\]]*)\\]\\(([^)]+)\\)") { "<img alt=\"\($0[1])\" src=\"\($0[2])\">" }

    // Trailing two-space line break
    if s.hasSuffix("  ") {
        s = s.dropLast(2) + "<br>"
    }

    return s
}

private func htmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
     .replacingOccurrences(of: "<", with: "&lt;")
     .replacingOccurrences(of: ">", with: "&gt;")
     .replacingOccurrences(of: "\"", with: "&quot;")
}

private func unorderedListPrefix(_ line: String) -> String? {
    for prefix in ["- ", "* ", "+ "] {
        if line.hasPrefix(prefix) { return String(line.dropFirst(prefix.count)) }
    }
    return nil
}

private func orderedListPrefix(_ line: String) -> String? {
    // Matches "1. ", "12. ", etc.
    var idx = line.startIndex
    while idx < line.endIndex && line[idx].isNumber { idx = line.index(after: idx) }
    guard idx > line.startIndex,
          idx < line.endIndex, line[idx] == ".",
          line.index(after: idx) < line.endIndex,
          line[line.index(after: idx)] == " " else { return nil }
    return String(line[line.index(idx, offsetBy: 2)...])
}

private func replacePattern(
    _ input: String,
    regex pattern: String,
    replacement: ([String]) -> String
) -> String {
    guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return input }
    let nsInput = input as NSString
    let matches = re.matches(in: input, range: NSRange(location: 0, length: nsInput.length))
    guard !matches.isEmpty else { return input }

    var result = ""
    var lastEnd = input.startIndex

    for match in matches {
        let matchRange = Range(match.range, in: input)!
        result += input[lastEnd..<matchRange.lowerBound]
        var groups: [String] = [String(input[matchRange])]
        for g in 1..<match.numberOfRanges {
            if let r = Range(match.range(at: g), in: input) {
                groups.append(String(input[r]))
            } else {
                groups.append("")
            }
        }
        result += replacement(groups)
        lastEnd = matchRange.upperBound
    }

    result += input[lastEnd...]
    return result
}
