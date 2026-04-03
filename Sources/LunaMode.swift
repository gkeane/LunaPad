import AppKit
import SwiftUI

enum LunaMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "lunaMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }
}

struct LunaModePicker: View {
    @Binding var mode: LunaMode

    var body: some View {
        Menu {
            ForEach(LunaMode.allCases) { lunaMode in
                Button(action: { mode = lunaMode }) {
                    Label(lunaMode.title, systemImage: lunaMode.icon)
                }
                .disabled(mode == lunaMode)
            }
        } label: {
            Image(systemName: mode.icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Appearance: \(mode.title)")
    }
}

struct WindowAppearanceApplier: NSViewRepresentable {
    let mode: LunaMode

    func makeNSView(context: Context) -> AppearanceBridgeView {
        let view = AppearanceBridgeView()
        view.mode = mode
        return view
    }

    func updateNSView(_ nsView: AppearanceBridgeView, context: Context) {
        nsView.mode = mode
    }
}

final class AppearanceBridgeView: NSView {
    var mode: LunaMode = .system {
        didSet {
            // Deferring to the next runloop avoids stale appearance during menu tracking.
            DispatchQueue.main.async { [weak self] in
                self?.applyAppearance()
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyAppearance()
    }

    private func applyAppearance() {
        NSApp.appearance = mode.nsAppearance
        window?.appearance = mode.nsAppearance
        window?.contentView?.needsLayout = true
        window?.contentView?.needsDisplay = true
    }
}

struct LunaModeCommands: Commands {
    @AppStorage(LunaMode.storageKey) private var lunaModeRawValue = LunaMode.system.rawValue

    private var lunaMode: Binding<LunaMode> {
        Binding(
            get: { LunaMode(rawValue: lunaModeRawValue) ?? .system },
            set: { lunaModeRawValue = $0.rawValue }
        )
    }

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()

            Menu("Lunamode") {
                ForEach(LunaMode.allCases) { mode in
                    Button {
                        lunaMode.wrappedValue = mode
                    } label: {
                        if lunaMode.wrappedValue == mode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Text(mode.title)
                        }
                    }
                }
            }
        }
    }
}
