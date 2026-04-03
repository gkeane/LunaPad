import SwiftUI
import AppKit

struct SplitPaneView: View {
    @ObservedObject var workspace: WorkspaceState
    let primaryDoc: OpenDocument
    let secondDoc: OpenDocument
    let wordWrap: Bool
    let font: NSFont

    private var axis: SplitAxis { workspace.splitState?.axis ?? .horizontal }
    private var diffActive: Bool { workspace.splitState?.diffActive ?? false }
    private var canDiff: Bool {
        primaryDoc.content.count + secondDoc.content.count <= 500_000
    }

    var body: some View {
        VStack(spacing: 0) {
            splitToolbar
            if axis == .horizontal {
                HSplitView {
                    pane(doc: primaryDoc)
                        .frame(minWidth: 260)
                    pane(doc: secondDoc)
                        .frame(minWidth: 260)
                }
            } else {
                VSplitView {
                    pane(doc: primaryDoc)
                        .frame(minHeight: 100)
                    pane(doc: secondDoc)
                        .frame(minHeight: 100)
                }
            }
        }
    }

    private var splitToolbar: some View {
        HStack(spacing: 8) {
            Button(action: { toggleAxis() }) {
                Image(systemName: axis == .horizontal ? "rectangle.split.2x1" : "rectangle.split.1x2")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(axis == .horizontal ? "Switch to Vertical" : "Switch to Horizontal")

            Divider().frame(height: 14)

            Button(action: { workspace.splitState?.diffActive.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "plusminus")
                    Text("Diff")
                }
                .font(.system(size: 11))
                .foregroundStyle(diffActive ? Color.primary : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canDiff)
            .help(canDiff ? "Toggle diff" : "Files too large to diff")

            Spacer()

            Button(action: { workspace.splitState = nil }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close Split")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func toggleAxis() {
        workspace.splitState?.axis = axis == .horizontal ? .vertical : .horizontal
    }

    @ViewBuilder
    private func pane(doc: OpenDocument) -> some View {
        EditorPaneView(doc: doc, wordWrap: wordWrap, font: font)
    }
}

struct EditorPaneView: View {
    let doc: OpenDocument
    let wordWrap: Bool
    let font: NSFont
    @State private var cursorPosition = CursorPosition()
    @State private var selectedRange: NSRange?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(doc.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(alignment: .bottom) { Divider() }

            NoteTextEditor(
                text: .constant(doc.content),
                wordWrap: wordWrap,
                font: font,
                showLineNumbers: false,
                isLargeDocument: doc.isLargeDocument,
                isEditable: false,
                cursorPosition: $cursorPosition,
                selectedRange: $selectedRange,
                selectedRangeScrollRequestID: 0,
                searchMatches: [],
                currentSearchMatch: nil,
                isLog: doc.isLog
            )

            StatusBarView(cursorPosition: cursorPosition, isLargeDocument: doc.isLargeDocument, canToggleLineNumbers: false)
        }
    }
}
