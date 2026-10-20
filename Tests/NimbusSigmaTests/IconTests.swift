import CoreGraphics
import XCTest
@testable import NimbusSigma

final class IconTests: XCTestCase {
    /// Every icon parses into a glyph that fills its 960-unit box (top at y = -960), as Material Symbols are drawn.
    func testEveryIconFitsItsBox() {
        for icon in SigmaIcon.allCases {
            let box = icon.cgPath.boundingBoxOfPath
            XCTAssertFalse(box.isEmpty, "\(icon) drew nothing")
            XCTAssertGreaterThanOrEqual(box.minX, -0.5, "\(icon)")
            XCTAssertLessThanOrEqual(box.maxX, 960.5, "\(icon)")
            XCTAssertGreaterThanOrEqual(box.minY, -960.5, "\(icon)")
            XCTAssertLessThanOrEqual(box.maxY, 0.5, "\(icon)")
            // A glyph that parsed only partly would be a sliver of its box.
            XCTAssertGreaterThan(box.width * box.height, 960 * 960 * 0.08, "\(icon) looks cut short: \(box)")
        }
    }

    func testRelativeCommandsAndImplicitRepeats() {
        // A 100-unit square: relative moveto, implicit lineto pairs, h and v.
        let square = SVGPath.parse("m10-110 100 0v100h-100z")
        XCTAssertEqual(square.boundingBoxOfPath, CGRect(x: 10, y: -110, width: 100, height: 100))
        // Q then T: the smooth curve reflects the control point.
        let wave = SVGPath.parse("M0 0Q50-100 100 0T200 0")
        XCTAssertEqual(wave.currentPoint, CGPoint(x: 200, y: 0))
        // Numbers run together the way the symbols write them: "-40T720-420".
        let tight = SVGPath.parse("M564-560H312l104 104-56 56")
        XCTAssertEqual(tight.currentPoint, CGPoint(x: 360, y: -400))
    }
}
