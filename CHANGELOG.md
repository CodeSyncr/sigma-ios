# Changelog

## 1.0.0

- `SigmaEditor`, `SigmaEditorView` and `SigmaEditorViewController`: the Sigma spreadsheet editor in an app, opened from a signed link, saving every change back to Nimbus Cloud.
- Commands: `save()`, `export(.xlsx / .csv)`, `undo()`, `redo()`, `setCells(_:)`, `values(_:)`, `sheetNames()`.
- Expired links and ended sessions are replaced through a `refreshLink` closure that asks your server.
- `SigmaClient` for server-side Swift: upload, blank sheets, links, content, workbook JSON, delete, usage.
- `SigmaShareSheet` and `SigmaContentTypes` for sharing exports and picking files to upload.
