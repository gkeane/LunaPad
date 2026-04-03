import SwiftUI
import UniformTypeIdentifiers

private enum DragPayload {
    static let workspace = "lunapad.workspace"
    static let document = "lunapad.document"
}

struct MainView: View {
    @ObservedObject var workspaceManager: WorkspaceManager
    @AppStorage(LunaMode.storageKey) private var lunaModeRawValue = LunaMode.system.rawValue
    @AppStorage("wordWrap") private var wordWrap: Bool = true
    @AppStorage("fontName") private var fontName: String = "Menlo"
    @AppStorage("fontSize") private var fontSize: Double = 13

    private var lunaMode: Binding<LunaMode> {
        Binding(
            get: { LunaMode(rawValue: lunaModeRawValue) ?? .system },
            set: { lunaModeRawValue = $0.rawValue }
        )
    }

    private var editorFont: NSFont {
        NSFont(name: fontName, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceStrip(workspaceManager: workspaceManager, lunaMode: lunaMode)

            if let workspace = workspaceManager.currentWorkspace {
                WorkspaceContentView(
                    workspace: workspace,
                    wordWrap: wordWrap,
                    font: editorFont
                )
                .id(workspace.id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fontChanged)) { note in
            if let font = note.object as? NSFont {
                fontName = font.fontName
                fontSize = Double(font.pointSize)
            }
        }
    }
}

private struct WorkspaceStrip: View {
    @ObservedObject var workspaceManager: WorkspaceManager
    @Binding var lunaMode: LunaMode
    @State private var draggedWorkspaceID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(workspaceManager.workspaces) { workspace in
                            WorkspaceTabButton(
                                workspace: workspace,
                                isSelected: workspaceManager.selectedWorkspaceId == workspace.id,
                                canClose: workspaceManager.workspaces.count > 1,
                                onSelect: { workspaceManager.selectWorkspace(id: workspace.id) },
                                onCommitRename: { workspaceManager.commitName(for: workspace) },
                                onClose: { workspaceManager.closeWorkspace(id: workspace.id) },
                                onDragStarted: {
                                    draggedWorkspaceID = workspace.id
                                    return provider(for: workspace.id, type: DragPayload.workspace)
                                }
                            )
                            .id(workspace.id)
                            .onDrop(
                                of: [.text],
                                delegate: WorkspaceDropDelegate(
                                    targetWorkspaceID: workspace.id,
                                    draggedWorkspaceID: $draggedWorkspaceID,
                                    workspaceManager: workspaceManager
                                )
                            )
                        }

                        Color.clear
                            .frame(width: 18, height: 34)
                            .onDrop(
                                of: [.text],
                                delegate: WorkspaceDropDelegate(
                                    targetWorkspaceID: nil,
                                    draggedWorkspaceID: $draggedWorkspaceID,
                                    workspaceManager: workspaceManager
                                )
                            )
                    }
                }
                .mask(
                    HStack(spacing: 0) {
                        Color.black
                        LinearGradient(
                            colors: [.black, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 20)
                    }
                )
                .onChange(of: workspaceManager.selectedWorkspaceId) { id in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }

            Divider()
                .frame(height: 18)
                .padding(.leading, 6)

            LunaModePicker(mode: $lunaMode)
                .padding(.horizontal, 8)

            Button(action: { workspaceManager.newWorkspace() }) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .help("New Workspace")
        }
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct WorkspaceTabButton: View {
    @ObservedObject var workspace: WorkspaceState
    @ObservedObject private var tabManager: TabManager
    let isSelected: Bool
    let canClose: Bool
    let onSelect: () -> Void
    let onCommitRename: () -> Void
    let onClose: () -> Void
    let onDragStarted: () -> NSItemProvider
    @FocusState private var nameFieldFocused: Bool

    init(
        workspace: WorkspaceState,
        isSelected: Bool,
        canClose: Bool,
        onSelect: @escaping () -> Void,
        onCommitRename: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onDragStarted: @escaping () -> NSItemProvider
    ) {
        self.workspace = workspace
        self._tabManager = ObservedObject(wrappedValue: workspace.tabManager)
        self.isSelected = isSelected
        self.canClose = canClose
        self.onSelect = onSelect
        self.onCommitRename = onCommitRename
        self.onClose = onClose
        self.onDragStarted = onDragStarted
    }

    private var hasUnsavedChanges: Bool {
        tabManager.documents.contains(where: { !$0.isSaved })
    }

    var body: some View {
        HStack(spacing: 6) {
            if workspace.isRenaming {
                TextField("", text: $workspace.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .focused($nameFieldFocused)
                    .frame(width: 150)
                    .onAppear { nameFieldFocused = true }
                    .onSubmit(onCommitRename)
                    .onExitCommand(perform: onCommitRename)
            } else {
                Text(workspace.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        onSelect()
                        workspace.isRenaming = true
                    }
                    .help("Double-click to rename")
            }

            Text("\(tabManager.documents.count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(isSelected ? 0.14 : 0.08)))

            if hasUnsavedChanges {
                Circle()
                    .fill(.primary)
                    .frame(width: 5, height: 5)
            }

            if canClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close Workspace")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color(nsColor: .selectedControlColor).opacity(0.32) : Color.clear)
        .contentShape(Rectangle())
        .help(workspace.displayName)
        .onTapGesture(perform: onSelect)
        .onDrag { onDragStarted() }
        .overlay(alignment: .trailing) { Divider() }
    }
}

private struct WorkspaceContentView: View {
    @ObservedObject var workspace: WorkspaceState
    @ObservedObject private var tabManager: TabManager
    @AppStorage(LunaMode.storageKey) private var lunaModeRawValue = LunaMode.system.rawValue
    @AppStorage("showLineNumbers") private var showLineNumbers: Bool = false
    let wordWrap: Bool
    let font: NSFont
    @State private var cursorPosition = CursorPosition()
    @State private var selectedRange: NSRange?
    @State private var selectedRangeScrollRequestID = 0
    @State private var logAutoScroll = true
    @State private var logWatcher: LogFileWatcher?
    @State private var pendingLogRefresh: DispatchWorkItem?
    @State private var logRefreshTask: Task<Void, Never>?
    @State private var logRefreshRequestID = 0
    @State private var logFileOffset: UInt64 = 0
    @State private var loadingDocumentId: UUID?
    @State private var loadingDocumentError: String?
    @State private var largeDocumentEditorOverrides: Set<UUID> = []

    private var findReplaceManager: FindReplaceManager { workspace.findReplaceManager }
    private var lunaMode: LunaMode {
        LunaMode(rawValue: lunaModeRawValue) ?? .system
    }

    init(workspace: WorkspaceState, wordWrap: Bool, font: NSFont) {
        self.workspace = workspace
        self._tabManager = ObservedObject(wrappedValue: workspace.tabManager)
        self.wordWrap = wordWrap
        self.font = font
    }

    var body: some View {
        VStack(spacing: 0) {
            FileTabStrip(
                tabManager: tabManager,
                isMarkdownDoc: supportsMarkdownPreview(tabManager.currentDocument),
                markdownDisplayMode: $workspace.markdownDisplayMode,
                isLogDoc: tabManager.currentDocument?.isLog ?? false,
                logAutoScroll: $logAutoScroll,
                workspace: workspace
            )

            if let doc = tabManager.currentDocument {
                if loadingDocumentId == doc.id {
                    documentLoadingView(for: doc)
                } else if let loadingDocumentError {
                    documentLoadFailureView(loadingDocumentError)
                } else {
                    let split = workspace.splitState
                    let secondDoc = split != nil ? tabManager.documents.first(where: { $0.id == split?.secondDocumentId }) : nil
                    let canShowSplit = split != nil && secondDoc != nil && !doc.isLargeDocument && !(secondDoc?.isLargeDocument ?? true)

                    if canShowSplit {
                        SplitPaneView(
                            workspace: workspace,
                            primaryDoc: doc,
                            secondDoc: secondDoc!,
                            wordWrap: wordWrap,
                            font: font
                        )
                    } else {
                        documentBody(for: doc)
                    }
                }

                StatusBarView(
                    cursorPosition: cursorPosition,
                    isLargeDocument: doc.usesProtectedEditorMode && !isEditingLargeDocument(doc),
                    canToggleLineNumbers: true
                )
            }
        }
        .onAppear {
            handleDocumentSelectionChange()
            clearsplitStateIfInvalid()
        }
        .onChange(of: tabManager.selectedDocumentId) { _ in
            clearsplitStateIfInvalid()
            selectedRange = nil
            selectedRangeScrollRequestID = 0
            logRefreshTask?.cancel()
            logRefreshTask = nil
            logRefreshRequestID &+= 1
            handleDocumentSelectionChange()
        }
        .onChange(of: logAutoScroll) { enabled in
            guard enabled, let doc = tabManager.currentDocument, doc.isLog else { return }
            setSelectedRangeIfNeeded(
                NSRange(location: doc.content.utf16.count, length: 0),
                forceScroll: true
            )
        }
    }

    private func handleDocumentSelectionChange() {
        loadingDocumentError = nil
        Task { await ensureCurrentDocumentLoadedIfNeeded() }
    }

    private func clearsplitStateIfInvalid() {
        guard let split = workspace.splitState else { return }
        let secondDoc = tabManager.documents.first(where: { $0.id == split.secondDocumentId })
        if secondDoc == nil || (tabManager.currentDocument?.isLargeDocument ?? false) || (secondDoc?.isLargeDocument ?? false) {
            workspace.splitState = nil
        }
    }

    private func ensureCurrentDocumentLoadedIfNeeded() async {
        guard let doc = tabManager.currentDocument else { return }

        if doc.requiresDiskReload {
            loadingDocumentId = doc.id
            do {
                try await tabManager.ensureDocumentContentLoaded(doc.id)
            } catch {
                if tabManager.selectedDocumentId == doc.id {
                    loadingDocumentError = error.localizedDescription
                }
            }
            if loadingDocumentId == doc.id {
                loadingDocumentId = nil
            }
        }

        guard tabManager.selectedDocumentId == doc.id else { return }
        refreshSearchState()
        setupLogWatcher()
    }

    private func setupLogWatcher() {
        logWatcher = nil
        pendingLogRefresh?.cancel()
        pendingLogRefresh = nil
        logRefreshTask?.cancel()
        logRefreshTask = nil
        logRefreshRequestID &+= 1
        logFileOffset = 0
        guard let doc = tabManager.currentDocument, doc.isLog, let url = doc.fileURL else { return }
        logFileOffset = LunaPadMemoryBudget.fileSize(at: url)

        // Scroll to bottom on tab switch if auto-scroll is on
        if logAutoScroll {
            setSelectedRangeIfNeeded(
                NSRange(location: doc.content.utf16.count, length: 0),
                forceScroll: true
            )
        }

        logWatcher = LogFileWatcher(url: url) {
            scheduleLogRefresh(for: doc.id, url: url)
        }
    }

    private func scheduleLogRefresh(for documentID: UUID, url: URL) {
        pendingLogRefresh?.cancel()
        let workItem = DispatchWorkItem {
            applyLogRefresh(for: documentID, url: url)
        }
        pendingLogRefresh = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + LunaPadMemoryBudget.logRefreshCoalesceDelay,
            execute: workItem
        )
    }

    private func applyLogRefresh(for documentID: UUID, url: URL) {
        pendingLogRefresh = nil

        guard let currentDocument = tabManager.currentDocument,
              currentDocument.id == documentID else { return }
        let capturedContent = currentDocument.content
        let capturedOffset = logFileOffset
        let refreshRequestID = logRefreshRequestID &+ 1
        logRefreshRequestID = refreshRequestID
        logRefreshTask?.cancel()
        logRefreshTask = Task(priority: .userInitiated) {
            let result = try? await Task.detached(priority: .userInitiated) {
                try LunaPadMemoryBudget.refreshLogContent(
                    currentContent: capturedContent,
                    from: url,
                    startingAt: capturedOffset
                )
            }.value

            guard !Task.isCancelled,
                  let result else { return }

            await MainActor.run {
                guard logRefreshRequestID == refreshRequestID,
                      let activeDocument = tabManager.currentDocument,
                      activeDocument.id == documentID else { return }

                logFileOffset = result.nextOffset
                guard result.content != activeDocument.content else { return }

                tabManager.updateDocument(
                    documentID,
                    fileURL: url,
                    content: result.content,
                    isSaved: true,
                    persistenceMode: .deferred
                )

                findReplaceManager.scheduleMatchUpdate(
                    in: activeDocument.isLargeDocument ? "" : result.content
                ) { match in
                    if findReplaceManager.isOpen && !logAutoScroll {
                        setSelectedRangeIfNeeded(match)
                    }
                }
                if logAutoScroll {
                    setSelectedRangeIfNeeded(
                        NSRange(location: result.content.utf16.count, length: 0),
                        forceScroll: true
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func documentBody(for doc: OpenDocument) -> some View {
        let displayMode = effectiveDisplayMode(for: doc)

        switch displayMode {
        case .editor:
            editorPane(for: doc)
        case .split:
            HSplitView {
                editorPane(for: doc)
                    .frame(minWidth: 320)

                MarkdownPreviewView(text: doc.content, lunaMode: lunaMode)
                    .frame(minWidth: 260)
            }
        case .preview:
            MarkdownPreviewView(text: doc.content, lunaMode: lunaMode)
        }
    }

    private func documentLoadingView(for doc: OpenDocument) -> some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Loading \(doc.displayName)…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func documentLoadFailureView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            Text("Could not load document")
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func effectiveDisplayMode(for doc: OpenDocument) -> MarkdownDisplayMode {
        supportsMarkdownPreview(doc) ? workspace.markdownDisplayMode : .editor
    }

    private func supportsMarkdownPreview(_ doc: OpenDocument?) -> Bool {
        guard let doc else { return false }
        return doc.isMarkdown && doc.content.count <= LunaPadMemoryBudget.markdownPreviewCharacterLimit
    }

    private func isEditingLargeDocument(_ doc: OpenDocument) -> Bool {
        largeDocumentEditorOverrides.contains(doc.id)
    }

    private func usesProtectedEditorMode(_ doc: OpenDocument) -> Bool {
        doc.usesProtectedEditorMode && !isEditingLargeDocument(doc)
    }

    private func isChunkedLargeDocumentView(_ doc: OpenDocument) -> Bool {
        doc.usesChunkedViewer && !isEditingLargeDocument(doc)
    }

    @ViewBuilder
    private func editorPane(for doc: OpenDocument) -> some View {
        let usesReducedLargeFileMode = usesProtectedEditorMode(doc)

        VStack(spacing: 0) {
            if doc.usesProtectedEditorMode {
                LargeDocumentNotice(
                    isEditingEnabled: isEditingLargeDocument(doc),
                    isChunkedViewer: isChunkedLargeDocumentView(doc),
                    onToggleEdit: {
                        toggleLargeDocumentEditing(doc)
                    }
                )
            }

            if usesReducedLargeFileMode {
                if let url = doc.fileURL, doc.usesChunkedViewer {
                    LargeFileViewer(
                        fileURL: url,
                        fileSize: max(doc.byteCount, doc.content.count),
                        wordWrap: wordWrap,
                        font: font,
                        showLineNumbers: showLineNumbers,
                        cursorPosition: $cursorPosition,
                        selectedRange: $selectedRange,
                        selectedRangeScrollRequestID: selectedRangeScrollRequestID
                    )
                } else {
                    LargeFileViewer(
                        text: doc.content,
                        wordWrap: wordWrap,
                        font: font,
                        showLineNumbers: showLineNumbers,
                        cursorPosition: $cursorPosition,
                        selectedRange: $selectedRange,
                        selectedRangeScrollRequestID: selectedRangeScrollRequestID
                    )
                }
            } else {
                NoteTextEditor(
                    text: Binding(
                        get: { doc.content },
                        set: {
                            tabManager.updateContent(doc.id, $0)
                            findReplaceManager.scheduleMatchUpdate(in: $0, isLargeDocument: doc.isLargeDocument)
                        }
                    ),
                    wordWrap: wordWrap,
                    font: font,
                    showLineNumbers: showLineNumbers,
                    isLargeDocument: false,
                    isEditable: !usesReducedLargeFileMode,
                    cursorPosition: $cursorPosition,
                    selectedRange: $selectedRange,
                    selectedRangeScrollRequestID: selectedRangeScrollRequestID,
                    searchMatches: findReplaceManager.isOpen && !doc.isLargeDocument ? findReplaceManager.allMatches : [],
                    currentSearchMatch: findReplaceManager.isOpen && !doc.isLargeDocument ? findReplaceManager.currentMatch : nil,
                    isLog: doc.isLog
                )
            }

            if findReplaceManager.isOpen && !isChunkedLargeDocumentView(doc) {
                FindReplacePanel(
                    manager: findReplaceManager,
                    isReplaceEnabled: !doc.isLargeDocument,
                    onSearchOptionsChanged: {
                        findReplaceManager.scheduleMatchUpdate(
                            in: doc.content,
                            isLargeDocument: doc.isLargeDocument
                        ) { match in
                            selectedRange = match
                        }
                    },
                    onFindNext: {
                        if doc.isLargeDocument {
                            let start = (selectedRange.map { NSMaxRange($0) }) ?? cursorPosition.location
                            selectedRange = findReplaceManager.findNextOnDemand(in: doc.content, after: start)
                        } else {
                            Task {
                                let match = await findReplaceManager.findNextAsync(in: doc.content)
                                selectedRange = match
                            }
                        }
                    },
                    onFindPrevious: {
                        if doc.isLargeDocument {
                            let start = (selectedRange?.location) ?? cursorPosition.location
                            selectedRange = findReplaceManager.findPreviousOnDemand(in: doc.content, before: start)
                        } else {
                            Task {
                                let match = await findReplaceManager.findPreviousAsync(in: doc.content)
                                selectedRange = match
                            }
                        }
                    },
                    onReplace: {
                        Task {
                            let replaced = await findReplaceManager.replaceCurrentAsync(in: doc.content)
                            tabManager.updateContent(doc.id, replaced)
                            findReplaceManager.scheduleMatchUpdate(
                                in: replaced,
                                isLargeDocument: doc.isLargeDocument
                            ) { match in
                                selectedRange = match
                            }
                        }
                    },
                    onReplaceAll: {
                        Task {
                            let replaced = await findReplaceManager.replaceAllAsync(in: doc.content)
                            tabManager.updateContent(doc.id, replaced)
                            findReplaceManager.scheduleMatchUpdate(
                                in: replaced,
                                isLargeDocument: doc.isLargeDocument
                            ) { match in
                                selectedRange = match
                            }
                        }
                    },
                    onClose: { findReplaceManager.isOpen = false }
                )
            }
        }
    }

    private func refreshSearchState() {
        if let doc = tabManager.currentDocument {
            findReplaceManager.scheduleMatchUpdate(
                in: doc.content,
                isLargeDocument: doc.isLargeDocument
            ) { match in
                setSelectedRangeIfNeeded(match)
            }
        }
    }

    private func toggleLargeDocumentEditing(_ doc: OpenDocument) {
        if isEditingLargeDocument(doc) {
            largeDocumentEditorOverrides.remove(doc.id)
            if doc.isSaved {
                tabManager.unloadChunkedLargeDocument(doc.id)
            }
            return
        }

        guard doc.usesChunkedViewer else {
            largeDocumentEditorOverrides.insert(doc.id)
            return
        }

        loadingDocumentError = nil
        loadingDocumentId = doc.id
        Task {
            do {
                try await tabManager.loadFullDocumentContent(doc.id)
                await MainActor.run {
                    guard tabManager.selectedDocumentId == doc.id else { return }
                    loadingDocumentId = nil
                    largeDocumentEditorOverrides.insert(doc.id)
                    refreshSearchState()
                }
            } catch {
                await MainActor.run {
                    if tabManager.selectedDocumentId == doc.id {
                        loadingDocumentId = nil
                        loadingDocumentError = error.localizedDescription
                    }
                }
            }
        }
    }

    private func setSelectedRangeIfNeeded(_ range: NSRange?, forceScroll: Bool = false) {
        let rangeChanged = selectedRange != range
        guard rangeChanged || forceScroll else { return }
        selectedRange = range
        if forceScroll, range != nil {
            selectedRangeScrollRequestID &+= 1
        }
    }
}


private struct FileTabStrip: View {
    @ObservedObject var tabManager: TabManager
    let isMarkdownDoc: Bool
    @Binding var markdownDisplayMode: MarkdownDisplayMode
    let isLogDoc: Bool
    @Binding var logAutoScroll: Bool
    let workspace: WorkspaceState
    @State private var draggedDocumentID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(tabManager.documents) { doc in
                            TabButton(
                                doc: doc,
                                isSelected: tabManager.selectedDocumentId == doc.id,
                                onSelect: { tabManager.selectTab(id: doc.id) },
                                onClose: { tabManager.closeTab(id: doc.id) },
                                onDragStarted: {
                                    draggedDocumentID = doc.id
                                    return provider(for: doc.id, type: DragPayload.document)
                                },
                                workspace: workspace,
                                tabManager: tabManager
                            )
                            .id(doc.id)
                            .onDrop(
                                of: [.text],
                                delegate: DocumentDropDelegate(
                                    targetDocumentID: doc.id,
                                    draggedDocumentID: $draggedDocumentID,
                                    tabManager: tabManager
                                )
                            )
                        }

                        Color.clear
                            .frame(width: 18, height: 28)
                            .onDrop(
                                of: [.text],
                                delegate: DocumentDropDelegate(
                                    targetDocumentID: nil,
                                    draggedDocumentID: $draggedDocumentID,
                                    tabManager: tabManager
                                )
                            )
                    }
                }
                .mask(
                    HStack(spacing: 0) {
                        Color.black
                        LinearGradient(
                            colors: [.black, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 20)
                    }
                )
                .onChange(of: tabManager.selectedDocumentId) { id in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }

            if isMarkdownDoc {
                Divider().frame(height: 16)
                HStack(spacing: 2) {
                    ForEach(MarkdownDisplayMode.allCases) { mode in
                        Button(action: { markdownDisplayMode = mode }) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 12))
                                .foregroundStyle(markdownDisplayMode == mode ? Color.primary : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 4)
                        .help(mode.title)
                    }
                }
                .padding(.horizontal, 6)
            }

            if isLogDoc {
                Divider().frame(height: 16)
                Button(action: { logAutoScroll.toggle() }) {
                    Image(systemName: logAutoScroll ? "arrow.down.to.line" : "pause.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(logAutoScroll ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .help(logAutoScroll ? "Auto-scroll on — click to disable" : "Auto-scroll off — click to enable")
            }

            Button(action: { tabManager.newTab() }) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .help("New Tab")
        }
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct LargeDocumentNotice: View {
    let isEditingEnabled: Bool
    let isChunkedViewer: Bool
    let onToggleEdit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Image(systemName: "bolt.horizontal.circle")
                    .foregroundStyle(.secondary)
                Text(
                    isEditingEnabled
                    ? "Large file mode is active. Editing is enabled, but search stays on-demand and gutter markers and line numbers stay reduced to keep LunaPad responsive."
                    : (isChunkedViewer
                        ? "Large file mode is active. LunaPad is showing this file in chunked read-only view to keep memory usage low. Choose Edit Anyway to load the full file into memory."
                        : "Large file mode is active. The file is opened read-only by default, and search stays on-demand while gutter markers and line numbers stay reduced to keep LunaPad responsive.")
                )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button(isEditingEnabled ? "Return to Safe Mode" : "Edit Anyway") {
                    onToggleEdit()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
            }
            .padding(8)
            .background(.bar)
        }
    }
}

private struct TabButton: View {
    let doc: OpenDocument
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onDragStarted: () -> NSItemProvider
    let workspace: WorkspaceState
    let tabManager: TabManager

    var body: some View {
        HStack(spacing: 4) {
            Text(doc.displayName)
                .font(.system(size: 12))
                .lineLimit(1)

            if !doc.isSaved {
                Circle()
                    .fill(.primary)
                    .frame(width: 4, height: 4)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close Tab")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(isSelected ? Color(nsColor: .selectedControlColor).opacity(0.4) : Color.clear)
        .contentShape(Rectangle())
        .help(doc.fileURL?.path ?? doc.displayName)
        .onTapGesture(perform: onSelect)
        .onDrag { onDragStarted() }
        .contextMenu {
            if tabManager.documents.count > 1 {
                Menu("Open in Split") {
                    Button("Horizontal") {
                        workspace.splitState = SplitPaneState(axis: .horizontal, secondDocumentId: doc.id)
                    }
                    Button("Vertical") {
                        workspace.splitState = SplitPaneState(axis: .vertical, secondDocumentId: doc.id)
                    }
                }
            }
        }
        .overlay(alignment: .trailing) { Divider() }
    }
}

private struct WorkspaceDropDelegate: DropDelegate {
    let targetWorkspaceID: UUID?
    @Binding var draggedWorkspaceID: UUID?
    let workspaceManager: WorkspaceManager

    func dropEntered(info: DropInfo) {
        guard let draggedWorkspaceID,
              draggedWorkspaceID != targetWorkspaceID else { return }
        workspaceManager.moveWorkspace(id: draggedWorkspaceID, before: targetWorkspaceID)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedWorkspaceID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }
}

private struct DocumentDropDelegate: DropDelegate {
    let targetDocumentID: UUID?
    @Binding var draggedDocumentID: UUID?
    let tabManager: TabManager

    func dropEntered(info: DropInfo) {
        guard let draggedDocumentID,
              draggedDocumentID != targetDocumentID else { return }
        tabManager.moveTab(id: draggedDocumentID, before: targetDocumentID)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedDocumentID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }
}

private func provider(for id: UUID, type: String) -> NSItemProvider {
    let provider = NSItemProvider(object: id.uuidString as NSString)
    provider.suggestedName = type
    return provider
}
