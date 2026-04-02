import Foundation

@MainActor
final class WorkspaceState: ObservableObject, Identifiable {
    let id: UUID
    @Published var name: String
    @Published var isRenaming: Bool
    let tabManager: TabManager
    let findReplaceManager: FindReplaceManager

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
    }

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Workspace" : trimmedName
    }
}

@MainActor
final class WorkspaceManager: ObservableObject {
    @Published var workspaces: [WorkspaceState] = []
    @Published var selectedWorkspaceId: UUID?

    init() {
        _ = newWorkspace(selectAndRename: false)
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
        let workspace = WorkspaceState(
            name: nextWorkspaceName(),
            isRenaming: selectAndRename,
            tabManager: TabManager(),
            findReplaceManager: FindReplaceManager()
        )
        workspaces.append(workspace)
        selectedWorkspaceId = workspace.id
        return workspace
    }

    func selectWorkspace(id: UUID) {
        selectedWorkspaceId = id
    }

    func closeWorkspace(id: UUID) {
        guard workspaces.count > 1, let index = workspaces.firstIndex(where: { $0.id == id }) else {
            return
        }

        let wasSelected = selectedWorkspaceId == id
        workspaces.remove(at: index)

        guard wasSelected else { return }
        let replacementIndex = min(index, workspaces.count - 1)
        selectedWorkspaceId = workspaces[replacementIndex].id
    }

    func commitName(for workspace: WorkspaceState) {
        objectWillChange.send()
        workspace.name = workspace.displayName
        workspace.isRenaming = false
    }

    private func nextWorkspaceName() -> String {
        if workspaces.isEmpty {
            return "Workspace"
        }

        return "Workspace \(workspaces.count + 1)"
    }
}
