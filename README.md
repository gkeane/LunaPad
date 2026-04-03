# LunaPad

<p align="center">
  <img src="assets/banner.png" alt="LunaPad banner" width="860">
</p>

<p align="center">
  A focused native macOS editor with workspace-level super-tabs, per-workspace file tabs, split panes, markdown preview, log tailing, and a memory-efficient design.
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#download">Download</a> •
  <a href="#why-lunapad">Why LunaPad</a> •
  <a href="#install">Install</a> •
  <a href="#build-from-source">Build</a> •
  <a href="#roadmap">Roadmap</a> •
  <a href="#contributing">Contributing</a>
</p>

## Why LunaPad

LunaPad is a lightweight native editor for people who keep multiple ideas in motion at once.

Instead of treating tabs as a flat list, LunaPad gives you a top-level workspace strip. Each workspace has:

- its own renameable name
- its own independent file tab set
- its own find/replace state
- its own editing flow

That makes it practical to keep one workspace for scratch notes, one for a writing draft, one for code snippets, and one for research, all inside a single app window without losing context.

## Features

- Native macOS app built with SwiftUI and AppKit
- Workspace super-tabs above document tabs
- Renameable workspaces
- Independent tab stacks per workspace
- Drag-and-drop reordering for both workspace tabs and file tabs
- Session restoration after relaunch or crash
- Recent files and recent workspaces menus
- Open multiple plain-text files
- File associations for common text, markdown, source, and log files
- Save and Save As flows
- Per-document dirty state indicators
- Find and replace with next/previous navigation
- Case-sensitive and whole-word search toggles
- Search result markers in the editor gutter
- Markdown editor, split, and preview modes
- Live log tailing with level-based line highlighting and auto-scroll toggle
- **Split pane editor** — horizontal or vertical, right-click any tab to open in a split
- **Side-by-side diff** — highlight added/removed lines between two open files
- Large-file safe mode — chunked read-only viewer keeps memory low on big files
- App-wide Lunamode with System, Light, and Dark appearance modes
- Word wrap toggle
- Font panel integration
- Live cursor line/column status bar
- Simple local build script that installs directly to `/Applications`

## How It Works

LunaPad uses a two-layer navigation model:

1. The top bar is the workspace bar. Each workspace behaves like a named editing zone.

2. The second bar is the file tab bar for the active workspace. Each workspace owns its own `TabManager` and `FindReplaceManager`, so switching workspaces preserves context instead of flattening everything into one tab row.

This makes the app feel closer to having multiple small editors open at once, but with less window clutter.

## Split Panes

Right-click any file tab to open it side by side with the current document — horizontal or vertical. A shared toolbar lets you:

- toggle between horizontal and vertical layout
- enable **Diff** mode, which highlights added and removed lines between the two panes using a Myers LCS diff
- close the split

Split state is saved per workspace and restored on relaunch. Splits on large files are blocked automatically to protect memory.

## Large File Handling

LunaPad uses tiered modes for large files:

| File size         | Mode                                                                         |
|-------------------|------------------------------------------------------------------------------|
| Normal            | Full editable editor                                                         |
| Large (>2M chars) | Protected mode — read-only by default, search on-demand                      |
| Very large        | Chunked viewer — reads file in pages without loading it entirely into memory  |

Log files bypass protected mode entirely and use the full editor with live reload.

## Download

You can download packaged builds from the GitHub Releases page:

- [Latest release](https://github.com/gkeane/LunaPad/releases/latest)

Current release assets include:

- a zipped `LunaPad.app` bundle for macOS
- a `.sha256` checksum file

Releases can also be produced by GitHub Actions:

- push a tag like `v1.4.0`, or
- run the `Release` workflow manually from the Actions tab with a version like `v1.4.0`

Note: current releases are unsigned local builds. On first launch, macOS may require an extra confirmation step unless future builds are signed and notarized.

## Install

### Prebuilt local install

If you have the repo locally:

```bash
./build.sh
open /Applications/LunaPad.app
```

The build script compiles the app, creates `LunaPad.app`, and refreshes the installed copy at `/Applications/LunaPad.app`.

## Build From Source

### Requirements

- macOS 13 or newer
- Xcode installed
- Xcode license accepted via `sudo xcodebuild -license`

### Build

```bash
./build.sh
```

### What the build script does

- selects the Xcode toolchain if available
- redirects Swift module caches to `/tmp`
- builds the release binary with SwiftPM
- bundles a native `.app`
- installs the app to `/Applications/LunaPad.app`

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd-N` | New file tab |
| `Cmd-Shift-N` | New workspace |
| `Cmd-O` | Open file |
| `Cmd-S` | Save |
| `Cmd-Shift-S` | Save As |
| `Cmd-W` | Close file tab |
| `Cmd-Shift-W` | Close workspace |
| `Cmd-F` | Find |
| `Cmd-H` | Find and replace |
| `Cmd-T` | Font panel |
| `Cmd-Ctrl-\` | Split horizontally |
| `Cmd-Ctrl--` | Split vertically |
| `Cmd-Ctrl-W` | Close split |

## Project Structure

```text
Sources/
  MainView.swift            Main UI, workspace strip, file tabs, editor layout
  WorkspaceManager.swift    Workspace and tab state, session persistence and restore
  FindReplaceManager.swift  Search and replace state
  NoteTextEditor.swift      AppKit-backed text editor bridge
  MarkdownRenderer.swift    WKWebView-based markdown preview
  SplitPaneView.swift       Split pane layout and pane headers
  DiffEngine.swift          Myers LCS line diff engine
  LargeFileViewer.swift     Chunked viewer for very large files
  MemoryBudget.swift        Memory thresholds and file loading helpers
  SessionDocumentCache.swift Disk cache for large unsaved documents
  LogFileWatcher.swift      kqueue-based file watcher for live log tailing
  LunaMode.swift            App-wide appearance controls and window theming
build.sh                    Build, bundle, and install script
bundle-app.sh               App bundle assembly
benchmarks/                 Memory and performance benchmark fixtures and results
```

## Positioning

LunaPad is not trying to replace a full IDE or a giant plugin-driven editor.

It is for users who want:

- a fast local note editor
- stronger structure than a single scratch pad
- native macOS behavior
- multiple parallel note contexts without window chaos
- sensible handling of large files without grinding to a halt

## Roadmap

- Optional autosave and crash recovery
- Unsaved-change prompts before closing documents or workspaces
- Clickable log/search gutter markers for fast navigation
- Signed and notarized distribution build

## Contributing

Issues and pull requests are welcome.

If you want to contribute, strong first candidates are:

- usability polish on the workspace bar
- keyboard navigation improvements
- better document lifecycle prompts for unsaved changes
- release/signing automation
- automated tests around workspace and tab state

## License

MIT. See [LICENSE](LICENSE).
