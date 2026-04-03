# LunaPad Threading and Responsiveness Plan

## What We Know

- App state is intentionally centralized on the main actor:
  - `TabManager`
  - `WorkspaceState`
  - `WorkspaceManager`
  - `FindReplaceManager`
- File I/O is already partially backgrounded with `Task.detached`.
- Large-file chunk reads are already backgrounded.
- The remaining freeze risk is not raw disk I/O. It is heavy post-load work that still returns to the main actor.

## Main Freeze Risks

### 1. Log refresh path still does heavy work on the main thread

- Live log refresh currently:
  - reads appended bytes
  - rebuilds retained log content
  - trims content
  - refreshes search state
- The expensive file read and string rebuild path should not run on the main actor.

### 2. Markdown preview conversion still renders on the main thread

- `markdownToHTML(...)` and the Markdown-to-HTML conversion path currently run in the debounced main-queue work item.
- Large Markdown edits can still stall the app even though preview is debounced.

### 3. Indexed search still runs on the main actor

- `FindReplaceManager` is `@MainActor`.
- For non-large documents, `updateMatches(...)` still does regex enumeration on the main actor.
- This can block the whole app on a big-but-not-large-mode document.

### 4. Full-content handoff back to AppKit still happens on the main thread

- Even when file I/O is backgrounded, normal-document loading still assigns a full `String` to the document/editor path on the main actor.
- This is expected for AppKit integration, but it means large non-safe-mode documents can still cause visible hitching when content lands.

## GPU Note

- GPU use is not the immediate fix.
- AppKit/WebKit already leverage system rendering paths where appropriate.
- The current bottlenecks are:
  - file reads
  - string construction/copying
  - regex work
  - markdown parsing/render generation
  - main-actor UI mutation
- A real GPU-focused optimization would mean a custom Metal-backed text renderer, which is much larger in scope than the remaining memory/responsiveness work.

## Implementation Order

### Pass 1. Background log refresh

Move log refresh file reading and retained-content rebuilding off the main thread.

Status: completed.

Success criteria:

- live log updates no longer do file reads and string rebuilding on the main actor
- stale refresh results are discarded safely when the selected tab changes
- auto-scroll behavior remains correct

### Pass 2. Background Markdown HTML generation

Move `markdownToHTML(...)` generation off the main thread while keeping `WKWebView.loadHTMLString(...)` on the main thread.

Status: completed.

Success criteria:

- Markdown preview remains debounced
- HTML generation no longer blocks the main queue
- stale preview renders are discarded safely

### Pass 3. Background indexed search

Refactor non-large-document regex indexing so match enumeration happens off the main actor, then publish the result back on the main actor.

Status: completed.

Implemented:

- passive indexed search updates from document changes and search-option changes now run off the main actor
- stale background search results are discarded when a newer update supersedes them
- explicit `Find Next` and `Find Previous` for normal documents now also run off the main actor
- background indexing now feeds selection-following back into the editor when search state refreshes complete
- `Replace` and `Replace All` for normal documents now also compute their match work off the main actor before applying the resulting content

Success criteria:

- opening Find on medium/large normal documents does not freeze the whole app
- selection and replace behavior remain correct

### Pass 4. Review main-thread content handoff

Measure whether normal-mode large-ish files still hitch when `String` content is assigned back into the AppKit editor.

Status: completed in pragmatic form.

Implemented:

- saved files now enter protected safe mode earlier, before the previous “large document” threshold
- the chunked/read-only viewer is used for more medium-large saved files, reducing the chance that a large `String` handoff into `NSTextView` blocks the app
- `Edit Anyway` remains the explicit escape hatch for users who want full editing semantics despite the higher handoff cost

Options if still problematic:

- defer editor instantiation until content is ready
- stage content handoff in smaller chunks where practical
- push more documents into safe mode earlier

## Plan Status

Completed.

Remaining intentional tradeoffs:

- `Edit Anyway` still opts back into the full editor path for protected files, so very large explicit edit sessions can still hitch more than safe mode
- core workspace/document state is still main-actor centered, which is acceptable for the current architecture but not the same as full per-document execution isolation
