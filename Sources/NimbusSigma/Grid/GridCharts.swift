#if canImport(UIKit)
import SwiftUI
import UIKit

/// A chart on the grid: the card as a picture (redrawn only when the chart
/// or its data change), a selection outline, and a knob to resize it.
final class ChartHost: UIView {
    let id: String
    private let image = UIImageView()
    private let knob = HandleKnob()
    private var drawn: (chart: SigmaChart, data: SigmaChartData)?
    var onTap: ((ChartHost) -> Void)?
    var onMove: ((ChartHost, CGPoint, Bool) -> Void)?
    var onResize: ((ChartHost, CGSize, Bool) -> Void)?
    private var startFrame = CGRect.zero

    var selected = false {
        didSet {
            layer.borderWidth = selected ? 2 : 0
            knob.isHidden = !selected
        }
    }

    init(id: String) {
        self.id = id
        super.init(frame: .zero)
        layer.borderColor = GridColors.accent.cgColor
        layer.cornerRadius = 10
        image.contentMode = .scaleToFill
        addSubview(image)
        knob.isHidden = true
        addSubview(knob)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(moved(_:))))
        knob.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(resized(_:))))
        isAccessibilityElement = true
        accessibilityTraits = .image
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ chart: SigmaChart, _ data: SigmaChartData) {
        accessibilityLabel = "\(chart.kind.label) chart" + (chart.title.map { ", \($0)" } ?? "")
        guard drawn?.chart != chart || drawn?.data != data else { return }
        drawn = (chart, data)
        let card = SigmaChartCard(chart: chart, data: data).frame(width: chart.width, height: chart.height)
        let renderer = ImageRenderer(content: card)
        renderer.scale = window?.screen.scale ?? UIScreen.main.scale
        image.image = renderer.uiImage
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        image.frame = bounds
        knob.center = CGPoint(x: bounds.maxX, y: bounds.maxY)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        super.point(inside: point, with: event) || (!knob.isHidden && knob.frame.contains(point))
    }

    @objc private func tapped() { onTap?(self) }

    @objc private func moved(_ g: UIPanGestureRecognizer) {
        guard selected else { return }
        if g.state == .began { startFrame = frame }
        let t = g.translation(in: superview)
        onMove?(self, CGPoint(x: startFrame.minX + t.x, y: startFrame.minY + t.y), g.state == .ended || g.state == .cancelled)
    }

    @objc private func resized(_ g: UIPanGestureRecognizer) {
        if g.state == .began { startFrame = frame }
        let t = g.translation(in: superview)
        onResize?(self, CGSize(width: max(200, startFrame.width + t.x), height: max(140, startFrame.height + t.y)), g.state == .ended || g.state == .cancelled)
    }

    /// Only a selected chart takes drags; otherwise the sheet scrolls under the finger.
    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        if g is UIPanGestureRecognizer, g.view === self { return selected }
        return super.gestureRecognizerShouldBegin(g)
    }
}

extension SigmaGridView {
    /// Places the sheet's charts in the scrolling body, by their anchor cells.
    func layoutCharts() {
        guard let book = workbook else { return }
        let key = (book.revision, book.activeSheet)
        if chartKey == nil || chartKey! != key {
            chartKey = key
            chartModels = book.charts()
        }
        var seen = Set<String>()
        for (chart, data) in chartModels {
            seen.insert(chart.id)
            let host = chartHosts[chart.id] ?? {
                let h = ChartHost(id: chart.id)
                h.onTap = { [weak self] host in self?.selectChart(host.id) }
                h.onMove = { [weak self] host, origin, done in self?.moveChart(host, to: origin, done: done) }
                h.onResize = { [weak self] host, size, done in self?.resizeChart(host, to: size, done: done) }
                chartHosts[chart.id] = h
                return h
            }()
            if host.superview !== bodyPane { bodyPane.addSubview(host) }
            bodyPane.bringSubviewToFront(host)
            if draggingChart != chart.id {
                let origin = geometry.rect(row: min(chart.row, geometry.rows - 1), column: min(chart.column, geometry.columns - 1)).origin
                host.frame = CGRect(origin: origin, size: CGSize(width: chart.width * zoom, height: chart.height * zoom))
            }
            host.show(chart, data)
            host.selected = controller.selectedChart == chart.id
        }
        for (id, host) in chartHosts where !seen.contains(id) {
            host.removeFromSuperview()
            chartHosts[id] = nil
        }
        if let id = controller.selectedChart, !seen.contains(id) { controller.selectedChart = nil }
    }

    func selectChart(_ id: String?) {
        if editingCell { commitEditing(move: .none) }
        controller.selectedChart = id
        setNeedsLayout()
        if let id, let host = chartHosts[id] {
            showMenu(at: convert(CGPoint(x: host.bounds.midX, y: host.bounds.minY), from: host))
        }
    }

    private func moveChart(_ host: ChartHost, to origin: CGPoint, done: Bool) {
        guard let book = workbook, var chart = chartModels.first(where: { $0.chart.id == host.id })?.chart else { return }
        // The chart follows the finger, then settles on the cell under its corner.
        let r = geometry.row(atY: max(0, origin.y)), c = geometry.column(atX: max(0, origin.x))
        if !done {
            draggingChart = host.id
            host.frame.origin = origin
            return
        }
        draggingChart = nil
        chart.row = r
        chart.column = c
        try? book.updateChart(chart)
        setNeedsLayout()
    }

    private func resizeChart(_ host: ChartHost, to size: CGSize, done: Bool) {
        guard let book = workbook, var chart = chartModels.first(where: { $0.chart.id == host.id })?.chart else { return }
        if !done {
            draggingChart = host.id
            host.frame.size = size
            return
        }
        draggingChart = nil
        chart.width = Double((size.width / zoom).rounded())
        chart.height = Double((size.height / zoom).rounded())
        try? book.updateChart(chart)
        setNeedsLayout()
    }
}
#endif
