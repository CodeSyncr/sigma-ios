import XCTest
@testable import NimbusSigma

/// Sigma's engine in real JavaScriptCore: no network, no web view. The
/// package does not ship the engine; these tests read Sigma's build of it
/// (SIGMA_ENGINE_JS, or the Sigma repo beside this one) and skip without it.
@MainActor
final class EngineTests: XCTestCase {
    static let engine: String? = {
        let env = ProcessInfo.processInfo.environment["SIGMA_ENGINE_JS"]
        let beside = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../sigma/app/native/sigma-core.js").standardized.path
        return [env, beside].compactMap { $0 }.lazy.compactMap { try? String(contentsOfFile: $0, encoding: .utf8) }.first
    }()

    private func engine() throws -> String {
        guard let e = Self.engine else { throw XCTSkip("Sigma's engine build was not found; set SIGMA_ENGINE_JS.") }
        return e
    }

    func testFunctionsSheetsAndPasteValues() throws {
        let book = try SigmaWorkbook(engine: engine())
        let fns = book.functions()
        XCTAssertGreaterThanOrEqual(fns.count, 80)
        XCTAssertEqual(fns.first { $0.name == "SUMIF" }?.syntax, "SUMIF(range, criterion, [sum_range])")

        try book.set([SigmaAddress("A1")!: "2", SigmaAddress("A2")!: "=A1*21"])
        try book.applyStyle(SigmaStyle(bold: true), from: SigmaAddress("C1")!, to: SigmaAddress("C1")!)
        let clip = try book.copy(SigmaSelection(SigmaAddress("A2")!))
        try book.pasteValues(clip, at: SigmaAddress("C1")!)
        XCTAssertEqual(book.input(at: SigmaAddress("C1")!), "42")
        XCTAssertEqual(book.style(at: SigmaAddress("C1")!).bold, true)

        XCTAssertEqual(try book.duplicateSheet(0), 1)
        XCTAssertEqual(book.sheets.map(\.name), ["Sheet1", "Sheet1 copy"])
        XCTAssertEqual(book.activeSheet, 1)
        XCTAssertEqual(book.value(at: SigmaAddress("A2")!, sheet: 1), .number(42))
        try book.moveSheet(from: 1, to: 0)
        XCTAssertEqual(book.sheets.map(\.name), ["Sheet1 copy", "Sheet1"])
        XCTAssertTrue(book.undo())
        XCTAssertEqual(book.sheets.map(\.name), ["Sheet1", "Sheet1 copy"])
    }

    func testFormulasStylesAndUndo() throws {
        let book = try SigmaWorkbook(engine: engine())
        XCTAssertTrue(book.engineVersion.hasPrefix("sigma@"), book.engineVersion)
        XCTAssertEqual(book.sheets.map(\.name), ["Sheet1"])

        try book.set([
            SigmaAddress("A1")!: "Item", SigmaAddress("B1")!: "Cost",
            SigmaAddress("A2")!: "Rent", SigmaAddress("B2")!: "1200",
            SigmaAddress("A3")!: "Food", SigmaAddress("B3")!: "450",
            SigmaAddress("B4")!: "=SUM(B2:B3)", SigmaAddress("B5")!: "=B4/0",
        ])
        XCTAssertEqual(book.value(at: SigmaAddress("B4")!), .number(1650))
        XCTAssertEqual(book.value(at: SigmaAddress("B5")!), .text("#DIV/0!"))
        XCTAssertEqual(book.input(at: SigmaAddress("B4")!), "=SUM(B2:B3)")

        try book.applyStyle(SigmaStyle(bold: true, fill: "#fde68a", numberFormat: .currency), from: SigmaAddress("B4")!, to: SigmaAddress("B4")!)
        let cells = book.cells(rows: 0...5, columns: 0...2)
        let b4 = try XCTUnwrap(cells.first { $0.row == 3 && $0.column == 1 })
        XCTAssertEqual(b4.style?.bold, true)
        XCTAssertEqual(b4.style?.fill, "#fde68a")
        XCTAssertTrue(b4.isNumber)
        XCTAssertTrue(b4.text.contains("1,650"), b4.text)
        XCTAssertTrue(cells.first { $0.row == 4 && $0.column == 1 }?.isError ?? false)

        let rev = book.revision
        XCTAssertTrue(book.undo())
        XCTAssertGreaterThan(book.revision, rev)
        XCTAssertNil(book.style(at: SigmaAddress("B4")!).bold)
        XCTAssertTrue(book.redo())
        XCTAssertEqual(book.style(at: SigmaAddress("B4")!).bold, true)

        try book.insertRows(at: 0)
        XCTAssertEqual(book.input(at: SigmaAddress("B5")!), "=SUM(B3:B4)", "formulas move with inserted rows")
    }

    func testSheets() throws {
        let book = try SigmaWorkbook(engine: engine())
        let i = try book.addSheet()
        XCTAssertEqual(i, 1)
        XCTAssertEqual(book.activeSheet, 1)
        try book.renameSheet(1, to: "Totals")
        try book.set("=Sheet1!A1*2", at: SigmaAddress("A1")!)
        try book.set("21", at: SigmaAddress("A1")!, sheet: 0)
        XCTAssertEqual(book.value(at: SigmaAddress("A1")!), .number(42))
        XCTAssertThrowsError(try book.renameSheet(1, to: "Sheet1"))
        try book.deleteSheet(1)
        XCTAssertEqual(book.sheets.count, 1)
        XCTAssertThrowsError(try book.deleteSheet(0), "the last sheet stays")
    }

    func testXlsxAndCsvRoundTrip() async throws {
        let book = try SigmaWorkbook(engine: engine())
        try book.set([SigmaAddress("A1")!: "नाम — naïve ✓", SigmaAddress("B1")!: "3.5", SigmaAddress("C1")!: "=B1*2"])
        try book.applyStyle(SigmaStyle(italic: true, textColor: "#c0392b"), from: SigmaAddress("A1")!, to: SigmaAddress("A1")!)
        try book.freeze(rows: 1, columns: 0)

        let xlsx = try await book.export(.xlsx)
        XCTAssertEqual(Array(xlsx.prefix(2)), [0x50, 0x4B])
        let back = try await SigmaWorkbook.importing(xlsx, format: .xlsx, name: "back.xlsx", engine: engine())
        XCTAssertEqual(back.input(at: SigmaAddress("A1")!), "नाम — naïve ✓", "UTF-8 survives JavaScriptCore both ways")
        XCTAssertEqual(back.input(at: SigmaAddress("C1")!), "=B1*2")
        XCTAssertEqual(back.value(at: SigmaAddress("C1")!), .number(7))
        XCTAssertEqual(back.style(at: SigmaAddress("A1")!).italic, true)
        XCTAssertEqual(back.style(at: SigmaAddress("A1")!).textColor, "#c0392b")
        XCTAssertEqual(back.sheets.first?.frozenRows, 1)

        let csv = try await book.export(.csv)
        XCTAssertEqual(String(decoding: csv, as: UTF8.self), "नाम — naïve ✓,3.5,7")
        let fromCsv = try await SigmaWorkbook.importing(Data("a,b\n\"x, y\",2\n".utf8), format: .csv, name: "q.csv", engine: engine())
        XCTAssertEqual(fromCsv.input(at: SigmaAddress("A2")!), "x, y")
        XCTAssertEqual(fromCsv.sheets.map(\.name), ["q"])
    }

    func testBadInputIsAnError() async {
        do {
            _ = try await SigmaWorkbook.importing(Data("not a zip".utf8), format: .xlsx, name: "x.xlsx", engine: engine())
            XCTFail("expected an error")
        } catch {
            guard case .engine(let m)? = error as? SigmaError else { return XCTFail("\(error)") }
            XCTAssertTrue(m.contains(".xlsx"), m)
        }
    }

    func testClipboardAndFill() throws {
        let book = try SigmaWorkbook(engine: engine())
        try book.set([SigmaAddress("A1")!: "1", SigmaAddress("B1")!: "=A1*10", SigmaAddress("A2")!: "2"])

        // Copied inside the workbook, a formula shifts with where it lands.
        let clip = try book.copy(SigmaSelection(active: SigmaAddress("A1")!, corner: SigmaAddress("B1")!))
        XCTAssertEqual(clip.text, "1\t10")
        let landed = try book.paste(clip.text, clip: clip, at: SigmaAddress("A5")!)
        XCTAssertEqual(landed.rows, 1)
        XCTAssertEqual(landed.columns, 2)
        XCTAssertEqual(book.input(at: SigmaAddress("B5")!), "=A5*10")

        // Text from another app lands as values.
        try book.paste("x\ty\n3\t4", at: SigmaAddress("D1")!)
        XCTAssertEqual(book.input(at: SigmaAddress("E2")!), "4")

        // A cut clears at once and moves on paste, formulas unshifted.
        try book.set("=A1", at: SigmaAddress("G1")!)
        let cut = try book.cut(SigmaSelection(SigmaAddress("G1")!))
        XCTAssertEqual(book.input(at: SigmaAddress("G1")!), "")
        try book.paste(cut.text, clip: cut, at: SigmaAddress("H3")!)
        XCTAssertEqual(book.input(at: SigmaAddress("H3")!), "=A1")

        // Fill continues the series and shifts formulas.
        try book.fill(from: SigmaSelection(active: SigmaAddress("A1")!, corner: SigmaAddress("B2")!),
                      to: SigmaSelection(active: SigmaAddress("A1")!, corner: SigmaAddress("B4")!))
        XCTAssertEqual(book.input(at: SigmaAddress("A4")!), "4")
        XCTAssertEqual(book.input(at: SigmaAddress("B3")!), "=A3*10")
        XCTAssertEqual(book.value(at: SigmaAddress("B3")!), .number(30))
        XCTAssertEqual(book.input(at: SigmaAddress("B4")!), "", "the empty B2 repeats too, as on the web")
    }

    func testFormattingNotesSortFindRules() throws {
        let book = try SigmaWorkbook(engine: engine())
        let A = { SigmaAddress($0)! }
        try book.set([A("A1"): "Name", A("B1"): "Score", A("A2"): "Cara", A("B2"): "72",
                      A("A3"): "Abe", A("B3"): "95", A("A4"): "Bo", A("B4"): "40"])

        // Borders, and a style key removed by an empty value.
        try book.applyBorders(.outer, from: A("A1"), to: A("B2"))
        XCTAssertEqual(book.style(at: A("A1")).borderTop, true)
        XCTAssertEqual(book.style(at: A("B2")).borderRight, true)
        XCTAssertNil(book.style(at: A("A2")).borderRight)
        try book.applyStylePatch(["bg": "#ff0000", "b": true], to: SigmaSelection(A("A1")))
        try book.applyStylePatch(["bg": "", "b": false], to: SigmaSelection(A("A1")))
        XCTAssertNil(book.style(at: A("A1")).fill)
        XCTAssertNil(book.style(at: A("A1")).bold)

        // Notes.
        try book.setNote("Checked twice", at: A("B3"))
        XCTAssertEqual(book.note(at: A("B3")), "Checked twice")
        XCTAssertTrue(book.cells(rows: 2...2, columns: 1...1).first?.hasNote ?? false)
        try book.setNote("", at: A("B3"))
        XCTAssertEqual(book.note(at: A("B3")), "")

        // Sort a block by its second column, descending; a single cell finds the block.
        let sorted = try book.sort(SigmaSelection(active: A("A2"), corner: A("B4")), byColumn: 1, ascending: false)
        XCTAssertEqual(sorted.description, "A2:B4")
        XCTAssertEqual((2...4).map { book.input(at: SigmaAddress(row: $0 - 1, column: 0)) }, ["Abe", "Cara", "Bo"])
        let block = try book.sort(SigmaSelection(A("A3")), byColumn: 0, ascending: true)
        XCTAssertEqual(block.description, "A2:B4", "a single cell sorts the block around it, header row left in place")
        XCTAssertEqual((0...3).map { book.input(at: SigmaAddress(row: $0, column: 0)) }, ["Name", "Abe", "Bo", "Cara"])

        // Find and replace.
        XCTAssertEqual(book.find("ab").map(\.description), ["A2"])
        XCTAssertEqual(book.find("AB", matchCase: true), [])
        let rev = book.revision
        XCTAssertEqual(book.find("zzz"), [])
        XCTAssertEqual(book.revision, rev, "finding changes nothing")
        XCTAssertEqual(try book.replaceAll("o", with: "0"), 2)
        XCTAssertEqual(book.input(at: A("A3")), "B0")
        XCTAssertEqual(book.input(at: A("B1")), "Sc0re")

        // A conditional rule colours matching cells and survives a round trip.
        let rule = SigmaConditionalRule(range: SigmaSelection(active: A("B2"), corner: A("B4")), condition: .greaterThan, value: "50", fill: "#c6efce", bold: true)
        try book.addConditionalRule(rule)
        XCTAssertEqual(book.conditionalRules(), [rule])
        let shown = Dictionary(uniqueKeysWithValues: book.cells(rows: 1...3, columns: 1...1).map { ($0.row, $0) })
        let high = shown.values.filter { $0.style?.fill == "#c6efce" }.map(\.text).sorted()
        XCTAssertEqual(high, ["72", "95"])
        try book.removeConditionalRule(at: 0)
        XCTAssertEqual(book.conditionalRules(), [])
    }

    func testChartsAndPatches() throws {
        let book = try SigmaWorkbook(engine: engine())
        let A = { SigmaAddress($0)! }
        try book.set([A("A1"): "Month", A("B1"): "Sales", A("C1"): "Costs",
                      A("A2"): "Jan", A("B2"): "100", A("C2"): "60",
                      A("A3"): "Feb", A("B3"): "140", A("C3"): "=C2+10"])

        var chart = try book.addChart(.line, data: "A1:C3", title: "Q1")
        XCTAssertEqual(chart.column, 4, "beside the data, as on the web")
        XCTAssertEqual(chart.width, 460)
        let (shown, data) = try XCTUnwrap(book.charts().first)
        XCTAssertEqual(shown.kind, .line)
        XCTAssertEqual(data.labels, ["Jan", "Feb"])
        XCTAssertEqual(data.series.map(\.name), ["Sales", "Costs"])
        XCTAssertEqual(data.series[1].values, [60, 70], "formulas are read computed")

        try book.set("200", at: A("B3"))
        XCTAssertEqual(book.charts().first?.data.series[0].values, [100, 200], "a chart reads live cells")

        chart.kind = .column
        chart.title = nil
        chart.stacked = true
        chart.row = 5
        try book.updateChart(chart)
        let updated = try XCTUnwrap(book.charts().first?.chart)
        XCTAssertEqual(updated.kind, .column)
        XCTAssertNil(updated.title)
        XCTAssertEqual(updated.stacked, true)
        XCTAssertEqual(updated.row, 5)
        try book.removeChart(id: chart.id)
        XCTAssertTrue(book.charts().isEmpty)

        // A Vani AI patch: described, applied as one step, undone as one step.
        let patch = #"{"cells":[{"a":"A4","v":"Total"},{"a":"B4","v":"=SUM(B2:B3)"}],"styles":[{"range":"A4:B4","b":true}],"charts":[{"type":"pie","data":"A1:B3","anchor":"E8"}]}"#
        XCTAssertEqual(book.describePatch(patch), "2 cells · 1 format · 1 chart")
        let result = try book.applyPatch(patch)
        XCTAssertEqual(result.cells, 2)
        XCTAssertEqual(result.charts, 1)
        XCTAssertTrue(result.summary.hasPrefix("Applied"), result.summary)
        XCTAssertEqual(book.value(at: A("B4")), .number(300))
        XCTAssertEqual(book.style(at: A("A4")).bold, true)
        XCTAssertEqual(book.charts().first?.chart.kind, .pie)
        XCTAssertTrue(book.undo())
        XCTAssertEqual(book.input(at: A("B4")), "")
        XCTAssertTrue(book.charts().isEmpty, "one undo takes the whole patch back")

        let context = book.aiContext()
        XCTAssertTrue(context.grid.contains("Month"), context.grid)
        XCTAssertEqual(context.used, "A1:C3")
    }

    func testAddresses() {
        XCTAssertEqual(SigmaAddress("A1"), SigmaAddress(row: 0, column: 0))
        XCTAssertEqual(SigmaAddress("$AB$12"), SigmaAddress(row: 11, column: 27))
        XCTAssertNil(SigmaAddress("12"))
        XCTAssertNil(SigmaAddress("A"))
        XCTAssertEqual(SigmaAddress(row: 0, column: 702).description, "AAA1")
    }

    func testEmbedAccess() {
        let a = SigmaSession.access(from: URL(string: "http://localhost:3344/embed/12?t=v1.12.7.edit.99.abc")!)
        XCTAssertEqual(a, SigmaSession.Access(base: URL(string: "http://localhost:3344")!, id: 12, token: "v1.12.7.edit.99.abc"))
        let b = SigmaSession.access(from: URL(string: "https://example.com/sigma/embed/3?t=x")!)
        XCTAssertEqual(b?.base.absoluteString, "https://example.com/sigma")
        XCTAssertNil(SigmaSession.access(from: URL(string: "https://example.com/v/sigma/3")!))
    }
}
