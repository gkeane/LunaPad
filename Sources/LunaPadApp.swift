import SwiftUI

@main
struct LunaPadApp: App {
    @FocusedValue(\.workspaceManager) private var workspaceManager
    @FocusedValue(\.tabManager) private var tabManager
    @FocusedValue(\.findReplaceManager) private var findReplaceManager

    var body: some Scene {
        WindowGroup {
            WorkspaceView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Workspace") {
                    workspaceManager?.newWorkspace()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(workspaceManager == nil)

                Button("New Tab") {
                    tabManager?.newTab()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(tabManager == nil)

                Button("Open File…") {
                    openFile()
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(tabManager == nil)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    saveCurrentDocument()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(tabManager == nil)

                Button("Save As…") {
                    saveAsCurrentDocument()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(tabManager == nil)
            }

            CommandGroup(after: .saveItem) {
                Button("Close Tab") {
                    if let id = tabManager?.selectedDocumentId {
                        tabManager?.closeTab(id: id)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(tabManager == nil)

                Button("Close Workspace") {
                    if let id = workspaceManager?.selectedWorkspaceId {
                        workspaceManager?.closeWorkspace(id: id)
                    }
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled((workspaceManager?.workspaces.count ?? 0) <= 1)
            }

            CommandMenu("Edit") {
                Button("Find…") {
                    findReplaceManager?.isOpen = true
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Find and Replace…") {
                    findReplaceManager?.isOpen = true
                }
                .keyboardShortcut("h", modifiers: .command)
            }

            FormatCommands()
        }
    }

    private func openFile() {
        guard let tabManager else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true

        panel.begin { response in
            if response == .OK {
                for url in panel.urls {
                    Task { try await tabManager.loadDocument(from: url) }
                }
            }
        }
    }

    private func saveCurrentDocument() {
        guard let tabManager, let doc = tabManager.currentDocument else { return }
        if let url = doc.fileURL {
            Task { try await tabManager.saveDocument(doc.id, to: url) }
        } else {
            saveAsCurrentDocument()
        }
    }

    private func saveAsCurrentDocument() {
        guard let tabManager, let doc = tabManager.currentDocument else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = doc.displayName
        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task { try await tabManager.saveDocument(doc.id, to: url) }
            }
        }
    }
}
