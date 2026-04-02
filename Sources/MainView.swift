import SwiftUI
import UniformTypeIdentifiers

private enum DragPayload {
    static let workspace = "lunapad.workspace"
    static let document = "lunapad.document"
}

struct MainView: View {
    @ObservedObject var workspaceManager: WorkspaceManager
    @AppStorage("wordWrap") private var wordWrap: Bool = true
    @AppStorage("fontName") private var fontName: String = "Menlo"
    @AppStorage("fontSize") private var fontSize: Double = 13

    private var editorFont: NSFont {
        NSFont(name: fontName, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceStrip(workspaceManager: workspaceManager)

            if let workspace = workspaceManager.currentWorkspace {
                WorkspaceContentView(
                    tabManager: workspace.tabManager,
                    findReplaceManager: workspace.findReplaceManager,
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
    @State private var draggedWorkspaceID: UUID?

    var body: some View {
        HStack(spacing: 0) {
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
        .overlay(alignment: .bottom) { Divider() }
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
        .onTapGesture(perform: onSelect)
        .onDrag { onDragStarted() }
        .overlay(alignment: .trailing) { Divider() }
    }
}

private struct WorkspaceContentView: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var findReplaceManager: FindReplaceManager
    let wordWrap: Bool
    let font: NSFont
    @State private var cursorPosition = CursorPosition()
    @State private var selectedRange: NSRange?

    var body: some View {
        VStack(spacing: 0) {
            FileTabStrip(tabManager: tabManager)

            if let doc = tabManager.currentDocument {
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
                    selectedRange: $selectedRange
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

                Divider()
                StatusBarView(cursorPosition: cursorPosition)
            }
        }
        .onAppear {
            if let content = tabManager.currentDocument?.content {
                findReplaceManager.updateMatches(in: content)
                selectedRange = findReplaceManager.currentMatch
            }
        }
        .onChange(of: tabManager.selectedDocumentId) { _ in
            selectedRange = nil
            if let content = tabManager.currentDocument?.content {
                findReplaceManager.updateMatches(in: content)
                selectedRange = findReplaceManager.currentMatch
            }
        }
    }
}

private struct FileTabStrip: View {
    @ObservedObject var tabManager: TabManager
    @State private var draggedDocumentID: UUID?

    var body: some View {
        HStack(spacing: 0) {
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
