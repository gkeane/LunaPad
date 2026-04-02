import SwiftUI

struct FindReplacePanel: View {
    @ObservedObject var manager: FindReplaceManager
    var onSearchOptionsChanged: () -> Void
    var onFindNext: () -> Void
    var onFindPrevious: () -> Void
    var onReplace: () -> Void
    var onReplaceAll: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text("Find:")
                        .frame(width: 40, alignment: .leading)

                    TextField("", text: $manager.findText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))

                    if manager.matchCount > 0 {
                        Text("\(manager.currentMatchIndex + 1)/\(manager.matchCount)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Button(action: onFindNext) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Find Next")

                    Button(action: onFindPrevious) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Find Previous")

                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }

                HStack(spacing: 8) {
                    Text("Replace:")
                        .frame(width: 60, alignment: .leading)

                    TextField("", text: $manager.replaceText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))

                    Button(action: onReplace) {
                        Text("Replace")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: onReplaceAll) {
                        Text("Replace All")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Toggle("Case", isOn: $manager.caseSensitive)
                        .font(.system(size: 11))

                    Toggle("Words", isOn: $manager.wholeWords)
                        .font(.system(size: 11))
                }
            }
            .padding(8)
            .background(.bar)
        }
        .onChange(of: manager.findText) { _ in onSearchOptionsChanged() }
        .onChange(of: manager.caseSensitive) { _ in onSearchOptionsChanged() }
        .onChange(of: manager.wholeWords) { _ in onSearchOptionsChanged() }
    }
}
