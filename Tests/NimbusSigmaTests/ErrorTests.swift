import XCTest
@testable import NimbusSigma

final class ErrorTests: XCTestCase {
    func testStatusesMapToErrors() {
        XCTAssertEqual(SigmaError.from(status: 410, message: "x"), .linkExpired("x"))
        XCTAssertEqual(SigmaError.from(status: 403, message: "x"), .linkInvalid("x"))
        XCTAssertEqual(SigmaError.from(status: 401, message: "x"), .unauthorized("x"))
        XCTAssertEqual(SigmaError.from(status: 402, message: "x"), .quotaExceeded("x"))
        XCTAssertEqual(SigmaError.from(status: 0, message: "x"), .network("x"))
        XCTAssertEqual(SigmaError.from(status: 500, message: ""), .server(status: 500, message: ""))
        XCTAssertEqual(SigmaError.server(status: 500, message: "").errorDescription, "Nimbus Cloud answered 500.")
    }
}
