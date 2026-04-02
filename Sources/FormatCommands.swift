import SwiftUI
import AppKit

extension Notification.Name {
    static let fontChanged = Notification.Name("LunaPadFontChanged")
}

struct FormatCommands: Commands {
    @AppStorage("wordWrap") private var wordWrap: Bool = true
    @AppStorage("fontSize") private var fontSize: Double = 13

    var body: some Commands {
        CommandMenu("Format") {
            Toggle("Word Wrap", isOn: $wordWrap)

            Divider()

            Button("Font…") {
                FontPanelCoordinator.shared.showFontPanel()
            }
            .keyboardShortcut("t", modifiers: .command)

            Divider()

            Button("Bigger") {
                fontSize = min(fontSize + 1, 72)
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Smaller") {
                fontSize = max(fontSize - 1, 8)
            }
            .keyboardShortcut("-", modifiers: .command)
        }
    }
}

final class FontPanelCoordinator: NSObject, NSWindowDelegate {
    static let shared = FontPanelCoordinator()

    func showFontPanel() {
        let fm = NSFontManager.shared
        fm.target = self
        fm.action = #selector(changeFont(_:))
        fm.orderFrontFontPanel(nil)
    }

    @objc func changeFont(_ sender: NSFontManager?) {
        guard let fm = sender else { return }
        let current = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let newFont = fm.convert(current)
        NotificationCenter.default.post(name: .fontChanged, object: newFont)
    }
}
