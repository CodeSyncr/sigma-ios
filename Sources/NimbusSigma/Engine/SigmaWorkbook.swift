import Foundation
import JavaScriptCore

/// A cell's look. Every field is optional; nil means the sheet's default.
public struct SigmaStyle: Codable, Hashable, Sendable {
    public enum Align: String, Codable, Sendable { case left = "l", center = "c", right = "r" }
    public enum NumberFormat: String, Codable, Sendable { case auto, number = "num", percent = "pct", currency = "cur", text }

    public var bold: Bool?
    public var italic: Bool?
    public var underline: Bool?
    public var strikethrough: Bool?
    public var align: Align?
    /// Points.
    public var fontSize: Double?
    /// "#rrggbb".
    public var textColor: String?
    public var fill: String?
    public var numberFormat: NumberFormat?
    public var decimals: Int?
    public var borderTop: Bool?
    public var borderBottom: Bool?
    public var borderLeft: Bool?
    public var borderRight: Bool?

    public init(bold: Bool? = nil, italic: Bool? = nil, underline: Bool? = nil, strikethrough: Bool? = nil,
                align: Align? = nil, fontSize: Double? = nil, textColor: String? = nil, fill: String? = nil,
                numberFormat: NumberFormat? = nil, decimals: Int? = nil,
                borderTop: Bool? = nil, borderBottom: Bool? = nil, borderLeft: Bool? = nil, borderRight: Bool? = nil) {
        self.bold = bold; self.italic = italic; self.underline = underline; self.strikethrough = strikethrough
        self.align = align; self.fontSize = fontSize; self.textColor = textColor; self.fill = fill
        self.numberFormat = numberFormat; self.decimals = decimals
        self.borderTop = borderTop; self.borderBottom = borderBottom; self.borderLeft = borderLeft; self.borderRight = borderRight
    }

    // Sigma's own short keys, so the JSON is the workbook's own format.
    enum CodingKeys: String, CodingKey {
        case bold = "b", italic = "i", underline = "u", strikethrough = "st", align = "al", fontSize = "fs"
        case textColor = "tc", fill = "bg", numberFormat = "nf", decimals = "dp"
        case borderTop = "bT", borderBottom = "bB", borderLeft = "bL", borderRight = "bR"
    }

    /// The engine's style patch: only the fields that are set.
    var patch: [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return dict
    }
}

/// What one cell shows, as the grid draws it.
public struct SigmaCell: Decodable, Hashable, Sendable {
    public let row: Int
    public let column: Int
    /// The formatted text, formulas computed.
    public let text: String
    public let isNumber: Bool
    public let isError: Bool
    /// The cell's style with conditional formatting applied.
    public let style: SigmaStyle?
    public let hasNote: Bool

    enum CodingKeys: String, CodingKey { case r, c, t, n, e, s, note }

    public init(from decoder: Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        row = try k.decode(Int.self, forKey: .r)
        column = try k.decode(Int.self, forKey: .c)
        text = try k.decodeIfPresent(String.self, forKey: .t) ?? ""
        isNumber = try k.decodeIfPresent(Int.self, forKey: .n) == 1
        isError = try k.decodeIfPresent(Int.self, forKey: .e) == 1
        style = try k.decodeIfPresent(SigmaStyle.self, forKey: .s)
        hasNote = try k.decodeIfPresent(Int.self, forKey: .note) == 1
    }
}

/// One sheet of a workbook.
public struct SigmaSheetInfo: Decodable, Hashable, Sendable {
    public let name: String
    public let rows: Int
    public let columns: Int
    public let frozenRows: Int
    public let frozenColumns: Int

    enum CodingKeys: String, CodingKey { case name, rows, cols, fr, fc }

    public init(from decoder: Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        name = try k.decode(String.self, forKey: .name)
        rows = try k.decode(Int.self, forKey: .rows)
        columns = try k.decode(Int.self, forKey: .cols)
        frozenRows = try k.decodeIfPresent(Int.self, forKey: .fr) ?? 0
        frozenColumns = try k.decodeIfPresent(Int.self, forKey: .fc) ?? 0
    }
}

/// Column widths and row heights, in points.
public struct SigmaSheetLayout: Decodable, Sendable {
    public let defaultColumnWidth: Double
    public let defaultRowHeight: Double
    public let columnWidths: [Int: Double]
    public let rowHeights: [Int: Double]

    enum CodingKeys: String, CodingKey { case colW, rowH, defaultColW, defaultRowH }

    public init(from decoder: Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        defaultColumnWidth = try k.decode(Double.self, forKey: .defaultColW)
        defaultRowHeight = try k.decode(Double.self, forKey: .defaultRowH)
        let cols = try k.decodeIfPresent([String: Double].self, forKey: .colW) ?? [:]
        let rows = try k.decodeIfPresent([String: Double].self, forKey: .rowH) ?? [:]
        columnWidths = Dictionary(uniqueKeysWithValues: cols.compactMap { k, v in Int(k).map { ($0, v) } })
        rowHeights = Dictionary(uniqueKeysWithValues: rows.compactMap { k, v in Int(k).map { ($0, v) } })
    }

    public func width(ofColumn c: Int) -> Double { columnWidths[c] ?? defaultColumnWidth }
    public func height(ofRow r: Int) -> Double { rowHeights[r] ?? defaultRowHeight }
}

/// A conditional formatting rule: cells in a range that meet a condition
/// take on a fill, a text colour, or bold.
public struct SigmaConditionalRule: Codable, Hashable, Sendable {
    public enum Condition: String, Codable, CaseIterable, Sendable {
        case greaterThan = "gt", lessThan = "lt", atLeast = "ge", atMost = "le"
        case equal = "eq", notEqual = "ne", contains, between, notEmpty = "notempty"

        public var label: String {
            switch self {
            case .greaterThan: return "Greater than"
            case .lessThan: return "Less than"
            case .atLeast: return "Greater than or equal to"
            case .atMost: return "Less than or equal to"
            case .equal: return "Equal to"
            case .notEqual: return "Not equal to"
            case .contains: return "Text contains"
            case .between: return "Between"
            case .notEmpty: return "Is not empty"
            }
        }

        public var needsValue: Bool { self != .notEmpty }
    }

    public var range: SigmaSelection
    public var condition: Condition
    public var value: String
    /// The upper bound, for `.between`.
    public var value2: String?
    public var fill: String?
    public var textColor: String?
    public var bold: Bool?

    public init(range: SigmaSelection, condition: Condition, value: String = "", value2: String? = nil,
                fill: String? = nil, textColor: String? = nil, bold: Bool? = nil) {
        self.range = range
        self.condition = condition
        self.value = value
        self.value2 = value2
        self.fill = fill
        self.textColor = textColor
        self.bold = bold
    }

    enum CodingKeys: String, CodingKey { case r1, c1, r2, c2, op, v1, v2, bg, tc, b }

    public init(from decoder: Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        range = SigmaSelection(active: SigmaAddress(row: try k.decode(Int.self, forKey: .r1), column: try k.decode(Int.self, forKey: .c1)),
                               corner: SigmaAddress(row: try k.decode(Int.self, forKey: .r2), column: try k.decode(Int.self, forKey: .c2)))
        condition = try k.decode(Condition.self, forKey: .op)
        value = try k.decodeIfPresent(String.self, forKey: .v1) ?? ""
        value2 = try k.decodeIfPresent(String.self, forKey: .v2)
        fill = try k.decodeIfPresent(String.self, forKey: .bg)
        textColor = try k.decodeIfPresent(String.self, forKey: .tc)
        bold = try k.decodeIfPresent(Bool.self, forKey: .b)
    }

    public func encode(to encoder: Encoder) throws {
        var k = encoder.container(keyedBy: CodingKeys.self)
        try k.encode(range.top, forKey: .r1)
        try k.encode(range.left, forKey: .c1)
        try k.encode(range.bottom, forKey: .r2)
        try k.encode(range.right, forKey: .c2)
        try k.encode(condition, forKey: .op)
        try k.encode(value, forKey: .v1)
        try k.encodeIfPresent(value2, forKey: .v2)
        try k.encodeIfPresent(fill, forKey: .bg)
        try k.encodeIfPresent(textColor, forKey: .tc)
        if bold == true { try k.encode(true, forKey: .b) }
    }
}

/// A cell's place on a sheet. Rows and columns count from zero; "A1" is (0, 0).
public struct SigmaAddress: Hashable, Sendable, CustomStringConvertible {
    public var row: Int
    public var column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    /// Reads "B12" or "$B$12".
    public init?(_ a1: String) {
        var letters = 0, digits = 0, sawDigit = false
        for ch in a1.uppercased() where ch != "$" {
            if let a = ch.asciiValue, a >= 65, a <= 90, !sawDigit {
                letters = letters * 26 + Int(a - 64)
            } else if let d = ch.wholeNumberValue {
                sawDigit = true
                digits = digits * 10 + d
            } else {
                return nil
            }
        }
        guard letters > 0, digits > 0 else { return nil }
        row = digits - 1
        column = letters - 1
    }

    public static func columnName(_ c: Int) -> String {
        var n = c + 1, out = ""
        while n > 0 {
            let r = (n - 1) % 26
            out = String(UnicodeScalar(UInt8(65 + r))) + out
            n = (n - 1) / 26
        }
        return out
    }

    public var description: String { SigmaAddress.columnName(column) + String(row + 1) }
}

/// A Sigma workbook, open in Sigma's own engine: read what cells show, change
/// them, undo, and save it as .xlsx or CSV. Everything that changes the
/// workbook bumps ``revision`` and calls ``onChange``.
@MainActor
public final class SigmaWorkbook: ObservableObject {
    @Published public private(set) var revision = 0
    @Published public private(set) var sheets: [SigmaSheetInfo] = []
    @Published public private(set) var activeSheet = 0

    /// Called after every change, for autosaving.
    public var onChange: (() -> Void)?

    let engine: SigmaEngine
    let handle: Int32

    /// A workbook only ever comes from a ``SigmaSession``: the engine it runs
    /// on is handed to a session for a sheet opened through the API.
    init(engine source: String, json: String? = nil) throws {
        engine = try SigmaEngine(source: source)
        handle = try engine.call("create", [json.map { $0 as Any } ?? NSNull()]).toInt32()
        refreshInfo()
    }

    /// Reads an .xlsx or CSV file into a new workbook, on a session's engine.
    static func importing(_ data: Data, format: SigmaFormat, name: String, engine source: String) async throws -> SigmaWorkbook {
        let reader = try SigmaEngine(source: source)
        let json = try await reader.callAsync("importFile", [data.base64EncodedString(), format.rawValue, name]).toString()
        return try SigmaWorkbook(engine: source, json: json)
    }

    /// The engine version, "sigma@<commit>".
    public var engineVersion: String { engine.version }

    // MARK: Reading

    /// Cells in a block that show something or are styled. Ask for what is on screen.
    public func cells(sheet: Int? = nil, rows: ClosedRange<Int>, columns: ClosedRange<Int>) -> [SigmaCell] {
        (try? engine.decode([SigmaCell].self, "cells", [handle, sheet ?? activeSheet, rows.lowerBound, columns.lowerBound, rows.upperBound, columns.upperBound])) ?? []
    }

    public func layout(sheet: Int? = nil) -> SigmaSheetLayout? {
        try? engine.decode(SigmaSheetLayout.self, "layout", [handle, sheet ?? activeSheet])
    }

    /// What was typed into a cell: a value or a formula.
    public func input(at a: SigmaAddress, sheet: Int? = nil) -> String {
        (try? engine.call("raw", [handle, sheet ?? activeSheet, a.row, a.column]).toString()) ?? ""
    }

    /// What a cell computes to.
    public func value(at a: SigmaAddress, sheet: Int? = nil) -> SigmaValue {
        guard let v = try? engine.call("value", [handle, sheet ?? activeSheet, a.row, a.column]).toObject() else { return .empty }
        return SigmaValue(v)
    }

    public func note(at a: SigmaAddress, sheet: Int? = nil) -> String {
        (try? engine.call("note", [handle, sheet ?? activeSheet, a.row, a.column]).toString()) ?? ""
    }

    public func style(at a: SigmaAddress, sheet: Int? = nil) -> SigmaStyle {
        (try? decodeEngine(SigmaStyle.self, "style", [sheet ?? activeSheet, a.row, a.column])) ?? SigmaStyle()
    }

    // MARK: Changing

    /// Types into a cell: a number, text, or a formula starting with "=".
    public func set(_ input: String, at a: SigmaAddress, sheet: Int? = nil) throws {
        try invoke("setCell", [sheet ?? activeSheet, a.row, a.column, input])
    }

    /// Types into several cells as one undo step.
    public func set(_ inputs: [SigmaAddress: String], sheet: Int? = nil) throws {
        let updates = inputs.map { ["r": $0.key.row, "c": $0.key.column, "raw": $0.value] as [String: Any] }
        try invoke("setCells", [sheet ?? activeSheet, updates])
    }

    public func applyStyle(_ style: SigmaStyle, from a: SigmaAddress, to b: SigmaAddress, sheet: Int? = nil) throws {
        try invoke("applyStyle", [sheet ?? activeSheet, min(a.row, b.row), min(a.column, b.column), max(a.row, b.row), max(a.column, b.column), style.patch])
    }

    public func clear(from a: SigmaAddress, to b: SigmaAddress, sheet: Int? = nil) throws {
        try invoke("clearRange", [sheet ?? activeSheet, min(a.row, b.row), min(a.column, b.column), max(a.row, b.row), max(a.column, b.column)])
    }

    public func insertRows(at row: Int, count: Int = 1, sheet: Int? = nil) throws { try invoke("insertRows", [sheet ?? activeSheet, row, count]) }
    public func deleteRows(at row: Int, count: Int = 1, sheet: Int? = nil) throws { try invoke("deleteRows", [sheet ?? activeSheet, row, count]) }
    public func insertColumns(at column: Int, count: Int = 1, sheet: Int? = nil) throws { try invoke("insertCols", [sheet ?? activeSheet, column, count]) }
    public func deleteColumns(at column: Int, count: Int = 1, sheet: Int? = nil) throws { try invoke("deleteCols", [sheet ?? activeSheet, column, count]) }

    public func freeze(rows: Int, columns: Int, sheet: Int? = nil) throws { try invoke("setFreeze", [sheet ?? activeSheet, rows, columns]) }

    public func setWidth(_ width: Double?, ofColumn c: Int, sheet: Int? = nil) throws {
        _ = try engine.call("setColWidth", [handle, sheet ?? activeSheet, c, width as Any? ?? NSNull()])
        changed()
    }

    public func setHeight(_ height: Double?, ofRow r: Int, sheet: Int? = nil) throws {
        _ = try engine.call("setRowHeight", [handle, sheet ?? activeSheet, r, height as Any? ?? NSNull()])
        changed()
    }

    // MARK: Formatting, notes, sort, find

    public enum Borders: String, CaseIterable, Sendable {
        case all, outer, top, bottom, left, right, clear
    }

    public func applyBorders(_ kind: Borders, from a: SigmaAddress, to b: SigmaAddress, sheet: Int? = nil) throws {
        try invoke("applyBorders", [sheet ?? activeSheet, min(a.row, b.row), min(a.column, b.column), max(a.row, b.row), max(a.column, b.column), kind.rawValue])
    }

    /// Applies Sigma's own style keys; a value of `false` or `""` removes that key.
    func applyStylePatch(_ patch: [String: Any], to s: SigmaSelection, sheet: Int? = nil) throws {
        try invoke("applyStyle", [sheet ?? activeSheet, s.top, s.left, s.bottom, s.right, patch])
    }

    /// Sets a cell's note; an empty string removes it.
    public func setNote(_ text: String, at a: SigmaAddress, sheet: Int? = nil) throws {
        try invoke("setNote", [sheet ?? activeSheet, a.row, a.column, text])
    }

    /// Sorts the rows of a block by one of its columns. A single cell sorts the
    /// block of data around it, leaving a header row in place, as the web editor
    /// does. Returns the rows sorted.
    @discardableResult
    public func sort(_ s: SigmaSelection, byColumn column: Int, ascending: Bool, sheet: Int? = nil) throws -> SigmaSelection {
        let sh = sheet ?? activeSheet
        var block = s
        if s.isSingle {
            struct Region: Decodable { let r1: Int; let c1: Int; let r2: Int; let c2: Int; let header: Bool }
            let r = try engine.decode(Region.self, "region", [handle, sh, s.active.row, s.active.column])
            block = SigmaSelection(active: SigmaAddress(row: r.header ? r.r1 + 1 : r.r1, column: r.c1), corner: SigmaAddress(row: r.r2, column: r.c2))
        }
        try invoke("sortRange", [sh, block.top, block.left, block.bottom, block.right, column, ascending])
        return block
    }

    /// The block of data around a cell, header row included (what a chart of it should read).
    public func dataBlock(around a: SigmaAddress, sheet: Int? = nil) -> SigmaSelection? {
        struct Region: Decodable { let r1: Int; let c1: Int; let r2: Int; let c2: Int }
        guard let r = try? engine.decode(Region.self, "region", [handle, sheet ?? activeSheet, a.row, a.column]) else { return nil }
        return SigmaSelection(active: SigmaAddress(row: r.r1, column: r.c1), corner: SigmaAddress(row: r.r2, column: r.c2))
    }

    /// Cells whose input or shown text contains `query`, row by row.
    public func find(_ query: String, matchCase: Bool = false, sheet: Int? = nil) -> [SigmaAddress] {
        struct Hit: Decodable { let r: Int; let c: Int }
        let hits = (try? engine.decode([Hit].self, "call", [handle, "findAll", [sheet ?? activeSheet, query, matchCase]])) ?? []
        return hits.map { SigmaAddress(row: $0.r, column: $0.c) }
    }

    /// Replaces `query` in every cell's input, as one undo step. Returns how many cells changed.
    @discardableResult
    public func replaceAll(_ query: String, with replacement: String, matchCase: Bool = false, sheet: Int? = nil) throws -> Int {
        let n = Int(try engine.call("call", [handle, "replaceAll", [sheet ?? activeSheet, query, replacement, matchCase]]).toInt32())
        if n > 0 { changed() }
        return n
    }

    public func conditionalRules(sheet: Int? = nil) -> [SigmaConditionalRule] {
        (try? engine.decode([SigmaConditionalRule].self, "cfRules", [handle, sheet ?? activeSheet])) ?? []
    }

    public func addConditionalRule(_ rule: SigmaConditionalRule, sheet: Int? = nil) throws {
        let data = try JSONEncoder().encode(rule)
        let object = try JSONSerialization.jsonObject(with: data)
        try invoke("addCfRule", [sheet ?? activeSheet, object])
    }

    public func removeConditionalRule(at index: Int, sheet: Int? = nil) throws {
        try invoke("removeCfRule", [sheet ?? activeSheet, index])
    }

    // MARK: Clipboard and fill

    /// A copied block: tab-separated text for other apps, and Sigma's own
    /// copy, so pasting inside the workbook shifts formulas like the web does.
    public struct Clip {
        public let text: String
        /// Cut cells are cleared when cut, as on the web, and pasted without shifting formulas.
        public let isCut: Bool
        let payload: Any
        let sheet: Int
    }

    public func copy(_ s: SigmaSelection, sheet: Int? = nil) throws -> Clip {
        try clip(s, sheet: sheet ?? activeSheet, cut: false)
    }

    /// Copies and clears, as one undo step for the clear.
    public func cut(_ s: SigmaSelection, sheet: Int? = nil) throws -> Clip {
        let c = try clip(s, sheet: sheet ?? activeSheet, cut: true)
        try clear(from: s.topLeft, to: s.bottomRight, sheet: c.sheet)
        return c
    }

    private func clip(_ s: SigmaSelection, sheet sh: Int, cut: Bool) throws -> Clip {
        let out = try engine.call("call", [handle, "copyRange", [sh, s.top, s.left, s.bottom, s.right]])
        let text = out.objectForKeyedSubscript("tsv")?.toString() ?? ""
        let payload = out.objectForKeyedSubscript("internal")?.toObject() ?? NSNull()
        return Clip(text: text, isCut: cut, payload: payload, sheet: sh)
    }

    /// Pastes at a cell. With the clip that produced `text` (copied here), formulas
    /// shift as on the web; otherwise `text` is read as tab-separated values.
    /// Returns how many rows and columns landed.
    @discardableResult
    public func paste(_ text: String, clip: Clip? = nil, at a: SigmaAddress, sheet: Int? = nil) throws -> (rows: Int, columns: Int) {
        let sh = sheet ?? activeSheet
        let out: JSValue
        if let clip, clip.text == text {
            out = try engine.call("call", [handle, "pasteInternal", [sh, a.row, a.column, clip.payload, clip.isCut && clip.sheet == sh]])
        } else {
            out = try engine.call("call", [handle, "pasteTSV", [sh, a.row, a.column, text]])
        }
        changed()
        return (Int(out.objectForKeyedSubscript("rows")?.toInt32() ?? 0), Int(out.objectForKeyedSubscript("cols")?.toInt32() ?? 0))
    }

    /// Fills `target` (which contains `source`) from the block at its start:
    /// series continue (1, 2, 3…) and formulas shift.
    public func fill(from source: SigmaSelection, to target: SigmaSelection, sheet: Int? = nil) throws {
        // Sigma fills the cells beyond the source, in one direction.
        let dst: [String: Int]
        if target.bottom > source.bottom {
            dst = ["r1": source.bottom + 1, "c1": source.left, "r2": target.bottom, "c2": source.right]
        } else if target.right > source.right {
            dst = ["r1": source.top, "c1": source.right + 1, "r2": source.bottom, "c2": target.right]
        } else if target.top < source.top {
            dst = ["r1": target.top, "c1": source.left, "r2": source.top - 1, "c2": source.right]
        } else if target.left < source.left {
            dst = ["r1": source.top, "c1": target.left, "r2": source.bottom, "c2": source.left - 1]
        } else {
            return
        }
        let src: [String: Int] = ["r1": source.top, "c1": source.left, "r2": source.bottom, "c2": source.right]
        try invoke("fill", [sheet ?? activeSheet, src, dst])
    }

    @discardableResult
    public func undo() -> Bool { (try? invokeBool("undo", [])) ?? false }

    @discardableResult
    public func redo() -> Bool { (try? invokeBool("redo", [])) ?? false }

    // MARK: Sheets

    public func selectSheet(_ index: Int) {
        guard sheets.indices.contains(index) else { return }
        _ = try? engine.call("setActive", [handle, index])
        activeSheet = index
    }

    @discardableResult
    public func addSheet() throws -> Int {
        let i = Int(try engine.call("call", [handle, "addSheet", [Any]()]).toInt32())
        changed()
        selectSheet(i)
        return i
    }

    public func renameSheet(_ index: Int, to name: String) throws {
        guard try engine.call("call", [handle, "renameSheet", [index, name]]).toBool() else {
            throw SigmaError.editor("A sheet name must be unique and cannot contain ! or '.")
        }
        changed()
    }

    public func deleteSheet(_ index: Int) throws {
        guard try engine.call("call", [handle, "deleteSheet", [index]]).toBool() else {
            throw SigmaError.editor("A workbook needs at least one sheet.")
        }
        changed()
        selectSheet(min(index, sheets.count - 1))
    }

    // MARK: Saving

    /// Sigma's own JSON: every sheet, formula, style and chart.
    public func serialize() -> String {
        (try? engine.call("serialize", [handle]).toString()) ?? ""
    }

    /// The workbook as a file: .xlsx (every sheet), or one sheet as CSV.
    public func export(_ format: SigmaFormat, sheet: Int = 0) async throws -> Data {
        let b64 = try await engine.callAsync("exportFile", [handle, format.rawValue, sheet]).toString() ?? ""
        guard let data = Data(base64Encoded: b64) else { throw SigmaError.engine("The export could not be read.") }
        return data
    }

    // MARK: Internals

    private func invoke(_ method: String, _ args: [Any]) throws {
        _ = try engine.call("call", [handle, method, args])
        changed()
    }

    private func invokeBool(_ method: String, _ args: [Any]) throws -> Bool {
        let did = try engine.call("call", [handle, method, args]).toBool()
        if did { changed() }
        return did
    }

    private func decodeEngine<T: Decodable>(_ type: T.Type, _ method: String, _ args: [Any]) throws -> T {
        try engine.decode(T.self, "call", [handle, method, args])
    }

    private func refreshInfo() {
        struct Info: Decodable { let active: Int; let sheets: [SigmaSheetInfo] }
        guard let info = try? engine.decode(Info.self, "info", [handle]) else { return }
        if sheets != info.sheets { sheets = info.sheets }
        let active = min(info.active, max(0, info.sheets.count - 1))
        if activeSheet != active { activeSheet = active }
    }

    /// For extensions in other files: a change was made through the engine directly.
    func changedExternally() { changed() }

    func invokeAny(_ method: String, _ args: [Any]) throws { try invoke(method, args) }

    private func changed() {
        refreshInfo()
        revision += 1
        onChange?()
    }
}
