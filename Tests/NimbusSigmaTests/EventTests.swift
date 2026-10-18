import XCTest
@testable import NimbusSigma

final class EventTests: XCTestCase {
    func testReady() {
        let e = SigmaEvent.decode([
            "source": "nimbus-docs", "type": "ready",
            "document": ["id": 3, "title": "Sample workbook", "filename": "sample.xlsx", "format": "xlsx", "mode": "edit"],
        ])
        XCTAssertEqual(e, .ready(SigmaEditorDocument(id: 3, title: "Sample workbook", filename: "sample.xlsx", format: .xlsx, mode: .edit)))
    }

    func testSavedAndErrors() {
        let saved = SigmaEvent.decode(["source": "nimbus-docs", "type": "saved", "at": "2026-10-18T21:16:26Z", "size": 2849, "checksum": "99c1"])
        guard case let .saved(at, size, checksum)? = saved else { return XCTFail("saved: \(String(describing: saved))") }
        XCTAssertEqual(at, Dates.parse("2026-10-18T21:16:26Z"))
        XCTAssertEqual(size, 2849)
        XCTAssertEqual(checksum, "99c1")

        XCTAssertEqual(SigmaEvent.decode(["source": "nimbus-docs", "type": "error", "status": 410, "message": "gone"]), .error(status: 410, message: "gone"))
        XCTAssertEqual(SigmaEditor.error(status: 410, message: "x"), .linkExpired("x"))
        XCTAssertEqual(SigmaEditor.error(status: 403, message: "x"), .linkInvalid("x"))
        XCTAssertEqual(SigmaEditor.error(status: 0, message: "x"), .network("x"))
    }

    func testIgnoresOtherMessages() {
        XCTAssertNil(SigmaEvent.decode(["type": "ready"]))
        XCTAssertNil(SigmaEvent.decode(["source": "someone-else", "type": "change"]))
        XCTAssertNil(SigmaEvent.decode(["source": "nimbus-docs", "type": "a-future-event"]))
        XCTAssertNil(SigmaEvent.decode("not a dictionary"))
        XCTAssertEqual(SigmaEvent.decode(["source": "nimbus-docs", "type": "change"]), .changed)
    }
}
