import XCTest
@testable import NimbusSigma

final class GridGeometryTests: XCTestCase {
    // 100 rows of 26pt (row 2 is 40pt), 20 columns of 96pt (column 1 is 150pt).
    let g = GridGeometry(rows: 100, columns: 20, frozenRows: 1, frozenColumns: 1,
                         columnWidth: { $0 == 1 ? 150 : 96 }, rowHeight: { $0 == 2 ? 40 : 26 })

    func testEdgesAndLookup() {
        XCTAssertEqual(g.rect(row: 2, column: 1), CGRect(x: 96, y: 52, width: 150, height: 40))
        XCTAssertEqual(g.sheetWidth, 96 * 19 + 150)
        XCTAssertEqual(g.column(atX: 95.9), 0)
        XCTAssertEqual(g.column(atX: 96), 1)
        XCTAssertEqual(g.column(atX: 245), 1)
        XCTAssertEqual(g.column(atX: 246), 2)
        XCTAssertEqual(g.column(atX: -5), 0)
        XCTAssertEqual(g.column(atX: 1e9), 19)
        XCTAssertEqual(g.row(atY: 91.9), 2)
        XCTAssertEqual(g.row(atY: 92), 3)
        XCTAssertEqual(g.contentSize.width, 46 + g.sheetWidth)
    }

    func testHitWithFrozenPanes() {
        let offset = CGPoint(x: 300, y: 500)
        XCTAssertEqual(g.hit(CGPoint(x: 10, y: 10), offset: offset), .corner)
        // Frozen column A stays put whatever the scroll.
        XCTAssertEqual(g.hit(CGPoint(x: 46 + 10, y: 28 + 10), offset: offset), .cell(row: 0, column: 0))
        XCTAssertEqual(g.hit(CGPoint(x: 46 + 10, y: 28 + 30), offset: offset), .cell(row: g.row(atY: 30 + 500), column: 0))
        XCTAssertEqual(g.hit(CGPoint(x: 46 + 100, y: 5), offset: offset), .columnHeader(g.column(atX: 100 + 300)))
        XCTAssertEqual(g.hit(CGPoint(x: 5, y: 28 + 5), offset: offset), .rowHeader(0))
        XCTAssertEqual(g.hit(CGPoint(x: 5, y: 28 + 27), offset: offset), .rowHeader(g.row(atY: 27 + 500)))
    }

    func testScreenRectRoundTrips() {
        let offset = CGPoint(x: 210, y: 333)
        for (r, c) in [(0, 0), (0, 5), (20, 0), (22, 4)] {  // all on screen at this offset
            let rect = g.screenRect(row: r, column: c, offset: offset)
            XCTAssertEqual(g.hit(CGPoint(x: rect.midX, y: rect.midY), offset: offset), .cell(row: r, column: c), "\(r),\(c)")
        }
    }

    func testVisibleScrollingSkipsFrozen() {
        let v = g.visibleScrolling(offset: .zero, viewport: CGSize(width: 390, height: 300))
        XCTAssertEqual(v.columns.lowerBound, 1)
        XCTAssertEqual(v.rows.lowerBound, 1)
        XCTAssertEqual(v.columns.upperBound, g.column(atX: 390 - 46))
        let far = g.visibleScrolling(offset: CGPoint(x: 1000, y: 2000), viewport: CGSize(width: 390, height: 300))
        XCTAssertEqual(far.columns.lowerBound, g.column(atX: 1000 + 96))
    }

    func testResizeEdges() {
        XCTAssertEqual(g.columnEdge(nearX: 246 + 4, slop: 8), 1)
        XCTAssertEqual(g.columnEdge(nearX: 246 - 4, slop: 8), 1)
        XCTAssertNil(g.columnEdge(nearX: 170, slop: 8))
        XCTAssertEqual(g.rowEdge(nearY: 92, slop: 6), 2)
    }

    func testSelection() {
        let s = SigmaSelection(active: SigmaAddress("C5")!, corner: SigmaAddress("A2")!)
        XCTAssertEqual(s.description, "A2:C5")
        XCTAssertTrue(s.contains(SigmaAddress("B3")!))
        XCTAssertFalse(s.contains(SigmaAddress("D3")!))
        XCTAssertEqual(SigmaSelection(SigmaAddress("B2")!).description, "B2")
    }
}
