import CoreGraphics

/// Where every row and column of a sheet sits, and which cell is under a
/// point on screen, with frozen panes. Pure arithmetic, so it is tested on
/// its own; the grid view only asks it questions.
///
/// Coordinates: the screen has the row-number strip on the left
/// (`rowHeaderWidth`) and the column-letter strip on top
/// (`columnHeaderHeight`). Frozen rows and columns never scroll; the rest
/// scroll by `offset`.
struct GridGeometry: Equatable {
    let rows: Int
    let columns: Int
    let frozenRows: Int
    let frozenColumns: Int
    var rowHeaderWidth: CGFloat = 46
    var columnHeaderHeight: CGFloat = 28

    /// x of each column's left edge from the first column; `columns + 1` entries.
    private(set) var columnX: [CGFloat]
    /// y of each row's top edge from the first row; `rows + 1` entries.
    private(set) var rowY: [CGFloat]

    init(rows: Int, columns: Int, frozenRows: Int, frozenColumns: Int,
         columnWidth: (Int) -> CGFloat, rowHeight: (Int) -> CGFloat) {
        self.rows = max(1, rows)
        self.columns = max(1, columns)
        self.frozenRows = min(max(0, frozenRows), self.rows - 1)
        self.frozenColumns = min(max(0, frozenColumns), self.columns - 1)
        var x: [CGFloat] = [0]
        x.reserveCapacity(self.columns + 1)
        for c in 0..<self.columns { x.append(x[c] + columnWidth(c)) }
        var y: [CGFloat] = [0]
        y.reserveCapacity(self.rows + 1)
        for r in 0..<self.rows { y.append(y[r] + rowHeight(r)) }
        columnX = x
        rowY = y
    }

    var frozenWidth: CGFloat { columnX[frozenColumns] }
    var frozenHeight: CGFloat { rowY[frozenRows] }
    var sheetWidth: CGFloat { columnX[columns] }
    var sheetHeight: CGFloat { rowY[rows] }

    /// The scroll view's content size: headers plus every row and column.
    var contentSize: CGSize { CGSize(width: rowHeaderWidth + sheetWidth, height: columnHeaderHeight + sheetHeight) }

    func width(ofColumn c: Int) -> CGFloat { columnX[c + 1] - columnX[c] }
    func height(ofRow r: Int) -> CGFloat { rowY[r + 1] - rowY[r] }

    /// A cell's rectangle relative to the sheet's top-left (headers excluded, nothing scrolled).
    func rect(row r: Int, column c: Int) -> CGRect {
        CGRect(x: columnX[c], y: rowY[r], width: width(ofColumn: c), height: height(ofRow: r))
    }

    /// The column whose span contains x (sheet coordinates), clamped.
    func column(atX x: CGFloat) -> Int { Self.index(in: columnX, at: x) }
    func row(atY y: CGFloat) -> Int { Self.index(in: rowY, at: y) }

    private static func index(in edges: [CGFloat], at v: CGFloat) -> Int {
        var lo = 0, hi = edges.count - 2
        if v <= 0 { return 0 }
        if v >= edges[hi + 1] { return hi }
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if edges[mid] <= v { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// The scrolling rows and columns visible at a scroll offset in a viewport.
    func visibleScrolling(offset: CGPoint, viewport: CGSize) -> (rows: ClosedRange<Int>, columns: ClosedRange<Int>) {
        let left = offset.x + frozenWidth
        let right = offset.x + viewport.width - rowHeaderWidth
        let top = offset.y + frozenHeight
        let bottom = offset.y + viewport.height - columnHeaderHeight
        let c1 = max(frozenColumns, column(atX: left)), c2 = max(c1, column(atX: max(left, right)))
        let r1 = max(frozenRows, row(atY: top)), r2 = max(r1, row(atY: max(top, bottom)))
        return (r1...r2, c1...c2)
    }

    enum Hit: Equatable {
        case cell(row: Int, column: Int)
        case columnHeader(Int)
        case rowHeader(Int)
        case corner
    }

    /// What is under a point in the viewport (not content) at a scroll offset.
    func hit(_ p: CGPoint, offset: CGPoint) -> Hit {
        let inColumnStrip = p.y < columnHeaderHeight
        let inRowStrip = p.x < rowHeaderWidth
        if inColumnStrip && inRowStrip { return .corner }
        let x = p.x - rowHeaderWidth, y = p.y - columnHeaderHeight
        let sheetX = x < frozenWidth ? x : x + offset.x
        let sheetY = y < frozenHeight ? y : y + offset.y
        if inColumnStrip { return .columnHeader(column(atX: sheetX)) }
        if inRowStrip { return .rowHeader(row(atY: sheetY)) }
        return .cell(row: row(atY: sheetY), column: column(atX: sheetX))
    }

    /// Where a cell's rectangle appears in the viewport at a scroll offset.
    func screenRect(row r: Int, column c: Int, offset: CGPoint) -> CGRect {
        var rect = self.rect(row: r, column: c)
        rect.origin.x += rowHeaderWidth - (c < frozenColumns ? 0 : offset.x)
        rect.origin.y += columnHeaderHeight - (r < frozenRows ? 0 : offset.y)
        return rect
    }

    /// The column edge within `slop` of x (sheet coordinates): the column to its left, for resizing.
    func columnEdge(nearX x: CGFloat, slop: CGFloat) -> Int? {
        let c = column(atX: x)
        if abs(columnX[c + 1] - x) <= slop { return c }
        if c > 0, abs(columnX[c] - x) <= slop { return c - 1 }
        return nil
    }

    func rowEdge(nearY y: CGFloat, slop: CGFloat) -> Int? {
        let r = row(atY: y)
        if abs(rowY[r + 1] - y) <= slop { return r }
        if r > 0, abs(rowY[r] - y) <= slop { return r - 1 }
        return nil
    }
}

/// A rectangle of cells with an active cell inside it.
public struct SigmaSelection: Hashable, Sendable {
    /// The cell typing goes into.
    public var active: SigmaAddress
    /// The far corner of the range; equal to `active` for a single cell.
    public var corner: SigmaAddress

    public init(_ a: SigmaAddress) {
        active = a
        corner = a
    }

    public init(active: SigmaAddress, corner: SigmaAddress) {
        self.active = active
        self.corner = corner
    }

    public var top: Int { min(active.row, corner.row) }
    public var bottom: Int { max(active.row, corner.row) }
    public var left: Int { min(active.column, corner.column) }
    public var right: Int { max(active.column, corner.column) }
    public var isSingle: Bool { active == corner }

    public var topLeft: SigmaAddress { SigmaAddress(row: top, column: left) }
    public var bottomRight: SigmaAddress { SigmaAddress(row: bottom, column: right) }

    public func contains(_ a: SigmaAddress) -> Bool {
        (top...bottom).contains(a.row) && (left...right).contains(a.column)
    }

    /// "B2" or "B2:D9".
    public var description: String { isSingle ? active.description : "\(topLeft):\(bottomRight)" }
}
