import CoreGraphics
import Foundation

enum LunaPadMemoryBudget {
    static let deferredSessionPersistenceDelay: TimeInterval = 0.75
    static let logRefreshCoalesceDelay: TimeInterval = 0.2
    static let maxTrackedSearchMatches = 2_000
    static let maxInlineSessionDocumentCharacters = 200_000
    static let protectedEditorCharacterLimit = 500_000
    static let largeDocumentCharacterLimit = 1_000_000
    static let asynchronousLineMetricsCharacterLimit = 100_000
    static let largeFileViewerChunkBytes = 262_144
    static let largeFileViewerRetainedChunkCount = 3
    static let largeFileViewerPrefetchDistance: CGFloat = 240
    static let markdownPreviewCharacterLimit = 250_000
    static let logHighlightCharacterLimit = 250_000
    static let visibleLogHighlightMarginCharacters = 4_096
    static let maxRetainedLogCharacters = 500_000
    static let maxInitialLogReadBytes = 1_000_000

    static func trimmedLogContent(_ content: String) -> String {
        guard content.count > maxRetainedLogCharacters else { return content }
        let trimmed = String(content.suffix(maxRetainedLogCharacters))
        guard let firstNewline = trimmed.firstIndex(of: "\n") else { return trimmed }
        return String(trimmed[trimmed.index(after: firstNewline)...])
    }

    static func fileSize(at url: URL) -> UInt64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return UInt64(values?.fileSize ?? 0)
    }

    static func loadDocumentContent(from url: URL) throws -> String {
        if url.pathExtension.lowercased() == "log" {
            return try loadInitialLogContent(from: url)
        }

        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return String(decoding: data, as: UTF8.self)
    }

    static func loadLargeFileChunk(from url: URL, startingAt offset: UInt64) throws -> LargeFileChunk {
        let fileSize = fileSize(at: url)
        let boundedOffset = min(offset, fileSize)
        let bytesToRead = min(UInt64(largeFileViewerChunkBytes), fileSize - boundedOffset)

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        try handle.seek(toOffset: boundedOffset)
        let data = try handle.read(upToCount: Int(bytesToRead)) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        let endOffset = boundedOffset + UInt64(data.count)

        return LargeFileChunk(
            text: text,
            startOffset: boundedOffset,
            endOffset: endOffset,
            fileSize: fileSize
        )
    }

    static func loadInitialLogContent(from url: URL) throws -> String {
        let fileSize = fileSize(at: url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let startOffset = fileSize > UInt64(maxInitialLogReadBytes)
            ? fileSize - UInt64(maxInitialLogReadBytes)
            : 0

        try handle.seek(toOffset: startOffset)
        let data = try handle.readToEnd() ?? Data()
        let content = String(decoding: data, as: UTF8.self)
        return trimmedLogContent(content)
    }

    static func loadAppendedLogContent(from url: URL, startingAt offset: UInt64) throws -> (content: String, nextOffset: UInt64) {
        let fileSize = fileSize(at: url)
        guard fileSize >= offset else {
            return (try loadInitialLogContent(from: url), fileSize)
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        try handle.seek(toOffset: offset)
        let data = try handle.readToEnd() ?? Data()
        return (String(decoding: data, as: UTF8.self), fileSize)
    }

    static func refreshLogContent(currentContent: String, from url: URL, startingAt offset: UInt64) throws -> (content: String, nextOffset: UInt64)? {
        let fileSize = fileSize(at: url)

        if fileSize >= offset {
            let appended = try loadAppendedLogContent(from: url, startingAt: offset)
            if !appended.content.isEmpty {
                return (
                    trimmedLogContent(currentContent + appended.content),
                    appended.nextOffset
                )
            }
        }

        let refreshed = try loadInitialLogContent(from: url)
        return (refreshed, fileSize)
    }
}

struct LargeFileChunk {
    let text: String
    let startOffset: UInt64
    let endOffset: UInt64
    let fileSize: UInt64

    var lineBreakCount: Int {
        text.reduce(into: 0) { count, character in
            if character == "\n" {
                count += 1
            }
        }
    }

    var hasPrevious: Bool {
        startOffset > 0
    }

    var hasNext: Bool {
        endOffset < fileSize
    }
}
