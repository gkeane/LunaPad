import SwiftUI
import UniformTypeIdentifiers

struct OpenDocument: Identifiable {
    let id: UUID
    var fileURL: URL?
    var content: String
    var isSaved: Bool

    var displayName: String {
        if let url = fileURL {
            return url.lastPathComponent
        }
        return "Untitled"
    }
}

@MainActor
final class TabManager: ObservableObject {
    @Published var documents: [OpenDocument] = []
    @Published var selectedDocumentId: UUID?

    init() {
        let doc = OpenDocument(id: UUID(), fileURL: nil, content: "", isSaved: true)
        documents = [doc]
        selectedDocumentId = doc.id
    }

    var currentDocument: OpenDocument? {
        documents.first { $0.id == selectedDocumentId }
    }

    func newTab() {
        let doc = OpenDocument(id: UUID(), fileURL: nil, content: "", isSaved: true)
        documents.append(doc)
        selectedDocumentId = doc.id
    }

    func closeTab(id: UUID) {
        guard documents.count > 1 else { return }
        documents.removeAll { $0.id == id }
        if selectedDocumentId == id {
            selectedDocumentId = documents.first?.id
        }
    }

    func updateContent(_ id: UUID, _ content: String) {
        if let index = documents.firstIndex(where: { $0.id == id }) {
            documents[index].content = content
            documents[index].isSaved = false
        }
    }

    func updateDocument(_ id: UUID, fileURL: URL?, content: String, isSaved: Bool) {
        if let index = documents.firstIndex(where: { $0.id == id }) {
            documents[index].fileURL = fileURL
            documents[index].content = content
            documents[index].isSaved = isSaved
        }
    }

    func saveDocument(_ id: UUID, to url: URL) async throws {
        guard let doc = documents.first(where: { $0.id == id }) else { return }
        let data = doc.content.data(using: .utf8) ?? Data()
        try data.write(to: url)
        updateDocument(id, fileURL: url, content: doc.content, isSaved: true)
    }

    func loadDocument(from url: URL) async throws {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "FileError", code: 1)
        }
        let doc = OpenDocument(id: UUID(), fileURL: url, content: content, isSaved: true)
        documents.append(doc)
        selectedDocumentId = doc.id
    }
}
