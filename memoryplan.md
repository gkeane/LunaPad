# LunaPad Memory Plan

## Baseline

Runtime snapshot taken from a live `LunaPad` process before the first optimization pass:

- `ps` RSS: about `107 MB`
- `vmmap` physical footprint: about `57.5 MB`
- `vmmap` peak physical footprint: about `89.8 MB`

The important number is physical footprint, not RSS. The app was not obviously leaking, but it was doing too much whole-document work and too much inline session persistence.

## Main Memory Risks

### 1. Whole-document session persistence

- Every workspace snapshot persisted full `OpenDocument.content`.
- Session persistence originally ran on essentially every edit.
- This caused repeated JSON encoding of all open documents, including large files.

### 2. Eager loading of large files

- Large files were loaded fully before the UI could settle.
- Session restore tried to reconstruct full document contents up front.
- Large saved files could choke reopen/restore.

### 3. Heavy render-time work after load

- Large files still triggered:
  - line counting over the whole buffer
  - find/replace indexing over the whole buffer
  - search gutter marker generation
  - log highlighting over the whole buffer
  - markdown preview regeneration
- `NSTextView` was being asked to behave like a normal editor for files that should be treated as large-file mode.

### 4. WebKit markdown preview cost

- `WKWebView` preview reloaded full HTML on each update.
- Preview stayed active even when the document was large enough that it should degrade.

### 5. Log viewer churn

- Logs were initially re-read as full files.
- Recoloring and search refreshes could reprocess the entire buffer repeatedly.

## Changes Already Implemented

### Current benchmark status

Recent current-state snapshots show:

- idle: `46.8M` physical footprint
- 10 medium tabs: `64.8M` physical footprint
- large plain text in large-file safe sliding-chunked mode: `38.9M` physical footprint
- restore with one large saved file after cache hardening: `47.6M` physical footprint

This means the large-file and restore paths have improved substantially, while idle and medium-tab overhead are still the main remaining general-memory targets.

An additional editor-churn pass reduced redundant UI/editor updates, but did not materially change steady-state physical footprint:

- idle after editor-churn pass: still `46.8M`
- 10 medium tabs after editor-churn pass: still `64.8M`

That suggests the remaining footprint is no longer dominated by avoidable redraw churn in the normal editor path.

### Session and persistence

- Session persistence is now debounced for edit-driven updates.
- Structural changes still persist immediately.
- Large saved documents now persist as lightweight placeholders for session restore.
- Unsaved buffers now persist through file-backed session cache files instead of being kept inline in the session blob.
- Session writes are flushed on app termination.
- Session decoding is backward-compatible with older saved snapshots.

### File loading

- Saved files can restore as placeholders and load from disk only when selected.
- File loading and saving now run off the main thread.
- Large saved files no longer need to be fully reconstructed inline at launch.

### Large-file guardrails

- Large-file mode activates based on document size.
- In large-file mode:
  - line numbers are disabled
  - search gutter markers are disabled
  - full-buffer match indexing is disabled
  - expensive line metrics are skipped
  - undo and incremental find bar are disabled in the editor
  - the default path is now a dedicated read-only viewer instead of the normal editor bridge
  - editing requires an explicit `Edit Anyway` action

### Markdown and logs

- Markdown preview is disabled above a size threshold.
- Markdown preview reload is debounced.
- Logs use bounded retained content.
- Log watcher appends incrementally where possible.
- Log highlighting is capped by size threshold and now applies only to the visible range plus a margin.

### Search and cursor work

- Normal-file search still uses indexed matches, capped to a fixed maximum.
- Large-file search is now on-demand for next/previous navigation instead of fully disabled.
- Cursor line/column updates now use a cached line-start table instead of slicing from the start of the document on every selection change.

## Remaining Work

### 1. Large-file viewer mode

Completed.

- huge files now open in a read-mostly mode by default
- the normal editor path is avoided in safe mode
- users can explicitly opt into `Edit Anyway`

### 2. Smarter session storage

Mostly completed.

- unsaved buffer persistence moved out of `UserDefaults`
- unsaved content now uses file-backed session cache files
- large inline JSON session blobs were reduced substantially

Remaining:

- cache storage now uses an app-scoped Application Support location, with legacy cache-path fallback and migration
- startup cleanup now prunes orphaned cache files against the restored session, including after crash/abandon scenarios
- unsaved placeholder documents now preserve their existing session-cache file instead of rewriting it as an empty buffer during the next session save

### 3. More selective editor work

Partially completed.

- log highlighting now uses the visible range plus a small margin
- cursor metrics no longer do prefix-string slicing on every selection change

Remaining:

- make line-number work more visible-range-driven for medium documents
- reduce `NSTextView` churn during large paste/load operations
- consider reducing editor updates during rapid external log refreshes

### 4. Better search behavior for large files

Mostly completed.

- the find UI now makes large-file search explicit
- large-file search uses on-demand next/previous scanning instead of full indexing

Remaining:

- add chunked replace support if it can be done safely without whole-buffer cost
- optionally show richer status for on-demand search beyond a single current hit

### 5. Better measurement

Add repeatable measurement scenarios and compare physical footprint after each pass:

- idle app
- 10 medium text tabs
- 1 large markdown document
- 1 large plain text document
- 1 live log file
- restore session with one large saved file

Track:

- physical footprint
- peak physical footprint
- selected document size
- workspace/tab count
- whether markdown preview or log mode is active

## Recommended Next Implementation Order

1. Add lightweight benchmark scripts/checklists and capture before/after footprint numbers.
2. Make line-number work more visible-range-driven for medium documents.
3. Reduce editor churn during rapid log refreshes and large paste/load operations.
4. Consider a chunked replace path for large-file mode, only if it can stay bounded.
5. Rebenchmark after the cache-lifecycle hardening pass and decide whether idle/medium-tab footprint still needs another general-session optimization pass.

## Next Execution Passes

### Pass A. Measurement first

Goal: stop guessing and make the next memory changes defendable.

Add a repeatable profiling checklist that captures:

- launch idle footprint after app settles
- footprint after opening 10 medium files
- footprint after opening a large plain text file
- footprint after opening a large markdown file
- footprint after opening a live `.log` file with auto-reload enabled
- footprint after quitting and relaunching into a restored session with one large saved file

For each scenario, record:

- `vmmap` physical footprint
- `vmmap` peak physical footprint
- process RSS for rough comparison only
- active workspace count
- active tab count
- selected document size
- whether the document is in normal editor mode, large-file safe mode, or `Edit Anyway`
- whether markdown preview or log watching is active

Deliverable:

- a checked-in benchmark checklist or helper script
  - implemented as `scripts/capture-memory-snapshot.sh` and `benchmarks/README.md`
- one baseline result file for the current codebase

### Pass B. Visible-range line-number work

Goal: stop medium-size files from paying full-document line-number cost.

Current state:

- large-file mode disables line numbers
- non-large documents still maintain more line metadata than needed for what is on screen

Implement next:

- compute displayed line-number ranges from the layout manager's visible glyph/character range
- avoid deriving or updating line-number labels for off-screen content
- keep the status bar line/column path independent from any full gutter recomputation

Success criteria:

- scrolling medium documents does not trigger obvious full-buffer line-number churn
- opening a medium-large file with line numbers enabled does not materially change peak footprint

### Pass C. Coalesce rapid editor refreshes

Goal: reduce churn when the text system gets hit by repeated external updates.

Focus areas:

- log file auto-reload bursts
- repeated `NSTextView` updates during large file load/replace flows
- unnecessary redraw/re-highlight work when content changes arrive faster than the UI can display

Implement next:

- debounce or coalesce external log-driven text refreshes
- avoid reapplying attributes if the visible text segment has not materially changed
- avoid redundant cursor/status recomputation during programmatic content swaps

Success criteria:

- live logs stay responsive without bursty memory spikes
- repeated append refreshes do not cause visible editor stutter

### Pass D. Session-cache lifecycle hardening

Goal: keep the new file-backed session cache from quietly accumulating junk.

Status: completed.

Implemented:

- cache files now live in an explicit app-scoped Application Support folder
- legacy cache files are still readable and are migrated forward when referenced by a restored session
- startup scavenging removes orphaned cache files not referenced by the current restored session
- restored unsaved placeholder documents no longer overwrite their own cache file with an empty buffer during subsequent session persistence

Success criteria:

- quitting and relaunching repeatedly should no longer grow cached session storage without bound
- old unsaved-buffer cache files are removed once they are no longer reachable

## Deferred / Lower Priority

These are possible optimizations, but they should not go ahead of measurement and viewport-based work:

- chunked replace for large-file mode
- richer match counting/status for on-demand large-file search
- more aggressive markdown preview optimization beyond the current threshold + debounce behavior

Reason:

- they are useful, but they are less likely to move the main pain points than measurement, line-number viewport work, and refresh coalescing

## Out of Scope For Now

These would be larger architectural shifts and should not be mixed into the current incremental memory passes without fresh evidence:

- replacing the normal text engine for all documents
- building a fully paged/chunked editing model for regular files
- introducing a database-backed session store
- adding background indexing or precomputed search databases

These may become necessary for extreme-file workflows, but they are not the next rational steps for the current app.

## Current Targets

- Idle LunaPad physical footprint: under `40 MB`
- Typical editing session: under `60 MB` physical footprint
- Large-file restore should not block app launch
- Large-file open should not freeze the main thread
- Closing a heavy tab/workspace should allow footprint to recover

## Practical Exit Criteria

The current memory optimization track can be considered successful when all of these are true:

- a restored session containing one large saved file no longer causes a launch stall
- opening a large file keeps the UI interactive from selection through first render
- live log viewing does not show runaway growth during repeated append bursts
- medium documents with line numbers enabled scroll without obvious recomputation pauses
- closing a heavy document or workspace allows footprint to settle back down instead of ratcheting upward across repeated tests
