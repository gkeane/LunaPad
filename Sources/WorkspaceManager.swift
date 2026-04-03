import Combine
import Foundation

enum SessionPersistenceMode {
    case immediate
    case deferred
}

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

    var icon: String {
        switch self {
        case .editor: return "doc.plaintext"
        case .split: return "rectangle.split.2x1"
        case .preview: return "eye"
        }
    }
}

struct OpenDocument: Identifiable, Codable, Equatable {
    let id: UUID
    var fileURL: URL?
    var content: String
    var isSaved: Bool
    var requiresDiskReload: Bool = false
    var byteCount: Int = 0
    var sessionCacheFileName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case fileURL
        case content
        case isSaved
        case requiresDiskReload
        case byteCount
        case sessionCacheFileName
    }

    init(
        id: UUID,
        fileURL: URL?,
        content: String,
        isSaved: Bool,
        requiresDiskReload: Bool = false,
        byteCount: Int = 0,
        sessionCacheFileName: String? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.content = content
        self.isSaved = isSaved
        self.requiresDiskReload = requiresDiskReload
        self.byteCount = byteCount
        self.sessionCacheFileName = sessionCacheFileName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fileURL = try container.decodeIfPresent(URL.self, forKey: .fileURL)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        isSaved = try container.decodeIfPresent(Bool.self, forKey: .isSaved) ?? true
        requiresDiskReload = try container.decodeIfPresent(Bool.self, forKey: .requiresDiskReload) ?? false
        byteCount = try container.decodeIfPresent(Int.self, forKey: .byteCount) ?? 0
        sessionCacheFileName = try container.decodeIfPresent(String.self, forKey: .sessionCacheFileName)
    }

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

    var isLog: Bool {
        guard let fileURL else { return false }
        return fileURL.pathExtension.lowercased() == "log"
    }

    var estimatedSize: Int {
        max(content.count, byteCount)
    }

    var isLargeDocument: Bool {
        estimatedSize >= LunaPadMemoryBudget.largeDocumentCharacterLimit
    }

    var usesProtectedEditorMode: Bool {
        estimatedSize >= LunaPadMemoryBudget.protectedEditorCharacterLimit &&
        isSaved &&
        fileURL != nil &&
        !isLog
    }

    var usesChunkedViewer: Bool {
        usesProtectedEditorMode &&
        sessionCacheFileName == nil &&
        content.isEmpty
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

    var onStateChange: ((SessionPersistenceMode) -> Void)?

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

    func sessionSnapshot() -> TabManagerSnapshot {
        TabManagerSnapshot(
            documents: documents.map { persistedSnapshot(for: $0) },
            selectedDocumentId: selectedDocumentId
        )
    }

    func newTab() {
        let doc = OpenDocument(id: UUID(), fileURL: nil, content: "", isSaved: true)
        documents.append(doc)
        selectedDocumentId = doc.id
        onStateChange?(.immediate)
    }

    func selectTab(id: UUID) {
        selectedDocumentId = id
        onStateChange?(.immediate)
    }

    func closeTab(id: UUID) {
        guard documents.count > 1 else { return }
        documents.removeAll { $0.id == id }
        if selectedDocumentId == id {
            selectedDocumentId = documents.first?.id
        }
        onStateChange?(.immediate)
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
        onStateChange?(.immediate)
    }

    func updateContent(_ id: UUID, _ content: String) {
        if let index = documents.firstIndex(where: { $0.id == id }) {
            documents[index].content = content
            documents[index].isSaved = false
            documents[index].requiresDiskReload = false
            onStateChange?(.deferred)
        }
    }

    func updateDocument(
        _ id: UUID,
        fileURL: URL?,
        content: String,
        isSaved: Bool,
        persistenceMode: SessionPersistenceMode = .immediate
    ) {
        if let index = documents.firstIndex(where: { $0.id == id }) {
            documents[index].fileURL = fileURL
            documents[index].content = content
            documents[index].isSaved = isSaved
            if isSaved {
                SessionDocumentCache.remove(fileName: documents[index].sessionCacheFileName)
                documents[index].sessionCacheFileName = nil
            }
            onStateChange?(persistenceMode)
        }
    }

    func saveDocument(_ id: UUID, to url: URL) async throws {
        guard let doc = documents.first(where: { $0.id == id }) else { return }
        let data = doc.content.data(using: .utf8) ?? Data()
        try await Task.detached(priority: .userInitiated) {
            try data.write(to: url, options: .atomic)
        }.value
        updateDocument(id, fileURL: url, content: doc.content, isSaved: true)
    }

    func loadDocument(from url: URL) async throws {
        let byteCount = Int(LunaPadMemoryBudget.fileSize(at: url))
        let isLog = url.pathExtension.lowercased() == "log"
        let shouldUseChunkedViewer = byteCount >= LunaPadMemoryBudget.protectedEditorCharacterLimit && !isLog

        let doc = OpenDocument(
            id: UUID(),
            fileURL: url,
            content: "",
            isSaved: true,
            requiresDiskReload: !shouldUseChunkedViewer,
            byteCount: byteCount
        )
        documents.append(doc)
        selectedDocumentId = doc.id
        onStateChange?(.immediate)
        if !shouldUseChunkedViewer {
            try await ensureDocumentContentLoaded(doc.id)
        }
    }

    func ensureDocumentContentLoaded(_ id: UUID) async throws {
        guard let document = documents.first(where: { $0.id == id }),
              document.requiresDiskReload else { return }

        if document.usesChunkedViewer {
            if let index = documents.firstIndex(where: { $0.id == id }) {
                documents[index].requiresDiskReload = false
            }
            return
        }

        let content = try await Task.detached(priority: .userInitiated) {
            if let sessionCacheFileName = document.sessionCacheFileName {
                return try SessionDocumentCache.loadContent(fileName: sessionCacheFileName)
            }
            guard let url = document.fileURL else {
                throw NSError(domain: "LunaPad.Load", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "No source is available for this document."
                ])
            }
            return try LunaPadMemoryBudget.loadDocumentContent(from: url)
        }.value

        if let index = documents.firstIndex(where: { $0.id == id }) {
            documents[index].fileURL = document.fileURL
            documents[index].content = content
            documents[index].isSaved = document.isSaved
            documents[index].requiresDiskReload = false
            documents[index].byteCount = max(document.byteCount, content.count)
            onStateChange?(.deferred)
        }
    }

    func loadFullDocumentContent(_ id: UUID) async throws {
        guard let document = documents.first(where: { $0.id == id }) else { return }

        let content = try await Task.detached(priority: .userInitiated) {
            if let sessionCacheFileName = document.sessionCacheFileName {
                return try SessionDocumentCache.loadContent(fileName: sessionCacheFileName)
            }
            guard let url = document.fileURL else {
                throw NSError(domain: "LunaPad.Load", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "No source is available for this document."
                ])
            }
            return try LunaPadMemoryBudget.loadDocumentContent(from: url)
        }.value

        if let index = documents.firstIndex(where: { $0.id == id }) {
            documents[index].content = content
            documents[index].requiresDiskReload = false
            documents[index].byteCount = max(documents[index].byteCount, content.count)
            onStateChange?(.deferred)
        }
    }

    func unloadChunkedLargeDocument(_ id: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        let document = documents[index]
        guard document.usesProtectedEditorMode else { return }

        documents[index].content = ""
        documents[index].requiresDiskReload = false
        onStateChange?(.deferred)
    }

    private func persistedSnapshot(for document: OpenDocument) -> OpenDocument {
        if !document.isSaved {
            if document.requiresDiskReload,
               document.content.isEmpty,
               document.sessionCacheFileName != nil {
                return document
            }

            guard let cacheFileName = SessionDocumentCache.write(content: document.content, for: document.id) else {
                return document
            }
            var cached = document
            cached.content = ""
            cached.requiresDiskReload = true
            cached.byteCount = document.content.count
            cached.sessionCacheFileName = cacheFileName
            return cached
        }

        guard document.isSaved,
              document.fileURL != nil,
              document.content.count > LunaPadMemoryBudget.maxInlineSessionDocumentCharacters else {
            return document
        }

        var lightweight = document
        lightweight.content = ""
        lightweight.requiresDiskReload = false
        lightweight.sessionCacheFileName = nil
        return lightweight
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
    var onStateChange: ((SessionPersistenceMode) -> Void)? {
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
            documents: tabManager.sessionSnapshot().documents,
            selectedDocumentId: tabManager.selectedDocumentId
        )
    }

    private func bindChanges() {
        $name
            .dropFirst()
            .sink { [weak self] _ in self?.onStateChange?(.immediate) }
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
    private var pendingSessionPersistence: DispatchWorkItem?

    init() {
        restoreRecentItems()
        if !restoreSession() {
            SessionDocumentCache.cleanup(retaining: [])
            _ = newWorkspace(selectAndRename: false)
            persistSessionNow()
        } else {
            cleanupSessionCachesForCurrentState()
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
        persistSessionNow()
        return workspace
    }

    func selectWorkspace(id: UUID) {
        selectedWorkspaceId = id
        persistSessionNow()
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
        persistSessionNow()
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

        persistSessionNow()
    }

    func commitName(for workspace: WorkspaceState) {
        objectWillChange.send()
        workspace.name = workspace.displayName
        workspace.isRenaming = false
        persistSessionNow()
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
        persistSessionNow()
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
        workspace.onStateChange = { [weak self] mode in
            self?.persistSession(using: mode)
        }
        return workspace
    }

    private func persistSession(using mode: SessionPersistenceMode) {
        switch mode {
        case .immediate:
            persistSessionNow()
        case .deferred:
            scheduleSessionPersistence()
        }
    }

    private func scheduleSessionPersistence() {
        pendingSessionPersistence?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.persistSessionNow()
        }
        pendingSessionPersistence = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + LunaPadMemoryBudget.deferredSessionPersistenceDelay,
            execute: workItem
        )
    }

    private func persistSessionNow() {
        pendingSessionPersistence?.cancel()
        pendingSessionPersistence = nil
        let snapshot = WorkspaceSessionSnapshot(
            selectedWorkspaceId: selectedWorkspaceId,
            workspaces: workspaces.map { $0.snapshot() }
        )
        cleanupSessionCaches(retaining: retainedCacheFileNames(for: snapshot))

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: sessionKey)
    }

    func flushSessionPersistence() {
        persistSessionNow()
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

    private func retainedCacheFileNames(for snapshot: WorkspaceSessionSnapshot) -> Set<String> {
        Set(
            snapshot.workspaces
                .flatMap(\.documents)
                .compactMap(\.sessionCacheFileName)
        )
    }

    private func retainedCacheFileNamesForCurrentState() -> Set<String> {
        retainedCacheFileNames(for: WorkspaceSessionSnapshot(
            selectedWorkspaceId: selectedWorkspaceId,
            workspaces: workspaces.map { $0.snapshot() }
        ))
    }

    private func cleanupSessionCachesForCurrentState() {
        cleanupSessionCaches(retaining: retainedCacheFileNamesForCurrentState())
    }

    private func cleanupSessionCaches(retaining retainedCacheFiles: Set<String>) {
        SessionDocumentCache.migrateRetainedFilesToApplicationSupport(retaining: retainedCacheFiles)
        SessionDocumentCache.cleanup(retaining: retainedCacheFiles)
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
