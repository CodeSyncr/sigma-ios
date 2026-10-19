# Changelog

## 2.1.0

The first public release of the native editor (2.0.0 was withdrawn on the day it was published).

- The engine is no longer in the package: a session downloads it from Sigma for a sheet opened through the API, verifies its SHA-256, and keeps it in memory only.
- A workbook comes only from a `SigmaSession`; the offline `SigmaWorkbook(json:)` and `SigmaWorkbook.importing(_:format:name:)` are gone.
- A sheet opened with a test-mode key shows a "Test mode" banner; `SigmaSession.Document.test` says so in code.
- An open refused for an account over its allowance fails with `SigmaError.quotaExceeded`.
- The licence is now proprietary.

## 2.0.0 (withdrawn)

The editor is native. 1.x showed Sigma's web editor in a web view; 2.0 draws the sheet with UIKit and SwiftUI and runs Sigma's own engine in JavaScriptCore.

- `SigmaSession` opens a sheet from a signed link and saves every change back (the file in its own format, and Sigma's workbook), refreshing expired links and ended sessions through your closure.
- `SigmaSheetView` (SwiftUI) and `SigmaSheetViewController` (UIKit): the grid with frozen panes, selection handles, in-cell and formula-bar editing, column resizing, a long-press menu and sheet tabs; a format bar (styles, colours, alignment, number formats, borders, text size); find and replace; sort that keeps a header row; conditional formatting; notes; charts with Swift Charts; Vani AI; sharing as Excel or CSV.
- `SigmaWorkbook`: the open sheet in Sigma's engine, for reading and changing cells, styles, charts and sheets from code.
- `SigmaGridController` drives the grid from your own controls.

### Moving from 1.x

- iOS 16 is now the minimum (Swift Charts). macOS builds keep the client and engine; the editor views are iOS.
- `SigmaEditor` + `SigmaEditorView` become `SigmaSession` + `SigmaSheetView`; `SigmaEditorViewController` becomes `SigmaSheetViewController`. The link closure is the same.

  ```swift
  // 1.x
  @StateObject var editor = SigmaEditor { try await MyAPI.sheetLink(id: 42) }
  SigmaEditorView(editor: editor)

  // 2.0
  @StateObject var session = SigmaSession { try await MyAPI.sheetLink(id: 42) }
  SigmaSheetView(session: session)
  ```
- `editor.save()` → `session.save()`; `editor.export(_:)` → `session.export(_:)`; `editor.setCells` / `values` / `undo` → `session.workbook` (`set(_:)`, `value(at:)`, `undo()`).
- `SigmaEvent` and `onEvent` are gone: observe the session's `phase`, `saveState` and `lastSaved` instead.
- `SigmaEditorDocument` is now `SigmaSession.Document`.
- `SigmaClient`, `SigmaFile`, `SigmaShareSheet` and `SigmaContentTypes` are unchanged.

## 1.0.0

- `SigmaEditor`, `SigmaEditorView` and `SigmaEditorViewController`: Sigma's web editor in a web view, opened from a signed link, saving every change back to Nimbus Cloud.
- `SigmaClient` for server-side Swift: upload, blank sheets, links, content, workbook JSON, delete, usage.
- `SigmaShareSheet` and `SigmaContentTypes` for sharing exports and picking files to upload.
