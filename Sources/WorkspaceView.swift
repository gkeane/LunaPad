import SwiftUI

struct WorkspaceView: View {
    @StateObject private var workspaceManager = WorkspaceManager()
    @AppStorage(LunaMode.storageKey) private var lunaModeRawValue = LunaMode.system.rawValue

    private var lunaMode: LunaMode {
        LunaMode(rawValue: lunaModeRawValue) ?? .system
    }

    var body: some View {
        MainView(workspaceManager: workspaceManager)
            .navigationTitle(workspaceManager.currentWorkspace?.displayName ?? "Workspace")
            .preferredColorScheme(lunaMode.colorScheme)
            .background(WindowAppearanceApplier(mode: lunaMode))
            .focusedSceneValue(\.workspaceManager, workspaceManager)
            .focusedSceneValue(\.tabManager, workspaceManager.currentTabManager)
            .focusedSceneValue(\.findReplaceManager, workspaceManager.currentFindReplaceManager)
            .onAppear {
                ExternalFileOpenCoordinator.shared.activate(workspaceManager)
            }
    }
}

struct WorkspaceManagerKey: FocusedValueKey {
    typealias Value = WorkspaceManager
}

struct TabManagerKey: FocusedValueKey {
    typealias Value = TabManager
}

struct FindReplaceManagerKey: FocusedValueKey {
    typealias Value = FindReplaceManager
}

extension FocusedValues {
    var workspaceManager: WorkspaceManager? {
        get { self[WorkspaceManagerKey.self] }
        set { self[WorkspaceManagerKey.self] = newValue }
    }

    var tabManager: TabManager? {
        get { self[TabManagerKey.self] }
        set { self[TabManagerKey.self] = newValue }
    }

    var findReplaceManager: FindReplaceManager? {
        get { self[FindReplaceManagerKey.self] }
        set { self[FindReplaceManagerKey.self] = newValue }
    }
}
