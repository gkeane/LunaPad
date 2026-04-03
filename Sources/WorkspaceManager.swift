import Combine
import Foundation

enum MarkdownDisplayMode: String, CaseIterable, Identifiable {
    case editor
    case split
    case preview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .editor: return "Editor"
        case .split: return "Split"
        case .preview: return "Preview"
        }
    }
}

struct OpenDocument: Identifiable, Codable, Equatable {
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

    var isMarkdown: Bool {
        guard let fileURL else { return false }
        let extensionValue = fileURL.pathExtension.lowercased()
        return ["md", "markdown", "mdown", "mkd"].contains(extensionValue)
    }
}

struct RecentFileEntry: Codable, Equatable, Identifiable {
    var url: URL

    var id: String { url.absoluteString }

    var displayName: String {
        url.lastPathComponent
    }
}

struct RecentItemsSnapshot: Codable {
    var recentFiles: [RecentFileEntry]
    var recentWorkspaces: [WorkspaceSnapshot]
}

struct TabManagerSnapshot: Codable {
    var documents: [OpenDocument]
    var selectedDocumentId: UUID?
}

struct WorkspaceSnapshot: Codable, Identifiable {
    var id: UUID
    var name: String
    var documents: [OpenDocument]
    var selectedDocumentId: UUID?
}

struct WorkspaceSessionSnapshot: Codable {
    var selectedWorkspaceId: UUID?
    var workspaces: [WorkspaceSnapshot]
}

@MainActor
final class TabManager: ObservableObject {
    @Published var documents: [OpenDocument]
    @Published var selectedDocumentId: UUID?

    var onStateChange: (() -> Void)?

    init(snapshot: TabManagerSnapshot? = nil) {
        if let snapshot, !snapshot.documents.isEmpty {
            documents = snapshot.documents
            selectedDocumentId = snapshot.selectedDocumentId ?? snapshot.documents.first?.id
        } else {
            let doc = OpenDocument(id: UUID(), fileURL: nil, content: "", isSaved: true)
            documents = [doc]
            selectedDocumentId = doc.id
        }
    }

    var currentDocument: OpenDocument? {
        documents.first { $0.id == selectedDocumentId }
    }

    func snapshot() -> TabManagerSnapshot {
        TabManagerSnapshot(documents: documents, selectedDocumentId: selectedDocumentId)
    }

    func newTab() {
        let doc = OpenDocument(id: UUID(), fileURL: nil, content: "", isSaved: true)
        documents.append(doc)
        selectedDocumentId = doc.id
        onStateChange?()
    }

    func selectTab(id: UUID) {
        selectedDocumentId = id
        onStateChange?()
    }

    func closeTab(id: UUID) {
        guard documents.count > 1 else { return }
        documents.removeAll { $0.id == id }
        if selectedDocumentId == id {
            selectedDocumentId = documents.first?.id
        }
        onStateChange?()
    }

    func moveTab(id: UUID, before targetID: UUID?) {
        guard let fromIndex = documents.firstIndex(where: { $0.id == id }) else { return }
        let document = documents.remove(at: fromIndex)

        let insertionIndex: Int
        if let targetID, let targetIndex = documents.firstIndex(where: { $0.id == targetID }) {
            insertionIndex = targetIndex
        } else {
            insertionIndex = documents.endIndex
        }

        documents.insert(document, at: insertionIndex)
        onStateChange?()
    }

    func updateContent(_ id: UUID, _ content: String) {
        if let index = documents.firstIndex(where: { $0.id == id }) {
            documents[index].content = content
            documents[index].isSaved = false
            onStateChange?()
        }
    }

    func updateDocument(_ id: UUID, fileURL: URL?, content: String, isSaved: Bool) {
        if let index = documents.firstIndex(where: { $0.id == id }) {
            documents[index].fileURL = fileURL
            documents[index].content = content
            documents[index].isSaved = isSaved
            onStateChange?()
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
        onStateChange?()
    }
}

@MainActor
final class WorkspaceState: ObservableObject, Identifiable {
    let id: UUID
    @Published var name: String
    @Published var isRenaming: Bool
    @Published var markdownDisplayMode: MarkdownDisplayMode = .editor
    let tabManager: TabManager
    let findReplaceManager: FindReplaceManager

    private var cancellables: Set<AnyCancellable> = []
    var onStateChange: (() -> Void)? {
        didSet {
            tabManager.onStateChange = onStateChange
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        isRenaming: Bool = false,
        tabManager: TabManager,
        findReplaceManager: FindReplaceManager
    ) {
        self.id = id
        self.name = name
        self.isRenaming = isRenaming
        self.tabManager = tabManager
        self.findReplaceManager = findReplaceManager
        bindChanges()
    }

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Workspace" : trimmedName
    }

    func snapshot() -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            id: id,
            name: displayName,
            documents: tabManager.documents,
            selectedDocumentId: tabManager.selectedDocumentId
        )
    }

    private func bindChanges() {
        $name
            .dropFirst()
            .sink { [weak self] _ in self?.onStateChange?() }
            .store(in: &cancellables)
    }
}

@MainActor
final class WorkspaceManager: ObservableObject {
    @Published var workspaces: [WorkspaceState] = []
    @Published var selectedWorkspaceId: UUID?
    @Published var recentFiles: [RecentFileEntry] = []
    @Published var recentWorkspaces: [WorkspaceSnapshot] = []

    private let sessionKey = "LunaPadWorkspaceSession"
    private let recentItemsKey = "LunaPadRecentItems"
    private let maxRecentFiles = 20
    private let maxRecentWorkspaces = 10

    init() {
        restoreRecentItems()
        if !restoreSession() {
            _ = newWorkspace(selectAndRename: false)
            persistSession()
        }
    }

    var currentWorkspace: WorkspaceState? {
        guard let selectedWorkspaceId else { return workspaces.first }
        return workspaces.first(where: { $0.id == selectedWorkspaceId }) ?? workspaces.first
    }

    var currentTabManager: TabManager? {
        currentWorkspace?.tabManager
    }

    var currentFindReplaceManager: FindReplaceManager? {
        currentWorkspace?.findReplaceManager
    }

    @discardableResult
    func newWorkspace(selectAndRename: Bool = true) -> WorkspaceState {
        let workspace = makeWorkspace(
            id: UUID(),
            name: nextWorkspaceName(),
            documents: nil,
            selectedDocumentId: nil,
            isRenaming: selectAndRename
        )
        workspaces.append(workspace)
        selectedWorkspaceId = workspace.id
        persistSession()
        return workspace
    }

    func selectWorkspace(id: UUID) {
        selectedWorkspaceId = id
        persistSession()
    }

    func moveWorkspace(id: UUID, before targetID: UUID?) {
        guard let fromIndex = workspaces.firstIndex(where: { $0.id == id }) else { return }
        let workspace = workspaces.remove(at: fromIndex)

        let insertionIndex: Int
        if let targetID, let targetIndex = workspaces.firstIndex(where: { $0.id == targetID }) {
            insertionIndex = targetIndex
        } else {
            insertionIndex = workspaces.endIndex
        }

        workspaces.insert(workspace, at: insertionIndex)
        persistSession()
    }

    func closeWorkspace(id: UUID) {
        guard workspaces.count > 1, let index = workspaces.firstIndex(where: { $0.id == id }) else {
            return
        }

        rememberRecentWorkspace(workspaces[index].snapshot())
        let wasSelected = selectedWorkspaceId == id
        workspaces.remove(at: index)

        if wasSelected {
            let replacementIndex = min(index, workspaces.count - 1)
            selectedWorkspaceId = workspaces[replacementIndex].id
        }

        persistSession()
    }

    func commitName(for workspace: WorkspaceState) {
        objectWillChange.send()
        workspace.name = workspace.displayName
        workspace.isRenaming = false
        persistSession()
    }

    func noteRecentFile(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        recentFiles.removeAll { $0.url.standardizedFileURL == standardizedURL }
        recentFiles.insert(RecentFileEntry(url: standardizedURL), at: 0)
        if recentFiles.count > maxRecentFiles {
            recentFiles = Array(recentFiles.prefix(maxRecentFiles))
        }
        persistRecentItems()
    }

    func reopenRecentWorkspace(id: UUID) {
        guard let snapshot = recentWorkspaces.first(where: { $0.id == id }) else { return }
        if let existingIndex = workspaces.firstIndex(where: { $0.id == id }) {
            selectedWorkspaceId = workspaces[existingIndex].id
        } else {
            let workspace = makeWorkspace(
                id: snapshot.id,
                name: snapshot.name,
                documents: snapshot.documents,
                selectedDocumentId: snapshot.selectedDocumentId,
                isRenaming: false
            )
            workspaces.append(workspace)
            selectedWorkspaceId = workspace.id
        }
        persistSession()
    }

    func clearRecentFiles() {
        recentFiles = []
        persistRecentItems()
    }

    func clearRecentWorkspaces() {
        recentWorkspaces = []
        persistRecentItems()
    }

    private func nextWorkspaceName() -> String {
        if workspaces.isEmpty {
            return "Workspace"
        }

        return "Workspace \(workspaces.count + 1)"
    }

    private func makeWorkspace(
        id: UUID,
        name: String,
        documents: [OpenDocument]?,
        selectedDocumentId: UUID?,
        isRenaming: Bool
    ) -> WorkspaceState {
        let tabManager = TabManager(
            snapshot: TabManagerSnapshot(
                documents: documents ?? [],
                selectedDocumentId: selectedDocumentId
            )
        )
        let workspace = WorkspaceState(
            id: id,
            name: name,
            isRenaming: isRenaming,
            tabManager: tabManager,
            findReplaceManager: FindReplaceManager()
        )
        workspace.onStateChange = { [weak self] in
            self?.persistSession()
        }
        return workspace
    }

    private func persistSession() {
        let snapshot = WorkspaceSessionSnapshot(
            selectedWorkspaceId: selectedWorkspaceId,
            workspaces: workspaces.map { $0.snapshot() }
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: sessionKey)
    }

    private func restoreSession() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: sessionKey),
              let snapshot = try? JSONDecoder().decode(WorkspaceSessionSnapshot.self, from: data),
              !snapshot.workspaces.isEmpty else {
            return false
        }

        workspaces = snapshot.workspaces.map {
            makeWorkspace(
                id: $0.id,
                name: $0.name,
                documents: $0.documents,
                selectedDocumentId: $0.selectedDocumentId,
                isRenaming: false
            )
        }
        selectedWorkspaceId = snapshot.selectedWorkspaceId ?? workspaces.first?.id
        return true
    }

    private func rememberRecentWorkspace(_ snapshot: WorkspaceSnapshot) {
        recentWorkspaces.removeAll { $0.id == snapshot.id }
        recentWorkspaces.insert(snapshot, at: 0)
        if recentWorkspaces.count > maxRecentWorkspaces {
            recentWorkspaces = Array(recentWorkspaces.prefix(maxRecentWorkspaces))
        }
        persistRecentItems()
    }

    private func persistRecentItems() {
        let snapshot = RecentItemsSnapshot(
            recentFiles: recentFiles,
            recentWorkspaces: recentWorkspaces
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: recentItemsKey)
    }

    private func restoreRecentItems() {
        guard let data = UserDefaults.standard.data(forKey: recentItemsKey),
              let snapshot = try? JSONDecoder().decode(RecentItemsSnapshot.self, from: data) else {
            return
        }
        recentFiles = snapshot.recentFiles
        recentWorkspaces = snapshot.recentWorkspaces
    }
}
