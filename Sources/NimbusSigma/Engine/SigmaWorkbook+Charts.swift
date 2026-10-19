import Foundation

/// A chart floating over a sheet. It holds a reference to its data, never a
/// copy: change a cell and the chart redraws.
public struct SigmaChart: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case column, bar, line, area, pie, doughnut, scatter

        public var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

        public var symbol: String {
            switch self {
            case .column: return "chart.bar"
            case .bar: return "chart.bar.xaxis"
            case .line: return "chart.xyaxis.line"
            case .area: return "chart.line.uptrend.xyaxis"
            case .pie: return "chart.pie"
            case .doughnut: return "circle.circle"
            case .scatter: return "chart.dots.scatter"
            }
        }

        public var canStack: Bool { self == .column || self == .bar || self == .area }
    }

    public var id: String
    public var kind: Kind
    public var title: String?
    /// The source block, in A1 notation ("A1:C13", or "Sheet2!A1:B9").
    public var data: String
    /// The anchor cell: the chart's top-left corner sits on it.
    public var row: Int
    public var column: Int
    /// Points (pixels on the web; the same numbers).
    public var width: Double
    public var height: Double
    public var stacked: Bool?
    public var headerRow: Bool?
    public var headerColumn: Bool?
    /// The one series that carries the story; the rest go grey.
    public var emphasis: Int?

    enum CodingKeys: String, CodingKey {
        case id, kind = "type", title, data, row = "r", column = "c", width = "w", height = "h", stacked
        case headerRow, headerColumn = "headerCol", emphasis
    }
}

/// What a chart shows: its categories and its series of numbers.
public struct SigmaChartData: Decodable, Hashable, Sendable {
    public struct Series: Decodable, Hashable, Sendable {
        public let name: String
        /// nil where a cell holds no number.
        public let values: [Double?]
        /// "#rrggbb", from Sigma's palette.
        public let color: String
    }

    public let labels: [String]
    public let series: [Series]
    /// Series beyond the most a chart shows.
    public let omitted: Int
    public let error: String?
}

/// What applying a Vani AI patch changed.
public struct SigmaPatchResult: Decodable, Hashable, Sendable {
    public let cells: Int
    public let styles: Int
    public let charts: Int
    public let skipped: Int
    /// "Applied 12 cells, 3 formats".
    public let summary: String
}

extension SigmaWorkbook {
    /// The sheet's charts, each with the data it currently shows.
    public func charts(sheet: Int? = nil) -> [(chart: SigmaChart, data: SigmaChartData)] {
        struct Entry: Decodable { let chart: SigmaChart; let data: SigmaChartData }
        let entries = (try? engine.decode([Entry].self, "charts", [handle, sheet ?? activeSheet])) ?? []
        return entries.map { ($0.chart, $0.data) }
    }

    /// Adds a chart of a block of cells, beside the data unless told where.
    @discardableResult
    public func addChart(_ kind: SigmaChart.Kind = .column, data: String, title: String? = nil,
                         at anchor: SigmaAddress? = nil, sheet: Int? = nil) throws -> SigmaChart {
        let sh = sheet ?? activeSheet
        var place = anchor
        if place == nil {
            struct Anchor: Decodable { let r: Int; let c: Int }
            let a = try engine.decode(Anchor.self, "anchor", [handle, sh])
            place = SigmaAddress(row: a.r, column: a.c)
        }
        var spec: [String: Any] = ["type": kind.rawValue, "data": data, "r": place!.row, "c": place!.column, "w": 460, "h": 280]
        if let title, !title.isEmpty { spec["title"] = title }
        let made = try engine.decode(SigmaChart.self, "call", [handle, "addChart", [sh, spec]])
        changedExternally()
        return made
    }

    /// Saves a chart's new type, title, data, place or size.
    public func updateChart(_ chart: SigmaChart, sheet: Int? = nil) throws {
        let data = try JSONEncoder().encode(chart)
        var patch = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        patch["id"] = nil
        // A cleared title or stack setting has to reach the engine as a removal.
        if chart.title == nil { patch["title"] = NSNull() }
        if chart.stacked == nil { patch["stacked"] = false }
        try invokeAny("updateChart", [sheet ?? activeSheet, chart.id, patch])
    }

    public func removeChart(id: String, sheet: Int? = nil) throws {
        try invokeAny("removeChart", [sheet ?? activeSheet, id])
    }

    // MARK: Vani AI

    /// What Vani AI is told about a sheet: its populated area as tab-separated
    /// text with A1 headers, formulas shown as formulas.
    func aiContext(sheet: Int? = nil) -> (grid: String, used: String) {
        struct Context: Decodable { let grid: String; let used: String }
        let c = try? engine.decode(Context.self, "context", [handle, sheet ?? activeSheet])
        return (c?.grid ?? "", c?.used ?? "")
    }

    /// "12 cells · 3 formats · 1 chart".
    func describePatch(_ json: String) -> String {
        (try? engine.call("describeOps", [json]).toString()) ?? ""
    }

    /// Applies a Vani AI patch as one undo step.
    @discardableResult
    public func applyPatch(_ json: String, sheet: Int? = nil) throws -> SigmaPatchResult {
        let result = try engine.decode(SigmaPatchResult.self, "applyOps", [handle, sheet ?? activeSheet, json])
        changedExternally()
        return result
    }
}
