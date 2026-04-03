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
    let wordWrap: Bool
    let font: NSFont
    @State private var cursorPosition = CursorPosition()
    @State private var selectedRange: NSRange?
    @State private var logAutoScroll = true
    @State private var logWatcher: LogFileWatcher?

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
                isMarkdownDoc: tabManager.currentDocument?.isMarkdown ?? false,
                markdownDisplayMode: $workspace.markdownDisplayMode,
                isLogDoc: tabManager.currentDocument?.isLog ?? false,
                logAutoScroll: $logAutoScroll
            )

            if let doc = tabManager.currentDocument {
                documentBody(for: doc)

                StatusBarView(cursorPosition: cursorPosition)
            }
        }
        .onAppear {
            refreshSearchState()
            setupLogWatcher()
        }
        .onChange(of: tabManager.selectedDocumentId) { _ in
            selectedRange = nil
            refreshSearchState()
            setupLogWatcher()
        }
        .onChange(of: logAutoScroll) { enabled in
            guard enabled, let doc = tabManager.currentDocument, doc.isLog else { return }
            selectedRange = NSRange(location: doc.content.utf16.count, length: 0)
        }
    }

    private func setupLogWatcher() {
        logWatcher = nil
        guard let doc = tabManager.currentDocument, doc.isLog, let url = doc.fileURL else { return }

        // Scroll to bottom on tab switch if auto-scroll is on
        if logAutoScroll {
            selectedRange = NSRange(location: doc.content.utf16.count, length: 0)
        }

        logWatcher = LogFileWatcher(url: url) {
            guard let data = try? Data(contentsOf: url),
                  let content = String(data: data, encoding: .utf8),
                  content != tabManager.currentDocument?.content else { return }
            tabManager.updateDocument(doc.id, fileURL: url, content: content, isSaved: true)
            findReplaceManager.updateMatches(in: content)
            if findReplaceManager.isOpen && !logAutoScroll {
                selectedRange = findReplaceManager.currentMatch
            }
            if logAutoScroll {
                selectedRange = NSRange(location: content.utf16.count, length: 0)
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

    private func effectiveDisplayMode(for doc: OpenDocument) -> MarkdownDisplayMode {
        doc.isMarkdown ? workspace.markdownDisplayMode : .editor
    }

    @ViewBuilder
    private func editorPane(for doc: OpenDocument) -> some View {
        VStack(spacing: 0) {
            NoteTextEditor(
                text: Binding(
                    get: { doc.content },
                    set: {
                        tabManager.updateContent(doc.id, $0)
                        findReplaceManager.updateMatches(in: $0)
                    }
                ),
                wordWrap: wordWrap,
                font: font,
                cursorPosition: $cursorPosition,
                selectedRange: $selectedRange,
                searchMatches: findReplaceManager.isOpen ? findReplaceManager.allMatches : [],
                currentSearchMatch: findReplaceManager.isOpen ? findReplaceManager.currentMatch : nil,
                isLog: doc.isLog
            )

            if findReplaceManager.isOpen {
                FindReplacePanel(
                    manager: findReplaceManager,
                    onSearchOptionsChanged: {
                        findReplaceManager.updateMatches(in: doc.content)
                        selectedRange = findReplaceManager.currentMatch
                    },
                    onFindNext: {
                        selectedRange = findReplaceManager.findNext(in: doc.content)
                    },
                    onFindPrevious: {
                        selectedRange = findReplaceManager.findPrevious(in: doc.content)
                    },
                    onReplace: {
                        let replaced = findReplaceManager.replaceCurrent(in: doc.content)
                        tabManager.updateContent(doc.id, replaced)
                        findReplaceManager.updateMatches(in: replaced)
                        selectedRange = findReplaceManager.currentMatch
                    },
                    onReplaceAll: {
                        let replaced = findReplaceManager.replaceAll(in: doc.content)
                        tabManager.updateContent(doc.id, replaced)
                        findReplaceManager.updateMatches(in: replaced)
                        selectedRange = findReplaceManager.currentMatch
                    },
                    onClose: { findReplaceManager.isOpen = false }
                )
            }
        }
    }

    private func refreshSearchState() {
        if let content = tabManager.currentDocument?.content {
            findReplaceManager.updateMatches(in: content)
            selectedRange = findReplaceManager.currentMatch
        }
    }
}


private struct FileTabStrip: View {
    @ObservedObject var tabManager: TabManager
    let isMarkdownDoc: Bool
    @Binding var markdownDisplayMode: MarkdownDisplayMode
    let isLogDoc: Bool
    @Binding var logAutoScroll: Bool
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
                                }
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

private struct TabButton: View {
    let doc: OpenDocument
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onDragStarted: () -> NSItemProvider

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
