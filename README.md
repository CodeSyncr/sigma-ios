# Nimbus Sigma for iOS

The [Sigma](https://nimbusgo.space/cloud/docs/sigma) spreadsheet editor inside your iOS app. Upload a spreadsheet to Nimbus Cloud from your server, open it in the app, and people edit it with formulas, formatting, charts and several sheets. Every change saves back as they type, and your server downloads the edited `.xlsx` or CSV whenever it likes.

**Requirements:** iOS 15 / macOS 12 / visionOS 1, Xcode 15.3+ (Swift 5.10).

## Install

Swift Package Manager — in Xcode, **File › Add Package Dependencies…** and enter:

```
https://github.com/CodeSyncr/sigma-ios.git
```

or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/CodeSyncr/sigma-ios.git", from: "1.0.0"),
],
targets: [
    .target(name: "App", dependencies: [.product(name: "NimbusSigma", package: "sigma-ios")]),
]
```

CocoaPods:

```ruby
pod 'NimbusSigma', :git => 'https://github.com/CodeSyncr/sigma-ios.git', :tag => '1.0.0'
```

## How it fits together

```
your server ──(sgm_ key)──▶ Nimbus Cloud     upload sheets, mint signed links, download edits
     │
     └──(signed link)──▶ your app ──▶ SigmaEditor     edits save straight back to the document
```

**Keep the `sgm_` key on your server.** A key compiled into an app can be extracted, and it can read and delete every document on your account. The app only ever needs a link, which expires (fifteen minutes by default; one minute to seven days). Once a link opens a sheet, the editing session lasts eight hours.

On your server (any language — here, the REST API):

```bash
# Upload, or create a blank sheet with {"title": "Budget", "blank": "xlsx"}
curl -X POST "https://nimbusgo.space/api/v1/sigma/documents?mode=edit" \
  -H "Authorization: Bearer $SIGMA_KEY" -F file=@budget.xlsx

# A fresh link for the app
curl -X POST "https://nimbusgo.space/api/v1/sigma/documents/42/link?mode=edit" \
  -H "Authorization: Bearer $SIGMA_KEY"

# The edited file, later
curl "https://nimbusgo.space/api/v1/sigma/documents/42/content" \
  -H "Authorization: Bearer $SIGMA_KEY" -o budget.xlsx
```

## Use

```swift
import NimbusSigma

struct SheetScreen: View {
    @StateObject private var editor: SigmaEditor

    init(sheetID: Int) {
        // Asked for a link when the sheet opens, and again whenever one expires.
        _editor = StateObject(wrappedValue: SigmaEditor { try await MyAPI.sheetLink(id: sheetID) })
    }

    var body: some View {
        SigmaEditorView(editor: editor)
            .navigationTitle(editor.title)
            .toolbar {
                if editor.hasUnsavedChanges { ProgressView() }
            }
    }
}
```

UIKit:

```swift
let editor = SigmaEditor(link: url) { try await MyAPI.sheetLink(id: 42) }
navigationController?.pushViewController(SigmaEditorViewController(editor: editor), animated: true)
```

### What the editor tells you

| Published | Meaning |
|---|---|
| `phase` | `.loading`, `.ready`, or `.failed(SigmaError)` |
| `document` | id, title, file name, format (`.xlsx`/`.csv`) and mode (`.edit`/`.view`) |
| `title` | the sheet's name, as the person renames it |
| `hasUnsavedChanges` | true from a change until it is saved (about a second later) |
| `lastSaved`, `lastError` | the last save, and the last failure while open |

`onEvent` delivers every event (`ready`, `changed`, `saved`, `titleChanged`, `error`) for apps that want them all.

### Commands

```swift
try await editor.save()                          // save now (throws for a view link)
let file = try await editor.export(.xlsx)        // SigmaFile: data + filename
try await editor.setCells(["A1": "Rent", "B1": "1200", "B3": "=SUM(B1:B2)"])
let rows = try await editor.values("A1:B3")      // [[SigmaValue]], formulas computed
try await editor.undo()
```

Share an export with the system share sheet:

```swift
.sheet(item: $file) { file in
    if let sheet = try? SigmaShareSheet(file: file) { sheet }
}
```

Let people pick a spreadsheet to upload (through your server):

```swift
.fileImporter(isPresented: $picking, allowedContentTypes: SigmaContentTypes.all) { result in
    if case let .success(url) = result, let (data, name) = try? SigmaContentTypes.read(url) {
        Task { try await MyAPI.uploadSheet(data, filename: name) }
    }
}
```

### Expired links

When a link has expired or been revoked, or an editing session ends, the editor calls your `refreshLink` closure once and opens the sheet again. Saved work is never lost: changes are in the document. Without a closure the editor fails with `SigmaError.linkExpired`.

### Vani AI

If your Nimbus Cloud account is on Pro, people get Vani AI in the sheet (building sheets, formulas, charts). Its use counts against your plan. On other plans it does not appear.

## Server-side Swift

`SigmaClient` wraps the REST API for Vapor, Hummingbird, command-line tools and prototypes. Do not ship it in an app.

```swift
let sigma = SigmaClient(apiKey: Environment.get("SIGMA_KEY")!)
let doc = try await sigma.upload(data, filename: "budget.xlsx", mode: .edit)
let link = try await sigma.link(for: doc.id, mode: .edit, lifetime: 600)
let edited = try await sigma.content(of: doc.id)
```

## Example

[`Examples/SigmaDemo`](Examples/SigmaDemo) is a small app: list your sheets, create or upload one, edit it, fill in a sample, and export.

1. Open `Examples/SigmaDemo/SigmaDemo.xcodeproj` and run it on a simulator or your phone (pick your team under Signing for a phone).
2. Tap the gear and enter your Nimbus Cloud address and a Sigma key (`sgm_test_…` from Nimbus Cloud › API & CLI Keys). In the Simulator, `http://localhost:3333` is a cloud running on your Mac.

The demo keeps the key on the device so it runs on its own. A real app keeps it on its server.

If Xcode says **"iOS 26.2 is not installed"**, it cannot build for iOS until you add the platform in **Xcode › Settings › Components** (several GB). Until then, `Examples/SigmaDemo/run-in-simulator.sh` builds the demo with SwiftPM and runs it in the Simulator:

```bash
SIGMA_CLOUD=http://localhost:3333 SIGMA_KEY=sgm_test_… Examples/SigmaDemo/run-in-simulator.sh
```

`project.yml` regenerates the project with [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you change it.

## Tests

`swift test` runs the unit tests. To open a real sheet in a real `WKWebView` against a running cloud:

```bash
SIGMA_E2E_CLOUD=http://localhost:3333 SIGMA_E2E_KEY=sgm_test_… swift test
```

## License

MIT
