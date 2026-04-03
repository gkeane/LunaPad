import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class ExternalFileOpenCoordinator {
    static let shared = ExternalFileOpenCoordinator()

    private weak var activeWorkspaceManager: WorkspaceManager?
    private var pendingURLs: [URL] = []

    func activate(_ workspaceManager: WorkspaceManager) {
        activeWorkspaceManager = workspaceManager
        flushPendingURLsIfPossible()
    }

    func openFiles(_ urls: [URL]) {
        let normalized = urls.map(\.standardizedFileURL)
        if let workspaceManager = activeWorkspaceManager {
            load(normalized, into: workspaceManager)
        } else {
            pendingURLs.append(contentsOf: normalized)
        }
    }

    private func flushPendingURLsIfPossible() {
        guard let workspaceManager = activeWorkspaceManager, !pendingURLs.isEmpty else { return }
        let queued = pendingURLs
        pendingURLs.removeAll()
        load(queued, into: workspaceManager)
    }

    private func load(_ urls: [URL], into workspaceManager: WorkspaceManager) {
        guard let tabManager = workspaceManager.currentTabManager else {
            pendingURLs.insert(contentsOf: urls, at: 0)
            return
        }

        for url in urls {
            Task { @MainActor in
                try? await tabManager.loadDocument(from: url)
                workspaceManager.noteRecentFile(url)
            }
        }
    }
}

final class LunaPadAppDelegate: NSObject, NSApplicationDelegate {
    // Modern method — called by Finder "Open With", drag-onto-dock-icon, etc.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            ExternalFileOpenCoordinator.shared.openFiles(urls)
        }
    }

    // Legacy fallback
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        Task { @MainActor in
            ExternalFileOpenCoordinator.shared.openFiles(urls)
        }
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct LunaPadApp: App {
    @NSApplicationDelegateAdaptor(LunaPadAppDelegate.self) private var appDelegate
    @FocusedValue(\.workspaceManager) private var workspaceManager
    @FocusedValue(\.tabManager) private var tabManager
    @FocusedValue(\.findReplaceManager) private var findReplaceManager

    private let openableContentTypes: [UTType] = [
        .text,
        .plainText,
        .utf8PlainText,
        .sourceCode,
        .json,
        .xml,
        .commaSeparatedText,
        .tabSeparatedText
    ] + [
        "md", "markdown", "txt", "text", "log", "yaml", "yml", "toml",
        "sh", "zsh", "bash", "swift", "js", "ts", "jsx", "tsx", "py",
        "rb", "java", "c", "h", "m", "mm", "cpp", "hpp", "css", "scss",
        "html", "htm", "sql", "ini", "conf", "cfg"
    ].compactMap { UTType(filenameExtension: $0) }

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

            CommandGroup(after: .newItem) {
                Menu("Open Recent File") {
                    if workspaceManager?.recentFiles.isEmpty ?? true {
                        Button("No Recent Files") {}
                            .disabled(true)
                    } else {
                        ForEach(workspaceManager?.recentFiles ?? []) { entry in
                            Button(entry.displayName) {
                                openRecentFile(entry.url)
                            }
                        }

                        Divider()

                        Button("Clear Menu") {
                            workspaceManager?.clearRecentFiles()
                        }
                    }
                }
                .disabled(tabManager == nil)

                Menu("Reopen Recent Workspace") {
                    if workspaceManager?.recentWorkspaces.isEmpty ?? true {
                        Button("No Recent Workspaces") {}
                            .disabled(true)
                    } else {
                        ForEach(workspaceManager?.recentWorkspaces ?? []) { workspace in
                            Button(workspace.name) {
                                workspaceManager?.reopenRecentWorkspace(id: workspace.id)
                            }
                        }

                        Divider()

                        Button("Clear Menu") {
                            workspaceManager?.clearRecentWorkspaces()
                        }
                    }
                }
                .disabled(workspaceManager == nil)
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
            LunaModeCommands()
        }
    }

    private func openFile() {
        guard let tabManager, let workspaceManager else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = openableContentTypes
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true

        panel.begin { response in
            if response == .OK {
                for url in panel.urls {
                    Task {
                        try await tabManager.loadDocument(from: url)
                        await MainActor.run {
                            workspaceManager.noteRecentFile(url)
                        }
                    }
                }
            }
        }
    }

    private func openRecentFile(_ url: URL) {
        guard let tabManager, let workspaceManager else { return }
        Task {
            try await tabManager.loadDocument(from: url)
            await MainActor.run {
                workspaceManager.noteRecentFile(url)
            }
        }
    }

    private func saveCurrentDocument() {
        guard let tabManager, let workspaceManager, let doc = tabManager.currentDocument else { return }
        if let url = doc.fileURL {
            Task {
                try await tabManager.saveDocument(doc.id, to: url)
                await MainActor.run {
                    workspaceManager.noteRecentFile(url)
                }
            }
        } else {
            saveAsCurrentDocument()
        }
    }

    private func saveAsCurrentDocument() {
        guard let tabManager, let workspaceManager, let doc = tabManager.currentDocument else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = doc.displayName
        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task {
                    try await tabManager.saveDocument(doc.id, to: url)
                    await MainActor.run {
                        workspaceManager.noteRecentFile(url)
                    }
                }
            }
        }
    }
}
