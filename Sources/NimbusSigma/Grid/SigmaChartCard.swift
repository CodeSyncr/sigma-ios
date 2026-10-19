#if canImport(UIKit)
import SwiftUI
import Charts

/// One chart, drawn natively: a card with its title, the plot and a legend.
/// Series colours are Sigma's own, so a chart looks the same on the web.
struct SigmaChartCard: View {
    let chart: SigmaChart
    let data: SigmaChartData

    private struct Point: Identifiable {
        let id: Int
        let label: String
        let index: Int
        let series: String
        let value: Double
    }

    private var points: [Point] {
        var out: [Point] = []
        for s in data.series {
            for (i, v) in s.values.enumerated() {
                guard let v, i < data.labels.count else { continue }
                out.append(Point(id: out.count, label: data.labels[i], index: i, series: s.name, value: v))
            }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let t = chart.title, !t.isEmpty {
                Text(t).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(GridColors.ink)).lineLimit(1)
            }
            if let error = data.error ?? (data.series.isEmpty ? "No numbers in \(chart.data)" : nil) {
                Spacer()
                Label(error, systemImage: "chart.bar.xaxis").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else if chart.kind == .pie || chart.kind == .doughnut {
                PieChart(labels: data.labels, values: data.series[0].values, hole: chart.kind == .doughnut)
            } else {
                plot
                    .chartForegroundStyleScale(domain: data.series.map(\.name), range: data.series.map { seriesColor($0) })
                    .chartLegend(data.series.count > 1 ? .visible : .hidden)
            }
        }
        // The card fills its chart's size whatever the plot inside would take on its own.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(GridColors.gridline), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .environment(\.colorScheme, .light)
    }

    private func seriesColor(_ s: SigmaChartData.Series) -> Color {
        if let e = chart.emphasis, data.series.indices.contains(e), data.series[e].name != s.name { return Color(white: 0.75) }
        return Palette.color(s.color) ?? .accentColor
    }

    @ChartContentBuilder
    private func marks(_ p: Point) -> some ChartContent {
        switch chart.kind {
        case .bar:
            if chart.stacked == true {
                BarMark(x: .value("Value", p.value), y: .value("Category", p.label))
                    .foregroundStyle(by: .value("Series", p.series))
            } else {
                BarMark(x: .value("Value", p.value), y: .value("Category", p.label))
                    .foregroundStyle(by: .value("Series", p.series))
                    .position(by: .value("Series", p.series))
            }
        case .line:
            LineMark(x: .value("Category", p.label), y: .value("Value", p.value))
                .foregroundStyle(by: .value("Series", p.series))
                .interpolationMethod(.monotone)
            PointMark(x: .value("Category", p.label), y: .value("Value", p.value))
                .foregroundStyle(by: .value("Series", p.series))
                .symbolSize(18)
        case .area:
            AreaMark(x: .value("Category", p.label), y: .value("Value", p.value), stacking: chart.stacked == true ? .standard : .unstacked)
                .foregroundStyle(by: .value("Series", p.series))
                .opacity(chart.stacked == true ? 0.85 : 0.45)
        case .scatter:
            PointMark(x: .value("X", Double(p.label) ?? Double(p.index + 1)), y: .value("Value", p.value))
                .foregroundStyle(by: .value("Series", p.series))
        default:
            if chart.stacked == true {
                BarMark(x: .value("Category", p.label), y: .value("Value", p.value))
                    .foregroundStyle(by: .value("Series", p.series))
            } else {
                BarMark(x: .value("Category", p.label), y: .value("Value", p.value))
                    .foregroundStyle(by: .value("Series", p.series))
                    .position(by: .value("Series", p.series))
            }
        }
    }

    private var plot: some View {
        Chart(points) { p in marks(p) }
            .chartXAxis { AxisMarks { _ in AxisValueLabel().font(.system(size: 10)) } }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color(GridColors.gridline))
                    AxisValueLabel().font(.system(size: 10))
                }
            }
    }
}

/// Pie and doughnut, drawn by hand: Swift Charts' sector mark needs iOS 17.
struct PieChart: View {
    let labels: [String]
    let values: [Double?]
    let hole: Bool

    private var slices: [(label: String, value: Double, color: Color)] {
        let palette = Palette.rows[1] + Palette.rows[3]
        return zip(labels, values).enumerated().compactMap { i, pair in
            guard let v = pair.1, v > 0 else { return nil }
            return (pair.0, v, Palette.color(palette[i % palette.count]) ?? .gray)
        }
    }

    var body: some View {
        let s = slices
        let total = s.reduce(0) { $0 + $1.value }
        HStack(spacing: 12) {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                ZStack {
                    ForEach(Array(s.enumerated()), id: \.offset) { i, slice in
                        let start = s[..<i].reduce(0) { $0 + $1.value } / total
                        let end = start + slice.value / total
                        Path { p in
                            p.move(to: center)
                            p.addArc(center: center, radius: size / 2, startAngle: .degrees(start * 360 - 90), endAngle: .degrees(end * 360 - 90), clockwise: false)
                            p.closeSubpath()
                        }
                        .fill(slice.color)
                        .overlay(Path { p in
                            p.move(to: center)
                            p.addArc(center: center, radius: size / 2, startAngle: .degrees(start * 360 - 90), endAngle: .degrees(end * 360 - 90), clockwise: false)
                            p.closeSubpath()
                        }.stroke(Color.white, lineWidth: 2))
                    }
                    if hole { Circle().fill(Color.white).frame(width: size * 0.55, height: size * 0.55) }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(s.prefix(8).enumerated()), id: \.offset) { _, slice in
                    HStack(spacing: 6) {
                        Circle().fill(slice.color).frame(width: 8, height: 8)
                        Text(slice.label).font(.system(size: 11)).lineLimit(1)
                        Text(String(format: "%.0f%%", slice.value / total * 100)).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
#endif
