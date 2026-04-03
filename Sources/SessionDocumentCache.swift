import Foundation

enum SessionDocumentCache {
    private static let directoryName = "SessionDocumentCache"
    private static let appDirectoryName = "LunaPad"

    private static var applicationSupportDirectoryURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseURL.appendingPathComponent(appDirectoryName, isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    private static var legacyCacheDirectoryURL: URL {
        let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseURL.appendingPathComponent(appDirectoryName, isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    private static var allDirectoryURLs: [URL] {
        [applicationSupportDirectoryURL, legacyCacheDirectoryURL]
    }

    static func cacheFileName(for id: UUID) -> String {
        "\(id.uuidString).txt"
    }

    static func cacheURL(for fileName: String) -> URL {
        applicationSupportDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
    }

    static func write(content: String, for id: UUID) -> String? {
        let fileName = cacheFileName(for: id)
        let url = cacheURL(for: fileName)
        do {
            try FileManager.default.createDirectory(
                at: applicationSupportDirectoryURL,
                withIntermediateDirectories: true
            )
            try content.write(to: url, atomically: true, encoding: .utf8)
            return fileName
        } catch {
            return nil
        }
    }

    static func loadContent(fileName: String) throws -> String {
        let fileManager = FileManager.default
        let urls = [
            applicationSupportDirectoryURL.appendingPathComponent(fileName, isDirectory: false),
            legacyCacheDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
        ]

        for url in urls where fileManager.fileExists(atPath: url.path) {
            return try String(contentsOf: url, encoding: .utf8)
        }

        throw NSError(domain: "LunaPad.SessionDocumentCache", code: 404, userInfo: [
            NSLocalizedDescriptionKey: "Cached session document could not be found."
        ])
    }

    static func remove(fileName: String?) {
        guard let fileName else { return }
        for directoryURL in allDirectoryURLs {
            let url = directoryURL.appendingPathComponent(fileName, isDirectory: false)
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func cleanup(retaining retainedFileNames: Set<String>) {
        for directoryURL in allDirectoryURLs {
            guard let fileURLs = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            ) else {
                continue
            }

            for url in fileURLs where !retainedFileNames.contains(url.lastPathComponent) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    static func migrateRetainedFilesToApplicationSupport(retaining retainedFileNames: Set<String>) {
        guard !retainedFileNames.isEmpty else { return }
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(
                at: applicationSupportDirectoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            return
        }

        for fileName in retainedFileNames {
            let destinationURL = applicationSupportDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
            if fileManager.fileExists(atPath: destinationURL.path) {
                continue
            }

            let legacyURL = legacyCacheDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
            guard fileManager.fileExists(atPath: legacyURL.path) else { continue }

            do {
                try fileManager.moveItem(at: legacyURL, to: destinationURL)
            } catch {
                if let content = try? String(contentsOf: legacyURL, encoding: .utf8) {
                    try? content.write(to: destinationURL, atomically: true, encoding: .utf8)
                    try? fileManager.removeItem(at: legacyURL)
                }
            }
        }
    }
}
