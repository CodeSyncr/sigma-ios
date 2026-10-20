#if canImport(UIKit)
import UIKit
import Combine

/// Selection, editing and the formula bar's text, shared by the grid and the
/// SwiftUI around it. ``SigmaSheetView`` makes one; use it to drive the grid
/// from your own controls.
@MainActor
public final class SigmaGridController: ObservableObject {
    @Published public internal(set) var selection = SigmaSelection(SigmaAddress(row: 0, column: 0))
    @Published public internal(set) var isEditing = false
    /// What the cell being edited holds, as typed. The formula bar binds to it.
    @Published public internal(set) var editText = ""
    /// What the active cell holds when nothing is being edited.
    @Published public internal(set) var activeInput = ""
    @Published public internal(set) var readOnly = false
    /// The active cell's style and note, for the format bar.
    @Published public internal(set) var activeStyle = SigmaStyle()
    @Published public internal(set) var activeNote = ""

    /// A panel the sheet view shows over the grid.
    public enum Panel: String, Identifiable, Sendable {
        case find, conditionalFormatting, note, chart, ai, functions
        public var id: String { rawValue }
    }
    @Published public var panel: Panel?
    /// The chart tapped on, if one is.
    @Published public internal(set) var selectedChart: String?
    /// Whether Vani AI is offered (the document's owner has it).
    @Published public internal(set) var aiAvailable = false
    /// The conversation with Vani AI, kept while the sheet is open.
    @Published public var aiMessages: [SigmaAIMessage] = []

    /// Charts the selection: a single cell charts the block of data around it.
    public func insertChart(_ kind: SigmaChart.Kind = .column) {
        guard let book = workbook, !readOnly else { return }
        grid?.commitIfEditing()
        var range = selection
        if selection.isSingle, let block = book.dataBlock(around: selection.active) { range = block }
        if let chart = try? book.addChart(kind, data: range.description) {
            grid?.selectChart(chart.id)
            panel = .chart
        }
    }

    weak var grid: SigmaGridView?
    var workbook: SigmaWorkbook? { grid?.workbook }

    public init() {}

    // MARK: Formatting the selection

    public func toggleBold() { patch(["b": !(activeStyle.bold ?? false)]) }
    public func toggleItalic() { patch(["i": !(activeStyle.italic ?? false)]) }
    public func toggleUnderline() { patch(["u": !(activeStyle.underline ?? false)]) }
    public func toggleStrikethrough() { patch(["st": !(activeStyle.strikethrough ?? false)]) }
    /// nil returns text to its usual colour.
    public func setTextColor(_ hex: String?) { patch(["tc": hex ?? ""]) }
    /// nil removes the fill.
    public func setFill(_ hex: String?) { patch(["bg": hex ?? ""]) }
    /// nil aligns numbers right and text left, as by default.
    public func setAlign(_ align: SigmaStyle.Align?) { patch(["al": align?.rawValue ?? ""]) }
    public func setNumberFormat(_ format: SigmaStyle.NumberFormat) { patch(["nf": format == .auto ? "" : format.rawValue]) }
    /// Shows one more (+1) or one fewer (-1) decimal place.
    public func stepDecimals(_ by: Int) { patch(["dp": max(0, min(10, (activeStyle.decimals ?? 2) + by))]) }
    /// Sets the text size; 13, the default, removes the setting.
    public func setFontSize(_ size: Double) {
        let s = min(96, max(6, size))
        patch(["fs": s == Double(gridFontSize) ? "" : s])
    }
    public func setBorders(_ kind: SigmaWorkbook.Borders) {
        guard let book = workbook, !readOnly else { return }
        finishEdit()
        try? book.applyBorders(kind, from: selection.topLeft, to: selection.bottomRight)
    }

    /// Removes every style from the selection: fonts, colours, alignment, number formats and borders.
    public func clearFormatting() {
        var p: [String: Any] = [:]
        for k in ["b", "i", "u", "st", "al", "fs", "tc", "bg", "nf", "dp", "bT", "bB", "bL", "bR"] { p[k] = "" }
        patch(p)
    }

    /// Sums the numbers just above the active cell into it, or starts a SUM to finish.
    public func autoSum() {
        guard let book = workbook, !readOnly else { return }
        finishEdit()
        let a = selection.active
        var top = a.row - 1
        while top >= 0 {
            if case .number = book.value(at: SigmaAddress(row: top, column: a.column)) { top -= 1 } else { break }
        }
        top += 1
        if top < a.row {
            try? book.set("=SUM(\(SigmaAddress(row: top, column: a.column)):\(SigmaAddress(row: a.row - 1, column: a.column)))", at: a)
            grid?.refreshAfterCommand()
        } else {
            grid?.beginEditing(initial: "=SUM(")
        }
    }

    /// Puts a function into the formula being typed, or starts one in the active cell.
    public func insertFunction(_ name: String) {
        guard !readOnly else { return }
        if isEditing {
            let text = editText
            let partial = FormulaHint.trailingName(text, standalone: true) ?? ""
            grid?.setEditorText(String(text.dropLast(partial.count)) + name + "(")
            grid?.focusEditorSoon()
        } else {
            grid?.beginEditing(initial: "=\(name)(")
        }
    }

    /// Freezes rows above and columns left of a point; (0, 0) unfreezes.
    public func freeze(rows: Int, columns: Int) {
        guard let book = workbook, !readOnly else { return }
        finishEdit()
        try? book.freeze(rows: rows, columns: columns)
    }

    /// Saves an edit in progress without moving, so formatting lands on the cell being edited.
    private func finishEdit() { if isEditing { grid?.commitEditing(move: .none) } }

    private func patch(_ p: [String: Any]) {
        guard let book = workbook, !readOnly else { return }
        finishEdit()
        try? book.applyStylePatch(p, to: selection)
    }

    // MARK: Sorting and notes

    /// Sorts by the active cell's column; a single cell sorts the block of data around it.
    public func sort(ascending: Bool) {
        guard let book = workbook, !readOnly else { return }
        finishEdit()
        if let block = try? book.sort(selection, byColumn: selection.active.column, ascending: ascending) {
            grid?.select(SigmaSelection(active: block.topLeft, corner: block.bottomRight), scroll: false)
        }
    }

    /// Sets the active cell's note; an empty string removes it.
    public func setNote(_ text: String) {
        guard let book = workbook, !readOnly else { return }
        try? book.setNote(text.trimmingCharacters(in: .whitespacesAndNewlines), at: selection.active)
    }

    public func select(_ s: SigmaSelection) { grid?.select(s, scroll: true) }
    /// Starts editing the active cell, from the formula bar or a key.
    public func beginEditing(with text: String? = nil) { grid?.beginEditing(initial: text) }
    /// The formula bar changed the text being edited.
    public func edit(_ text: String) { grid?.setEditorText(text) }
    /// The formula bar took focus: edit the active cell there, not in the cell.
    func formulaBarFocused() { if !isEditing { grid?.beginEditing(initial: nil, focus: false) } }
    public func commit() { grid?.commitEditing(move: .down) }
    public func cancel() { grid?.cancelEditing() }
    public func undo() { grid?.perform(.undo) }
    public func redo() { grid?.perform(.redo) }
}

/// The spreadsheet, drawn natively: cells, headers, frozen panes, selection,
/// editing. One reusable view per visible cell; nothing is drawn twice while
/// it stays on screen.
@MainActor
final class SigmaGridView: UIScrollView, UIScrollViewDelegate, UITextFieldDelegate, @preconcurrency UIEditMenuInteractionDelegate, UIGestureRecognizerDelegate {
    enum Move { case down, up, right, left, none }
    enum Action { case undo, redo, cut, copy, paste, pasteValues, clear, fill, fillDown, fillRight, insertRowAbove, insertRowBelow, deleteRows, insertColumnLeft, insertColumnRight, deleteColumns, edit, freezeHere, freezeOneRow, freezeTwoRows, freezeOneColumn, unfreeze, sortAscending, sortDescending, note, conditionalFormatting, find }

    let controller: SigmaGridController
    private(set) var workbook: SigmaWorkbook?
    private var watching = Set<AnyCancellable>()

    private(set) var geometry = GridGeometry(rows: 1, columns: 1, frozenRows: 0, frozenColumns: 0, columnWidth: { _ in 96 }, rowHeight: { _ in 26 })
    private var geometryKey: (revision: Int, sheet: Int)?
    /// Column widths being dragged, before they are saved.
    private var liveColumnWidth: (column: Int, width: CGFloat)?
    /// A row height being dragged, before it is saved.
    private var liveRowHeight: (row: Int, height: CGFloat)?
    /// Pinch zoom, 50% to 200%: cells, headers, text and charts scale with it.
    private(set) var zoom: CGFloat = 1
    /// Fill mode: the corner handle drags out a fill instead of the selection.
    private var filling = false
    private var fillTarget: SigmaSelection?

    // Panes: the scrolling body and the frozen top, left and corner.
    private let body = Pane(), top = Pane(), left = Pane(), corner = Pane()
    private let columnHeaders = HeaderPane(), frozenColumnHeaders = HeaderPane()
    private let rowHeaders = HeaderPane(), frozenRowHeaders = HeaderPane()
    private let cornerBox = UIView()
    private let frozenRowLine = UIView(), frozenColumnLine = UIView()
    private let overlay = HandleOverlay()
    private var cellPool: [GridCellView] = []
    private var headerPool: [GridHeaderView] = []

    // What the engine said each cell shows, for the block around the screen.
    private var cache: [Int: SigmaCell] = [:]
    private var cachedBlock: (rows: ClosedRange<Int>, columns: ClosedRange<Int>, revision: Int, sheet: Int)?

    // Charts over the body, by id; rebuilt from the engine when the workbook changes.
    var chartHosts: [String: ChartHost] = [:]
    var chartModels: [(chart: SigmaChart, data: SigmaChartData)] = []
    var chartKey: (Int, Int)?
    var draggingChart: String?
    var bodyPane: Pane { body }
    var editingCell: Bool { editing != nil }
    func commitIfEditing() { if editing != nil { commitEditing(move: .none) } }

    private let editor = CellEditor()
    private lazy var accessory = FormulaKeys(
        insert: { [weak self] text in self?.insertIntoEditor(text) },
        functions: { [weak self] in self?.controller.panel = .functions }
    )
    private var editing: SigmaAddress?
    private var clip: SigmaWorkbook.Clip?
    private lazy var editMenu = UIEditMenuInteraction(delegate: self)

    init(controller: SigmaGridController) {
        self.controller = controller
        super.init(frame: .zero)
        controller.grid = self
        backgroundColor = .white
        delegate = self
        showsHorizontalScrollIndicator = true
        isDirectionalLockEnabled = true
        alwaysBounceVertical = true
        keyboardDismissMode = .none
        contentInsetAdjustmentBehavior = .never
        scrollsToTop = true

        for p in [body, left, top, corner] { addSubview(p) }
        for p in [columnHeaders, frozenColumnHeaders, rowHeaders, frozenRowHeaders] { addSubview(p) }
        cornerBox.backgroundColor = GridColors.header
        addSubview(cornerBox)
        for line in [frozenRowLine, frozenColumnLine] {
            line.backgroundColor = GridColors.frozenLine
            line.isUserInteractionEnabled = false
            addSubview(line)
        }
        addSubview(overlay)
        overlay.onDrag = { [weak self] handle, point, ended in self?.dragHandle(handle, to: point, ended: ended) }

        editor.delegate = self
        editor.addTarget(self, action: #selector(editorChanged), for: .editingChanged)
        editor.onKey = { [weak self] move in self?.commitEditing(move: move) }
        editor.inputAccessoryView = accessory

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.delegate = self
        addGestureRecognizer(tap)
        let long = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        long.delegate = self
        addGestureRecognizer(long)
        let resize = UIPanGestureRecognizer(target: self, action: #selector(resizing(_:)))
        resize.delegate = self
        addGestureRecognizer(resize)
        panGestureRecognizer.require(toFail: resize)
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:))))
        addInteraction(editMenu)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Workbook

    func show(_ book: SigmaWorkbook, readOnly: Bool) {
        guard book !== workbook else { return }
        workbook = book
        controller.readOnly = readOnly
        watching = []
        book.$revision.dropFirst().sink { [weak self] _ in self?.workbookChanged() }.store(in: &watching)
        // Duplicates first: only a real switch of sheet resets the selection.
        book.$activeSheet.removeDuplicates().dropFirst().sink { [weak self] _ in
            self?.cancelEditing()
            self?.select(SigmaSelection(SigmaAddress(row: 0, column: 0)), scroll: false)
            self?.contentOffset = .zero
            self?.workbookChanged()
        }.store(in: &watching)
        workbookChanged()
    }

    private func workbookChanged() {
        cachedBlock = nil
        geometryKey = nil
        refreshActiveInput()
        setNeedsLayout()
    }

    private func refreshGeometry() {
        guard let book = workbook else { return }
        let key = (book.revision, book.activeSheet)
        if let k = geometryKey, k == key, liveColumnWidth == nil, liveRowHeight == nil { return }
        geometryKey = key
        let info = book.sheets.indices.contains(book.activeSheet) ? book.sheets[book.activeSheet] : nil
        let layout = book.layout()
        let live = liveColumnWidth
        let liveRow = liveRowHeight
        let z = zoom
        var g = GridGeometry(
            rows: info?.rows ?? 1000, columns: info?.columns ?? 104,
            frozenRows: info?.frozenRows ?? 0, frozenColumns: info?.frozenColumns ?? 0,
            columnWidth: { c in live?.column == c ? live!.width : CGFloat(layout?.width(ofColumn: c) ?? 96) * z },
            rowHeight: { r in liveRow?.row == r ? liveRow!.height : CGFloat(layout?.height(ofRow: r) ?? 26) * z }
        )
        g.rowHeaderWidth = 46 * z
        g.columnHeaderHeight = 28 * z
        geometry = g
        let size = geometry.contentSize
        if contentSize != size { contentSize = CGSize(width: size.width, height: size.height + 80) }
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard workbook != nil else { return }
        refreshGeometry()
        let g = geometry
        let off = contentOffset
        let hw = g.rowHeaderWidth, hh = g.columnHeaderHeight

        body.frame = CGRect(x: hw, y: hh, width: g.sheetWidth, height: g.sheetHeight)
        top.frame = CGRect(x: hw, y: off.y + hh, width: g.sheetWidth, height: g.frozenHeight)
        left.frame = CGRect(x: off.x + hw, y: hh, width: g.frozenWidth, height: g.sheetHeight)
        corner.frame = CGRect(x: off.x + hw, y: off.y + hh, width: g.frozenWidth, height: g.frozenHeight)
        columnHeaders.frame = CGRect(x: hw, y: off.y, width: g.sheetWidth, height: hh)
        frozenColumnHeaders.frame = CGRect(x: off.x + hw, y: off.y, width: g.frozenWidth, height: hh)
        rowHeaders.frame = CGRect(x: off.x, y: hh, width: hw, height: g.sheetHeight)
        frozenRowHeaders.frame = CGRect(x: off.x, y: off.y + hh, width: hw, height: g.frozenHeight)
        cornerBox.frame = CGRect(x: off.x, y: off.y, width: hw, height: hh)
        frozenRowLine.isHidden = g.frozenRows == 0
        frozenColumnLine.isHidden = g.frozenColumns == 0
        frozenRowLine.frame = CGRect(x: off.x, y: off.y + hh + g.frozenHeight - 1, width: bounds.width, height: 2)
        frozenColumnLine.frame = CGRect(x: off.x + hw + g.frozenWidth - 1, y: off.y, width: 2, height: bounds.height)
        overlay.frame = CGRect(origin: off, size: bounds.size)

        let v = g.visibleScrolling(offset: off, viewport: bounds.size)
        let frozenRows: ClosedRange<Int>? = g.frozenRows > 0 ? 0...(g.frozenRows - 1) : nil
        let frozenCols: ClosedRange<Int>? = g.frozenColumns > 0 ? 0...(g.frozenColumns - 1) : nil
        ensureData(rows: v.rows, columns: v.columns)

        render(body, rows: v.rows, columns: v.columns)
        render(top, rows: frozenRows, columns: v.columns)
        render(left, rows: v.rows, columns: frozenCols)
        render(corner, rows: frozenRows, columns: frozenCols)
        renderHeaders(columnHeaders, columns: v.columns)
        renderHeaders(frozenColumnHeaders, columns: frozenCols)
        renderHeaders(rowHeaders, rows: v.rows)
        renderHeaders(frozenRowHeaders, rows: frozenRows)
        placeSelection()
        layoutCharts()
    }

    /// UIKit scrolls a focused text field into view on its own, ignoring frozen
    /// panes and the headers; the grid already keeps the edited cell in view.
    override func scrollRectToVisible(_ rect: CGRect, animated: Bool) {}

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if editMenuShowing { editMenu.dismissMenu() }
    }

    /// Fetches what the cells around the screen show, in one call to the engine.
    private func ensureData(rows: ClosedRange<Int>, columns: ClosedRange<Int>) {
        guard let book = workbook else { return }
        if let b = cachedBlock, b.revision == book.revision, b.sheet == book.activeSheet,
           b.rows.contains(rows.lowerBound), b.rows.contains(rows.upperBound),
           b.columns.contains(columns.lowerBound), b.columns.contains(columns.upperBound) { return }
        let g = geometry
        let rr = max(0, rows.lowerBound - 30)...min(g.rows - 1, rows.upperBound + 60)
        let cc = max(0, columns.lowerBound - 6)...min(g.columns - 1, columns.upperBound + 10)
        var next: [Int: SigmaCell] = [:]
        func load(_ r: ClosedRange<Int>, _ c: ClosedRange<Int>) {
            for cell in book.cells(rows: r, columns: c) { next[key(cell.row, cell.column)] = cell }
        }
        load(rr, cc)
        if g.frozenRows > 0 { load(0...(g.frozenRows - 1), cc) }
        if g.frozenColumns > 0 { load(rr, 0...(g.frozenColumns - 1)) }
        if g.frozenRows > 0 && g.frozenColumns > 0 { load(0...(g.frozenRows - 1), 0...(g.frozenColumns - 1)) }
        cache = next
        cachedBlock = (rr, cc, book.revision, book.activeSheet)
    }

    private func key(_ r: Int, _ c: Int) -> Int { r * 16384 + c }

    private func render(_ pane: Pane, rows: ClosedRange<Int>?, columns: ClosedRange<Int>?) {
        guard let rows, let columns else {
            for (_, v) in pane.cells { v.removeFromSuperview(); cellPool.append(v) }
            pane.cells.removeAll()
            return
        }
        for (k, v) in pane.cells where !(rows.contains(k / 16384) && columns.contains(k % 16384)) {
            v.removeFromSuperview()
            cellPool.append(v)
            pane.cells[k] = nil
        }
        for r in rows {
            for c in columns {
                let k = key(r, c)
                let view: GridCellView
                if let existing = pane.cells[k] {
                    view = existing
                } else {
                    view = cellPool.popLast() ?? GridCellView(frame: .zero)
                    pane.insertSubview(view, at: 0)
                    pane.cells[k] = view
                }
                let frame = geometry.rect(row: r, column: c)
                if view.frame != frame { view.frame = frame }
                if let cell = cache[k] {
                    view.content = .init(text: cell.text, isNumber: cell.isNumber, isError: cell.isError, style: cell.style, hasNote: cell.hasNote, zoom: zoom)
                } else {
                    view.content = .init()
                }
            }
        }
    }

    private func renderHeaders(_ pane: HeaderPane, columns: ClosedRange<Int>? = nil, rows: ClosedRange<Int>? = nil) {
        let range = columns ?? rows
        for (k, v) in pane.views where !(range?.contains(k) ?? false) {
            v.removeFromSuperview()
            headerPool.append(v)
            pane.views[k] = nil
        }
        guard let range else { return }
        let sel = controller.selection
        for i in range {
            let view = pane.views[i] ?? {
                let v = headerPool.popLast() ?? GridHeaderView(frame: .zero)
                pane.addSubview(v)
                pane.views[i] = v
                return v
            }()
            view.zoom = zoom
            if columns != nil {
                view.frame = CGRect(x: geometry.rect(row: 0, column: i).minX, y: 0, width: geometry.width(ofColumn: i), height: geometry.columnHeaderHeight)
                view.title = SigmaAddress.columnName(i)
                view.highlighted = (sel.left...sel.right).contains(i)
            } else {
                view.frame = CGRect(x: 0, y: geometry.rect(row: i, column: 0).minY, width: geometry.rowHeaderWidth, height: geometry.height(ofRow: i))
                view.title = String(i + 1)
                view.highlighted = (sel.top...sel.bottom).contains(i)
            }
        }
    }

    // MARK: Selection

    func select(_ s: SigmaSelection, scroll: Bool) {
        guard s != controller.selection else { return }
        if editing != nil { commitEditing(move: .none) }
        controller.selection = s
        refreshActiveInput()
        if scroll { scrollToVisible(s.corner) }
        setNeedsLayout()
        // Find selects each hit; the keyboard stays with its search field.
        if controller.panel == nil && !isFirstResponder { becomeFirstResponder() }
    }

    private func refreshActiveInput() {
        let a = controller.selection.active
        controller.activeInput = workbook?.input(at: a) ?? ""
        let style = workbook?.style(at: a) ?? SigmaStyle()
        if controller.activeStyle != style { controller.activeStyle = style }
        let note = workbook?.note(at: a) ?? ""
        if controller.activeNote != note { controller.activeNote = note }
    }

    private func placeSelection() {
        let s = controller.selection
        let g = geometry
        for (pane, rows, cols) in [
            (body, g.frozenRows..<g.rows, g.frozenColumns..<g.columns),
            (top, 0..<g.frozenRows, g.frozenColumns..<g.columns),
            (left, g.frozenRows..<g.rows, 0..<g.frozenColumns),
            (corner, 0..<g.frozenRows, 0..<g.frozenColumns),
        ] {
            let r1 = max(s.top, rows.lowerBound), r2 = min(s.bottom, rows.upperBound - 1)
            let c1 = max(s.left, cols.lowerBound), c2 = min(s.right, cols.upperBound - 1)
            if r1 > r2 || c1 > c2 {
                pane.selection.isHidden = true
            } else {
                pane.selection.isHidden = false
                pane.selection.frame = g.rect(row: r1, column: c1).union(g.rect(row: r2, column: c2))
                // A selection across a frozen line is one box: only its real edges get a border.
                var edges: UIRectEdge = []
                if r1 == s.top { edges.insert(.top) }
                if r2 == s.bottom { edges.insert(.bottom) }
                if c1 == s.left { edges.insert(.left) }
                if c2 == s.right { edges.insert(.right) }
                pane.selection.edges = edges
                pane.bringSubviewToFront(pane.selection)
            }
            let a = s.active
            if rows.contains(a.row) && cols.contains(a.column) && !s.isSingle {
                pane.activeOutline.isHidden = false
                pane.activeOutline.frame = g.rect(row: a.row, column: a.column)
                pane.bringSubviewToFront(pane.activeOutline)
            } else {
                pane.activeOutline.isHidden = true
            }
            if editor.superview === pane { pane.bringSubviewToFront(editor) }
        }
        let off = contentOffset
        let tl = g.screenRect(row: s.top, column: s.left, offset: off)
        let br = g.screenRect(row: s.bottom, column: s.right, offset: off)
        let shown = editing == nil && !controller.readOnly
        // A handle on a scrolling cell hides once that cell has scrolled under a frozen pane.
        func visible(_ row: Int, _ column: Int, _ p: CGPoint) -> Bool {
            if row >= g.frozenRows && p.y < g.columnHeaderHeight + g.frozenHeight - 2 { return false }
            if column >= g.frozenColumns && p.x < g.rowHeaderWidth + g.frozenWidth - 2 { return false }
            return true
        }
        let tlPoint = CGPoint(x: tl.minX, y: tl.minY), brPoint = CGPoint(x: br.maxX, y: br.maxY)
        overlay.place(topLeft: tlPoint, bottomRight: brPoint,
                      topLeftVisible: shown && !filling && visible(s.top, s.left, tlPoint),
                      bottomRightVisible: shown && visible(s.bottom, s.right, brPoint),
                      filling: filling,
                      clip: CGRect(x: g.rowHeaderWidth - 12, y: g.columnHeaderHeight - 12, width: bounds.width, height: bounds.height))
        if let t = fillTarget {
            let a = g.screenRect(row: t.top, column: t.left, offset: off), b = g.screenRect(row: t.bottom, column: t.right, offset: off)
            overlay.showFill(a.union(b))
        } else {
            overlay.showFill(nil)
        }
    }

    private func scrollToVisible(_ a: SigmaAddress) {
        let g = geometry
        var off = contentOffset
        let rect = g.rect(row: a.row, column: a.column)
        if a.column >= g.frozenColumns {
            let viewW = bounds.width - g.rowHeaderWidth - g.frozenWidth
            if rect.minX - g.frozenWidth < off.x { off.x = rect.minX - g.frozenWidth }
            else if rect.maxX - g.frozenWidth > off.x + viewW { off.x = rect.maxX - g.frozenWidth - viewW }
        }
        if a.row >= g.frozenRows {
            let keyboard = editing != nil ? keyboardOverlap : 0
            let viewH = bounds.height - g.columnHeaderHeight - g.frozenHeight - keyboard
            if rect.minY - g.frozenHeight < off.y { off.y = rect.minY - g.frozenHeight }
            else if rect.maxY - g.frozenHeight > off.y + viewH { off.y = rect.maxY - g.frozenHeight - viewH }
        }
        off.x = min(max(0, off.x), max(0, contentSize.width - bounds.width))
        off.y = min(max(0, off.y), max(0, contentSize.height - bounds.height))
        if off != contentOffset { setContentOffset(off, animated: false) }
    }

    private func dragHandle(_ handle: HandleOverlay.Handle, to p: CGPoint, ended: Bool) {
        if filling && handle == .bottomRight { return dragFill(to: p, ended: ended) }
        // Near an edge, the sheet scrolls under the finger.
        var off = contentOffset
        let edge: CGFloat = 36, step: CGFloat = 14
        if p.x > bounds.width - edge { off.x += step } else if p.x < geometry.rowHeaderWidth + geometry.frozenWidth + edge { off.x -= step }
        if p.y > bounds.height - edge { off.y += step } else if p.y < geometry.columnHeaderHeight + geometry.frozenHeight + edge { off.y -= step }
        off.x = min(max(0, off.x), max(0, contentSize.width - bounds.width))
        off.y = min(max(0, off.y), max(0, contentSize.height - bounds.height))
        if off != contentOffset { contentOffset = off }
        guard case let .cell(r, c) = geometry.hit(p, offset: contentOffset) else { return }
        let s = controller.selection
        let fixed = handle == .bottomRight ? s.topLeft : s.bottomRight
        let next = SigmaSelection(active: fixed, corner: SigmaAddress(row: r, column: c))
        if next != s {
            controller.selection = next
            refreshActiveInput()
            UISelectionFeedbackGenerator().selectionChanged()
            setNeedsLayout()
        }
        if ended { showMenu(at: CGPoint(x: p.x + contentOffset.x, y: p.y + contentOffset.y)) }
    }

    /// Fill mode: the target grows from the selection in the direction dragged furthest.
    private func dragFill(to p: CGPoint, ended: Bool) {
        let s = controller.selection
        if case let .cell(r, c) = geometry.hit(CGPoint(x: max(p.x, geometry.rowHeaderWidth + 1), y: max(p.y, geometry.columnHeaderHeight + 1)), offset: contentOffset) {
            let down = r > s.bottom ? r - s.bottom : r < s.top ? s.top - r : 0
            let across = c > s.right ? c - s.right : c < s.left ? s.left - c : 0
            if down == 0 && across == 0 {
                fillTarget = nil
            } else if down >= across {
                fillTarget = SigmaSelection(active: SigmaAddress(row: min(s.top, r), column: s.left), corner: SigmaAddress(row: max(s.bottom, r), column: s.right))
            } else {
                fillTarget = SigmaSelection(active: SigmaAddress(row: s.top, column: min(s.left, c)), corner: SigmaAddress(row: s.bottom, column: max(s.right, c)))
            }
            setNeedsLayout()
        }
        guard ended else { return }
        let target = fillTarget
        fillTarget = nil
        filling = false
        if let book = workbook, let target {
            do {
                try book.fill(from: s, to: target)
                controller.selection = SigmaSelection(active: target.topLeft, corner: target.bottomRight)
                refreshActiveInput()
            } catch {
                flash(error)
            }
        }
        setNeedsLayout()
    }

    // MARK: Zoom

    @objc private func pinched(_ g: UIPinchGestureRecognizer) {
        guard g.state == .changed || g.state == .ended else { return }
        let p = g.location(in: self)
        setZoom(zoom * g.scale, focus: CGPoint(x: p.x - contentOffset.x, y: p.y - contentOffset.y))
        g.scale = 1
    }

    /// Zooms about a point in the viewport, keeping what is under it in place.
    func setZoom(_ next: CGFloat, focus f: CGPoint) {
        let old = zoom
        let z = min(2, max(0.5, next))
        guard abs(z - old) > 0.001 else { return }
        let g = geometry
        let sx = (contentOffset.x + f.x - g.rowHeaderWidth) / old
        let sy = (contentOffset.y + f.y - g.columnHeaderHeight) / old
        zoom = z
        geometryKey = nil
        refreshGeometry()
        let ng = geometry
        var off = CGPoint(x: sx * z - (f.x - ng.rowHeaderWidth), y: sy * z - (f.y - ng.columnHeaderHeight))
        off.x = min(max(0, off.x), max(0, contentSize.width - bounds.width))
        off.y = min(max(0, off.y), max(0, contentSize.height - bounds.height))
        contentOffset = off
        if editing != nil {
            editor.font = gridFont(controller.activeStyle, zoom: zoom)
            sizeEditor()
        }
        chartKey = nil
        setNeedsLayout()
    }

    /// Redraws after a change made outside a gesture (AutoSum, a command).
    func refreshAfterCommand() {
        refreshActiveInput()
        setNeedsLayout()
    }

    /// Gives the cell editor the keyboard again once a sheet has gone.
    func focusEditorSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, self.editing != nil else { return }
            self.editor.becomeFirstResponder()
        }
    }

    // MARK: Gestures

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        if filling {
            filling = false
            fillTarget = nil
            setNeedsLayout()
        }
        let p = g.location(in: self)
        let viewport = CGPoint(x: p.x - contentOffset.x, y: p.y - contentOffset.y)
        switch geometry.hit(viewport, offset: contentOffset) {
        case let .cell(r, c):
            let a = SigmaAddress(row: r, column: c)
            if editing == a { return }
            if controller.selectedChart != nil {
                controller.selectedChart = nil
                setNeedsLayout()
            }
            // A tap on the cell already chosen opens it for typing; anywhere else chooses.
            if controller.selection.isSingle && controller.selection.active == a && !controller.readOnly {
                beginEditing(initial: nil)
            } else {
                select(SigmaSelection(a), scroll: false)
            }
        case let .columnHeader(c):
            select(SigmaSelection(active: SigmaAddress(row: 0, column: c), corner: SigmaAddress(row: geometry.rows - 1, column: c)), scroll: false)
            showMenu(at: p)
        case let .rowHeader(r):
            select(SigmaSelection(active: SigmaAddress(row: r, column: 0), corner: SigmaAddress(row: r, column: geometry.columns - 1)), scroll: false)
            showMenu(at: p)
        case .corner:
            select(SigmaSelection(active: SigmaAddress(row: 0, column: 0), corner: SigmaAddress(row: geometry.rows - 1, column: geometry.columns - 1)), scroll: false)
        }
    }

    @objc private func longPressed(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        let p = g.location(in: self)
        let viewport = CGPoint(x: p.x - contentOffset.x, y: p.y - contentOffset.y)
        if case let .cell(r, c) = geometry.hit(viewport, offset: contentOffset) {
            let a = SigmaAddress(row: r, column: c)
            if !controller.selection.contains(a) { select(SigmaSelection(a), scroll: false) }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showMenu(at: p)
        }
    }

    private var resizingColumn: (column: Int, startWidth: CGFloat)?
    private var resizingRow: (row: Int, startHeight: CGFloat)?
    /// Where the finger first came down: a drag is only a resize if it started on an edge.
    private var touchDown: CGPoint?

    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard g !== panGestureRecognizer, g is UIPanGestureRecognizer, !(g.view is HandleOverlay) else {
            return super.gestureRecognizerShouldBegin(g)
        }
        // Only a drag that starts on a column edge (or a row edge) in the headers resizes.
        let p = touchDown ?? g.location(in: self)
        let viewport = CGPoint(x: p.x - contentOffset.x, y: p.y - contentOffset.y)
        guard !controller.readOnly else { return false }
        if viewport.x < geometry.rowHeaderWidth, viewport.y > geometry.columnHeaderHeight {
            let y = viewport.y - geometry.columnHeaderHeight
            let sheetY = y < geometry.frozenHeight ? y : y + contentOffset.y
            guard let r = geometry.rowEdge(nearY: sheetY, slop: 10) else { return false }
            resizingRow = (r, geometry.height(ofRow: r))
            resizingColumn = nil
            return true
        }
        guard viewport.y < geometry.columnHeaderHeight, viewport.x > geometry.rowHeaderWidth else { return false }
        let x = viewport.x - geometry.rowHeaderWidth
        let sheetX = x < geometry.frozenWidth ? x : x + contentOffset.x
        guard let c = geometry.columnEdge(nearX: sheetX, slop: 14) else { return false }
        resizingColumn = (c, geometry.width(ofColumn: c))
        resizingRow = nil
        return true
    }

    /// Touches in the cell being edited belong to its text field (placing the caret, selecting text).
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if g is UIPanGestureRecognizer { touchDown = touch.location(in: self) }
        guard let v = touch.view else { return true }
        return !(v === editor || v.isDescendant(of: editor))
    }

    @objc private func resizing(_ g: UIPanGestureRecognizer) {
        if let rr = resizingRow {
            let h = max(14 * zoom, rr.startHeight + g.translation(in: self).y)
            switch g.state {
            case .began: break
            case .changed:
                liveRowHeight = (rr.row, h)
                geometryKey = nil
                setNeedsLayout()
            case .ended:
                liveRowHeight = nil
                resizingRow = nil
                try? workbook?.setHeight(Double(h / zoom), ofRow: rr.row)
            default:
                liveRowHeight = nil
                resizingRow = nil
                geometryKey = nil
                setNeedsLayout()
            }
            return
        }
        guard let r = resizingColumn else { return }
        let w = max(24 * zoom, r.startWidth + g.translation(in: self).x)
        switch g.state {
        case .began:
            break
        case .changed:
            liveColumnWidth = (r.column, w)
            geometryKey = nil
            setNeedsLayout()
        case .ended:
            liveColumnWidth = nil
            resizingColumn = nil
            try? workbook?.setWidth(Double(w / zoom), ofColumn: r.column)
        default:
            liveColumnWidth = nil
            resizingColumn = nil
            geometryKey = nil
            setNeedsLayout()
        }
    }

    // MARK: Editing

    func beginEditing(initial: String?, focus: Bool = true) {
        guard !controller.readOnly, let book = workbook else { return }
        let a = controller.selection.active
        if controller.selection.isSingle == false { controller.selection = SigmaSelection(a) }
        editing = a
        let raw = initial ?? book.input(at: a)
        let pane = paneFor(a)
        let style = book.style(at: a)
        editor.font = gridFont(style, zoom: zoom)
        editor.textAlignment = .left
        editor.text = raw
        pane.addSubview(editor)
        sizeEditor()
        controller.isEditing = true
        controller.editText = raw
        scrollToVisible(a)
        if focus { editor.becomeFirstResponder() }
        setNeedsLayout()
    }

    func setEditorText(_ text: String) {
        if editing == nil { beginEditing(initial: text, focus: false) } else if editor.text != text { editor.text = text }
        controller.editText = text
        sizeEditor()
    }

    private func insertIntoEditor(_ text: String) {
        if editing == nil { beginEditing(initial: nil) }
        editor.insertText(text)
        editorChanged()
    }

    @objc private func editorChanged() {
        controller.editText = editor.text ?? ""
        sizeEditor()
    }

    /// The editor covers its cell, and grows to the right only when the text needs the room.
    private func sizeEditor() {
        guard let a = editing else { return }
        let rect = geometry.rect(row: a.row, column: a.column)
        let textWidth = ((editor.text ?? "") as NSString).size(withAttributes: [.font: editor.font ?? gridFont(nil, zoom: zoom)]).width + 18
        let room = max(rect.width, bounds.width - geometry.rowHeaderWidth - 16)
        editor.frame = CGRect(x: rect.minX, y: rect.minY, width: min(max(rect.width, textWidth), room), height: rect.height)
    }

    func commitEditing(move: Move) {
        guard let a = editing, let book = workbook else { return }
        let text = controller.editText
        editing = nil
        controller.isEditing = false
        editor.removeFromSuperview()
        if text != book.input(at: a) {
            do { try book.set(text, at: a) } catch { flash(error) }
        }
        let g = geometry
        var next = a
        switch move {
        case .down: next.row = min(g.rows - 1, a.row + 1)
        case .up: next.row = max(0, a.row - 1)
        case .right: next.column = min(g.columns - 1, a.column + 1)
        case .left: next.column = max(0, a.column - 1)
        case .none: break
        }
        controller.selection = SigmaSelection(next)
        refreshActiveInput()
        scrollToVisible(next)
        becomeFirstResponder()
        setNeedsLayout()
    }

    func cancelEditing() {
        guard editing != nil else { return }
        editing = nil
        controller.isEditing = false
        editor.removeFromSuperview()
        becomeFirstResponder()
        setNeedsLayout()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        commitEditing(move: .down)
        return false
    }

    private func paneFor(_ a: SigmaAddress) -> Pane {
        let fr = a.row < geometry.frozenRows, fc = a.column < geometry.frozenColumns
        return fr && fc ? corner : fr ? top : fc ? left : body
    }

    private var keyboardOverlap: CGFloat {
        guard let window else { return 0 }
        let frame = convert(bounds, to: window)
        let kb = keyboardFrame
        return max(0, frame.maxY - kb.minY)
    }

    private var keyboardFrame: CGRect = .null

    override func didMoveToWindow() {
        super.didMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        guard window != nil else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChange(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillChange(_ n: Notification) {
        keyboardFrame = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .null
        contentInset.bottom = keyboardOverlap
        verticalScrollIndicatorInsets.bottom = keyboardOverlap
        if let a = editing { scrollToVisible(a) }
    }

    @objc private func keyboardWillHide(_ n: Notification) {
        keyboardFrame = .null
        contentInset.bottom = 0
        verticalScrollIndicatorInsets.bottom = 0
    }

    // MARK: Actions

    func perform(_ action: Action) {
        guard let book = workbook else { return }
        let s = controller.selection
        if controller.readOnly && action != .copy && action != .find { return }
        do {
            switch action {
            case .undo: if editing != nil { cancelEditing() } else { book.undo() }
            case .redo: book.redo()
            case .copy, .cut:
                let c = action == .cut ? try book.cut(s) : try book.copy(s)
                clip = c
                UIPasteboard.general.string = c.text
            case .paste:
                guard let text = UIPasteboard.general.string else { return }
                let landed = try book.paste(text, clip: clip, at: s.topLeft)
                if clip?.isCut == true { clip = nil }
                if landed.rows > 0 && landed.columns > 0 {
                    controller.selection = SigmaSelection(active: s.topLeft, corner: SigmaAddress(row: s.top + landed.rows - 1, column: s.left + landed.columns - 1))
                }
            case .pasteValues:
                guard let clip else { return }
                let landed = try book.pasteValues(clip, at: s.topLeft)
                if landed.rows > 0 && landed.columns > 0 {
                    controller.selection = SigmaSelection(active: s.topLeft, corner: SigmaAddress(row: s.top + landed.rows - 1, column: s.left + landed.columns - 1))
                }
            case .fill:
                filling = true
            case .clear: try book.clear(from: s.topLeft, to: s.bottomRight)
            case .fillDown:
                try book.fill(from: SigmaSelection(active: s.topLeft, corner: SigmaAddress(row: s.top, column: s.right)), to: s)
            case .fillRight:
                try book.fill(from: SigmaSelection(active: s.topLeft, corner: SigmaAddress(row: s.bottom, column: s.left)), to: s)
            case .insertRowAbove: try book.insertRows(at: s.top, count: s.bottom - s.top + 1)
            case .insertRowBelow: try book.insertRows(at: s.bottom + 1, count: s.bottom - s.top + 1)
            case .deleteRows: try book.deleteRows(at: s.top, count: s.bottom - s.top + 1)
            case .insertColumnLeft: try book.insertColumns(at: s.left, count: s.right - s.left + 1)
            case .insertColumnRight: try book.insertColumns(at: s.right + 1, count: s.right - s.left + 1)
            case .deleteColumns: try book.deleteColumns(at: s.left, count: s.right - s.left + 1)
            case .edit: beginEditing(initial: nil)
            case .freezeHere: try book.freeze(rows: s.active.row + 1, columns: s.active.column + 1)
            case .freezeOneRow: try book.freeze(rows: 1, columns: geometry.frozenColumns)
            case .freezeTwoRows: try book.freeze(rows: 2, columns: geometry.frozenColumns)
            case .freezeOneColumn: try book.freeze(rows: geometry.frozenRows, columns: 1)
            case .unfreeze: try book.freeze(rows: 0, columns: 0)
            case .sortAscending: controller.sort(ascending: true)
            case .sortDescending: controller.sort(ascending: false)
            case .note: controller.panel = .note
            case .conditionalFormatting: controller.panel = .conditionalFormatting
            case .find: controller.panel = .find
            }
        } catch {
            flash(error)
        }
        refreshActiveInput()
        setNeedsLayout()
    }

    private func flash(_ error: Error) {
        let note = UINotificationFeedbackGenerator()
        note.notificationOccurred(.error)
    }

    // MARK: Edit menu

    private var editMenuShowing = false

    func showMenu(at p: CGPoint) {
        guard editing == nil else { return }
        editMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: p))
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        if let id = controller.selectedChart {
            guard !controller.readOnly else { return nil }
            return UIMenu(children: [
                UIAction(title: "Edit Chart", image: UIImage(systemName: "slider.horizontal.3")) { [weak self] _ in self?.controller.panel = .chart },
                UIAction(title: "Delete Chart", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                    try? self?.workbook?.removeChart(id: id)
                    self?.controller.selectedChart = nil
                },
            ])
        }
        let s = controller.selection
        let g = geometry
        let wholeRows = s.left == 0 && s.right == g.columns - 1
        let wholeColumns = s.top == 0 && s.bottom == g.rows - 1
        let ro = controller.readOnly
        func act(_ title: String, _ image: String?, _ a: Action, destructive: Bool = false) -> UIAction {
            UIAction(title: title, image: image.flatMap(UIImage.init(systemName:)), attributes: destructive ? .destructive : []) { [weak self] _ in self?.perform(a) }
        }
        var basics: [UIMenuElement] = [act("Copy", "doc.on.doc", .copy)]
        if !ro {
            basics.insert(act("Cut", "scissors", .cut), at: 0)
            if UIPasteboard.general.hasStrings { basics.append(act("Paste", "doc.on.clipboard", .paste)) }
            // Values only needs Sigma's own copy, which knows what the cells computed.
            if clip != nil { basics.append(act("Paste Values Only", "doc.on.clipboard.fill", .pasteValues)) }
            basics.append(act("Clear", "eraser", .clear))
            if s.isSingle { basics.insert(act("Edit", "pencil", .edit), at: 0) }
        }
        guard !ro else { return UIMenu(children: basics) }
        var more: [UIMenuElement] = []
        if !wholeRows && !wholeColumns {
            var fills = [act("Drag to Fill…", "square.and.arrow.down.on.square", .fill)]
            if s.bottom > s.top { fills.append(act("Fill Down", "arrow.down.to.line", .fillDown)) }
            if s.right > s.left { fills.append(act("Fill Right", "arrow.right.to.line", .fillRight)) }
            more.append(UIMenu(title: "Fill", image: UIImage(systemName: "square.and.pencil"), children: fills))
        }
        let rowWord = s.bottom > s.top ? "Rows" : "Row"
        let colWord = s.right > s.left ? "Columns" : "Column"
        let rowItems = [act("Insert \(rowWord) Above", "arrow.up.to.line.compact", .insertRowAbove), act("Insert \(rowWord) Below", "arrow.down.to.line.compact", .insertRowBelow), act("Delete \(rowWord)", "trash", .deleteRows, destructive: true)]
        let colItems = [act("Insert \(colWord) Left", "arrow.left.to.line.compact", .insertColumnLeft), act("Insert \(colWord) Right", "arrow.right.to.line.compact", .insertColumnRight), act("Delete \(colWord)", "trash", .deleteColumns, destructive: true)]
        if wholeRows { more += rowItems }
        else if wholeColumns { more += colItems }
        else {
            more.append(UIMenu(title: "Rows", image: UIImage(systemName: "rectangle.split.1x2"), children: rowItems))
            more.append(UIMenu(title: "Columns", image: UIImage(systemName: "rectangle.split.2x1"), children: colItems))
        }
        if !wholeRows {
            more.append(UIMenu(title: "Sort", image: UIImage(systemName: "arrow.up.arrow.down"), children: [
                act("Sort A → Z", "arrow.up", .sortAscending), act("Sort Z → A", "arrow.down", .sortDescending),
            ]))
        }
        if s.isSingle {
            more.append(act(controller.activeNote.isEmpty ? "Add Note" : "Edit Note", "note.text", .note))
        }
        let frozen = g.frozenRows > 0 || g.frozenColumns > 0
        var freezes = [act("1 Row", nil, .freezeOneRow), act("2 Rows", nil, .freezeTwoRows), act("1 Column", nil, .freezeOneColumn),
                       act("Up to \(s.active)", nil, .freezeHere)]
        if frozen { freezes.append(act("No Frozen Panes", nil, .unfreeze)) }
        more.append(UIMenu(title: "Freeze", image: UIImage(systemName: "snowflake"), children: freezes))
        return UIMenu(children: basics + more)
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, willPresentMenuFor configuration: UIEditMenuConfiguration, animator: UIEditMenuInteractionAnimating) {
        editMenuShowing = true
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, willDismissMenuFor configuration: UIEditMenuConfiguration, animator: UIEditMenuInteractionAnimating) {
        editMenuShowing = false
    }

    // MARK: Hardware keyboard

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        guard editing == nil else { return nil }
        func k(_ input: String, _ mods: UIKeyModifierFlags = [], _ title: String? = nil, _ sel: Selector) -> UIKeyCommand {
            let c = UIKeyCommand(input: input, modifierFlags: mods, action: sel)
            if let title { c.discoverabilityTitle = title }
            c.wantsPriorityOverSystemBehavior = true
            return c
        }
        return [
            k("c", .command, "Copy", #selector(keyCopy)), k("x", .command, "Cut", #selector(keyCut)),
            k("v", .command, "Paste", #selector(keyPaste)), k("z", .command, "Undo", #selector(keyUndo)),
            k("z", [.command, .shift], "Redo", #selector(keyRedo)), k("a", .command, "Select All", #selector(keySelectAll)),
            k("d", .command, "Fill Down", #selector(keyFillDown)), k("r", .command, "Fill Right", #selector(keyFillRight)),
            k("b", .command, "Bold", #selector(keyBold)), k("i", .command, "Italic", #selector(keyItalic)),
            k("u", .command, "Underline", #selector(keyUnderline)), k("f", .command, "Find", #selector(keyFind)),
            k("=", .command, "Zoom In", #selector(keyZoomIn)), k("+", .command, nil, #selector(keyZoomIn)),
            k("-", .command, "Zoom Out", #selector(keyZoomOut)), k("0", .command, "Actual Size", #selector(keyZoomReset)),
        ]
    }

    @objc private func keyCopy() { perform(.copy) }
    @objc private func keyCut() { perform(.cut) }
    @objc private func keyPaste() { perform(.paste) }
    @objc private func keyUndo() { perform(.undo) }
    @objc private func keyRedo() { perform(.redo) }
    @objc private func keyFillDown() { perform(.fillDown) }
    @objc private func keyFillRight() { perform(.fillRight) }
    @objc private func keyBold() { controller.toggleBold() }
    @objc private func keyItalic() { controller.toggleItalic() }
    @objc private func keyUnderline() { controller.toggleUnderline() }
    @objc private func keyFind() { perform(.find) }
    @objc private func keyZoomIn() { setZoom(zoom * 1.25, focus: CGPoint(x: bounds.width / 2, y: bounds.height / 2)) }
    @objc private func keyZoomOut() { setZoom(zoom / 1.25, focus: CGPoint(x: bounds.width / 2, y: bounds.height / 2)) }
    @objc private func keyZoomReset() { setZoom(1, focus: CGPoint(x: bounds.width / 2, y: bounds.height / 2)) }
    @objc private func keySelectAll() {
        select(SigmaSelection(active: SigmaAddress(row: 0, column: 0), corner: SigmaAddress(row: geometry.rows - 1, column: geometry.columns - 1)), scroll: false)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // While a panel is open, typing belongs to it, never to the cells behind.
        guard editing == nil, controller.panel == nil, let key = presses.first?.key, !key.modifierFlags.contains(.command) else {
            return super.pressesBegan(presses, with: event)
        }
        let s = controller.selection
        let extend = key.modifierFlags.contains(.shift)
        let g = geometry
        func moved(_ dr: Int, _ dc: Int) {
            let from = extend ? s.corner : s.active
            let to = SigmaAddress(row: min(max(0, from.row + dr), g.rows - 1), column: min(max(0, from.column + dc), g.columns - 1))
            select(extend ? SigmaSelection(active: s.active, corner: to) : SigmaSelection(to), scroll: true)
        }
        switch key.keyCode {
        case .keyboardUpArrow: moved(-1, 0)
        case .keyboardDownArrow: moved(1, 0)
        case .keyboardLeftArrow: moved(0, -1)
        case .keyboardRightArrow: moved(0, 1)
        case .keyboardTab: moved(0, extend ? -1 : 1)
        case .keyboardReturnOrEnter: if extend { moved(-1, 0) } else { beginEditing(initial: nil) }
        case .keyboardDeleteOrBackspace, .keyboardDeleteForward: perform(.clear)
        case .keyboardEscape: break
        default:
            let chars = key.characters
            if !chars.isEmpty, !controller.readOnly, chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                beginEditing(initial: chars)
            } else {
                super.pressesBegan(presses, with: event)
            }
        }
    }
}

// MARK: - Pieces

/// A region of cells: the scrolling body or one of the frozen panes.
final class Pane: UIView {
    var cells: [Int: GridCellView] = [:]
    let selection = SelectionBox()
    let activeOutline = UIView()

    init() {
        super.init(frame: .zero)
        backgroundColor = .white
        clipsToBounds = true
        isUserInteractionEnabled = true
        activeOutline.isUserInteractionEnabled = false
        activeOutline.layer.borderColor = GridColors.accent.cgColor
        activeOutline.layer.borderWidth = 1
        activeOutline.backgroundColor = .clear
        addSubview(selection)
        addSubview(activeOutline)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

/// The tinted selection, with a border on the edges it says.
final class SelectionBox: UIView {
    var edges: UIRectEdge = .all { didSet { if edges != oldValue { setNeedsDisplay() } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let b = bounds
        GridColors.accentSoft.setFill()
        ctx.fill(b)
        GridColors.accent.setFill()
        let w: CGFloat = 2
        if edges.contains(.top) { ctx.fill(CGRect(x: 0, y: 0, width: b.width, height: w)) }
        if edges.contains(.bottom) { ctx.fill(CGRect(x: 0, y: b.height - w, width: b.width, height: w)) }
        if edges.contains(.left) { ctx.fill(CGRect(x: 0, y: 0, width: w, height: b.height)) }
        if edges.contains(.right) { ctx.fill(CGRect(x: b.width - w, y: 0, width: w, height: b.height)) }
    }
}

final class HeaderPane: UIView {
    var views: [Int: GridHeaderView] = [:]

    init() {
        super.init(frame: .zero)
        backgroundColor = GridColors.header
        clipsToBounds = true
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

/// The two round handles that stretch a selection, over everything else.
final class HandleOverlay: UIView {
    enum Handle { case topLeft, bottomRight }
    var onDrag: ((Handle, CGPoint, Bool) -> Void)?
    private let tl = HandleKnob(), br = HandleKnob()
    private let clipper = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipper.clipsToBounds = true
        clipper.isUserInteractionEnabled = true
        addSubview(clipper)
        fillOutline.fillColor = UIColor.clear.cgColor
        fillOutline.strokeColor = GridColors.accent.cgColor
        fillOutline.lineWidth = 2
        fillOutline.lineDashPattern = [6, 4]
        layer.addSublayer(fillOutline)
        for (knob, which) in [(tl, Handle.topLeft), (br, Handle.bottomRight)] {
            clipper.addSubview(knob)
            let pan = UIPanGestureRecognizer(target: self, action: #selector(dragged(_:)))
            knob.addGestureRecognizer(pan)
            knob.which = which
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private let fillOutline = CAShapeLayer()

    func place(topLeft: CGPoint, bottomRight: CGPoint, topLeftVisible: Bool, bottomRightVisible: Bool, filling: Bool, clip: CGRect) {
        clipper.frame = clip
        tl.isHidden = !topLeftVisible
        br.isHidden = !bottomRightVisible
        br.filling = filling
        tl.center = CGPoint(x: topLeft.x - clip.minX, y: topLeft.y - clip.minY)
        br.center = CGPoint(x: bottomRight.x - clip.minX, y: bottomRight.y - clip.minY)
    }

    /// The block a fill drag would reach, while it is dragged; nil hides it.
    func showFill(_ rect: CGRect?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillOutline.path = rect.map { UIBezierPath(rect: $0).cgPath }
        CATransaction.commit()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        for k in [tl, br] where !k.isHidden && k.frame.offsetBy(dx: clipper.frame.minX, dy: clipper.frame.minY).contains(point) { return true }
        return false
    }

    @objc private func dragged(_ g: UIPanGestureRecognizer) {
        guard let knob = g.view as? HandleKnob else { return }
        onDrag?(knob.which, g.location(in: self), g.state == .ended || g.state == .cancelled)
    }
}

final class HandleKnob: UIView {
    var which: HandleOverlay.Handle = .bottomRight
    private let dot = UIView()
    private let plus = UIImageView(image: UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)))
    /// The fill handle: a green square with a plus, so it reads differently from the round selection handles.
    var filling = false {
        didSet {
            guard filling != oldValue else { return }
            dot.layer.cornerRadius = filling ? 3 : 7
            dot.backgroundColor = filling ? GridColors.accent : .white
            dot.frame = filling ? CGRect(x: 13, y: 13, width: 18, height: 18) : CGRect(x: 15, y: 15, width: 14, height: 14)
            plus.isHidden = !filling
        }
    }

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        backgroundColor = .clear
        dot.frame = CGRect(x: 15, y: 15, width: 14, height: 14)
        dot.backgroundColor = .white
        dot.layer.cornerRadius = 7
        dot.layer.borderWidth = 2.5
        dot.layer.borderColor = GridColors.accent.cgColor
        dot.isUserInteractionEnabled = false
        addSubview(dot)
        plus.tintColor = .white
        plus.contentMode = .center
        plus.frame = CGRect(x: 13, y: 13, width: 18, height: 18)
        plus.isHidden = true
        plus.isUserInteractionEnabled = false
        addSubview(plus)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

/// The in-cell text field. Tab and the arrow keys of a hardware keyboard
/// finish the edit and move, as in a desktop spreadsheet.
final class CellEditor: UITextField {
    var onKey: ((SigmaGridView.Move) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        layer.borderColor = GridColors.accent.cgColor
        layer.borderWidth = 2
        autocorrectionType = .no
        autocapitalizationType = .none
        smartQuotesType = .no
        smartDashesType = .no
        spellCheckingType = .no
        returnKeyType = .next
        leftView = UIView(frame: CGRect(x: 0, y: 0, width: 5, height: 1))
        leftViewMode = .always
        textColor = GridColors.ink
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(tabRight)),
            UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(tabLeft)),
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(up)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(down)),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escape)),
        ]
    }

    @objc private func tabRight() { onKey?(.right) }
    @objc private func tabLeft() { onKey?(.left) }
    @objc private func up() { onKey?(.up) }
    @objc private func down() { onKey?(.down) }
    @objc private func escape() { (superview?.superview as? SigmaGridView)?.cancelEditing() }
}

/// Keys a formula needs that the iPhone keyboard hides, above it while
/// editing, and ƒx for the function list. (Suggestions and argument hints
/// show in the sheet view, just above this bar.)
final class FormulaKeys: UIInputView {
    init(insert: @escaping (String) -> Void, functions: @escaping () -> Void) {
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 44), inputViewStyle: .keyboard)
        let keys = UIStackView()
        keys.axis = .horizontal
        keys.distribution = .fillEqually
        keys.spacing = 5
        keys.translatesAutoresizingMaskIntoConstraints = false
        for key in ["=", "+", "−", "×", "÷", "(", ")", ":", ",", "Σ", "ƒx"] {
            let b = UIButton(type: .system)
            b.setTitle(key, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: key == "ƒx" ? 16 : 19, weight: key == "ƒx" ? .bold : .medium)
            if key == "ƒx" { b.tintColor = GridColors.accent; b.accessibilityLabel = "Insert function" }
            b.backgroundColor = UIColor.secondarySystemBackground
            b.layer.cornerRadius = 6
            let text: String
            switch key {
            case "−": text = "-"
            case "×": text = "*"
            case "÷": text = "/"
            case "Σ": text = "SUM("
            default: text = key
            }
            b.addAction(UIAction { _ in
                UIDevice.current.playInputClick()
                if key == "ƒx" { functions() } else { insert(text) }
            }, for: .touchUpInside)
            keys.addArrangedSubview(b)
        }
        addSubview(keys)
        NSLayoutConstraint.activate([
            keys.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 6),
            keys.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -6),
            keys.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            keys.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
        allowsSelfSizing = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 44) }

    /// "SUMIF(range, **criterion**, [sum_range])  Adds the cells that meet a condition."
    static func syntax(_ fn: SigmaFunction, argument: Int) -> NSAttributedString {
        let args = FormulaHint.arguments(fn.syntax)
        let mono = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let monoBold = UIFont.monospacedSystemFont(ofSize: 14, weight: .bold)
        let out = NSMutableAttributedString(string: fn.name + "(", attributes: [.font: mono, .foregroundColor: GridColors.ink])
        // Past the last argument, a repeating one ("[number2, …]") is still the current one.
        let current = args.isEmpty ? -1 : min(argument, args.count - 1)
        for (i, a) in args.enumerated() {
            if i > 0 { out.append(NSAttributedString(string: ", ", attributes: [.font: mono, .foregroundColor: GridColors.ink])) }
            out.append(NSAttributedString(string: a, attributes: i == current
                ? [.font: monoBold, .foregroundColor: GridColors.accent]
                : [.font: mono, .foregroundColor: GridColors.ink]))
        }
        out.append(NSAttributedString(string: ")", attributes: [.font: mono, .foregroundColor: GridColors.ink]))
        if !fn.description.isEmpty {
            out.append(NSAttributedString(string: "   " + fn.description, attributes: [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.secondaryLabel]))
        }
        return out
    }
}

extension FormulaKeys: UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}
#endif
