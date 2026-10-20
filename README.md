# Nimbus Sigma for iOS

A native spreadsheet editor for your iOS app, backed by [Sigma](https://nimbusgo.space/cloud/docs/sigma) on Nimbus Cloud. Upload a spreadsheet from your server, open it in the app, and people edit it with formulas, formatting, charts, several sheets and Vani AI. Every change saves back as they type, and your server downloads the edited `.xlsx` or CSV whenever it likes.

It is native throughout: a UIKit grid, a SwiftUI format bar, Swift Charts. The formulas are Sigma's own engine, the same code the web editor runs, executed in JavaScriptCore, so a sheet computes the same on an iPhone as on the web. There is no web view.

The engine is not in this package. Each session downloads it from Sigma for a sheet opened through the API, checks it, and keeps it in memory only, so the editor works only with a Nimbus Cloud account and a Sigma API key.

**Requirements:** iOS 16 / visionOS 1, Xcode 15.3+ (Swift 5.10). The client and engine also build for macOS 13 (for server-side Swift and tests); the editor views are iOS.

## Install

Swift Package Manager: in Xcode, **File › Add Package Dependencies…** and enter:

```
https://github.com/CodeSyncr/sigma-ios.git
```

or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/CodeSyncr/sigma-ios.git", from: "2.1.1"),
],
targets: [
    .target(name: "App", dependencies: [.product(name: "NimbusSigma", package: "sigma-ios")]),
]
```

CocoaPods:

```ruby
pod 'NimbusSigma', :git => 'https://github.com/CodeSyncr/sigma-ios.git', :tag => '2.1.1'
```

## How it fits together

```
your server ──(sgm_ key)──▶ Nimbus Cloud     upload sheets, mint signed links, download edits
     │
     └──(signed link)──▶ your app ──▶ SigmaSession ──▶ SigmaSheetView     edits save straight back
```

**Billing.** Sigma's API counts each time a sheet is opened in an editor (in your app or embedded on the web), not uploads; your plan includes an allowance each month. Test keys (`sgm_test_`) are for building: their opens are capped and their sheets are deleted after a week, and the editor shows "Test mode".

**Keep the `sgm_` key on your server.** A key compiled into an app can be extracted, and it can read and delete every document on your account. The app only ever needs a link, which expires (fifteen minutes by default; one minute to seven days). Once a link opens a sheet, the editing session lasts eight hours.

On your server (any language; here, the REST API):

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
    @StateObject private var session: SigmaSession

    init(sheetID: Int) {
        // Asked for a link when the sheet opens, and again whenever one expires.
        _session = StateObject(wrappedValue: SigmaSession { try await MyAPI.sheetLink(id: sheetID) })
    }

    var body: some View {
        SigmaSheetView(session: session)
            .navigationTitle(session.title)
    }
}
```

UIKit:

```swift
let session = SigmaSession { try await MyAPI.sheetLink(id: 42) }
navigationController?.pushViewController(SigmaSheetViewController(session: session), animated: true)
```

### What people get

- **The grid:** smooth scrolling, pinch to zoom, sticky headers, frozen rows and columns (with presets), tap to select, round handles to stretch a selection, drag to fill, tap again to type, a formula bar, a row of formula keys above the keyboard, column and row resizing, a long-press menu (cut, copy, paste, paste values only, fill, insert and delete rows and columns, sort, notes, freeze), sheet tabs (rename, duplicate, move, delete), undo and redo. iPad keyboards get arrows, Tab, Return, ⌘C/X/V/Z/A/D/R/B/I/U/F and ⌘+/−/0 to zoom.
- **Formulas:** suggestions as you type a function name, the syntax of the function you are in with the current argument highlighted, and an Insert Function list by category; AutoSum.
- **Formatting:** bold, italic, underline, strikethrough, text and fill colours, alignment, number formats, decimals, text size, borders, Clear formatting.
- **Data:** find and replace, sort (a header row stays put), conditional formatting, notes.
- **Charts:** column, bar, line, area, scatter, pie and doughnut, drawn with Swift Charts and bound to their cells. Move, resize, restyle, delete.
- **Vani AI**, when your Nimbus Cloud account is on Pro: people ask, and apply the change it proposes as one undo step. Its use counts against your plan.
- **Share:** the sheet as Excel or CSV through the system share sheet.

### The session

| Published | Meaning |
|---|---|
| `phase` | `.loading`, `.ready`, or `.failed(SigmaError)` |
| `document` | id, title, file name, format (`.xlsx`/`.csv`) and mode (`.edit`/`.view`) |
| `title` | the sheet's name; set it to rename |
| `saveState` | `.saved`, `.unsaved`, `.saving`, or `.failed` |
| `workbook` | the open `SigmaWorkbook` |
| `aiAvailable` | whether Vani AI is offered |

```swift
try await session.save()                        // save now, without waiting
let file = try await session.export(.xlsx)      // SigmaFile: data + filename
```

When a link has expired or been revoked, the session asks your closure for a fresh one. If the editing session ends while someone is working, it gets a fresh link and saves again; nothing typed is lost.

### Driving the sheet from code

`SigmaWorkbook` is the open sheet in Sigma's engine:

```swift
let book = session.workbook!
try book.set([SigmaAddress("A1")!: "Rent", SigmaAddress("B1")!: "1200", SigmaAddress("B3")!: "=SUM(B1:B2)"])
book.value(at: SigmaAddress("B3")!)              // .number(1200)
try book.applyStyle(SigmaStyle(bold: true, fill: "#fff2cc"), from: SigmaAddress("A1")!, to: SigmaAddress("B1")!)
try book.addChart(.column, data: "A1:B2")
book.undo()
```

Pass a `SigmaGridController` to `SigmaSheetView` to read the selection or drive the grid (select, format, sort, insert a chart, open a panel) from your own controls.

## Server-side Swift

`SigmaClient` wraps the REST API for Vapor, Hummingbird, command-line tools and prototypes. Do not ship it in an app.

```swift
let sigma = SigmaClient(apiKey: Environment.get("SIGMA_KEY")!)
let doc = try await sigma.upload(data, filename: "budget.xlsx", mode: .edit)
let link = try await sigma.link(for: doc.id, mode: .edit, lifetime: 600)
let edited = try await sigma.content(of: doc.id)
```

## Example

[`Examples/SigmaDemo`](Examples/SigmaDemo) is a small app: list your sheets, create or upload one, edit it, export it.

1. Open `Examples/SigmaDemo/SigmaDemo.xcodeproj` and run it on a simulator or your phone (pick your team under Signing for a phone).
2. Tap the gear and enter your Nimbus Cloud address and a Sigma key (`sgm_test_…` from Nimbus Cloud › API & CLI Keys). In the Simulator, `http://localhost:3333` is a cloud running on your Mac.

The demo keeps the key on the device so it runs on its own. A real app keeps it on its server.

If Xcode says **"iOS 26.2 is not installed"**, it cannot build for iOS until you add the platform in **Xcode › Settings › Components** (several GB). Until then, `Examples/SigmaDemo/run-in-simulator.sh` builds the demo with SwiftPM and runs it in the Simulator:

```bash
SIGMA_CLOUD=http://localhost:3333 SIGMA_KEY=sgm_test_… Examples/SigmaDemo/run-in-simulator.sh
```

## Tests

`swift test` runs the unit tests. The engine tests need Sigma's engine build (`SIGMA_ENGINE_JS=/path/to/sigma-core.js`) and skip without it. To open real sheets against a running cloud:

```bash
SIGMA_E2E_CLOUD=http://localhost:3333 SIGMA_E2E_KEY=sgm_test_… swift test
```

## License

Proprietary. The SDK may be used only with Nimbus Cloud's Sigma API under your Nimbus Cloud account; see [LICENSE](LICENSE).
