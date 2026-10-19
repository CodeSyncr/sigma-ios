import XCTest
@testable import NimbusSigma

/// Opens sheets natively against a running Nimbus Cloud and Sigma. Skipped
/// unless pointed at them (see EditorEndToEndTests).
@MainActor
final class SessionEndToEndTests: XCTestCase {
    private func server() throws -> SigmaClient {
        let env = ProcessInfo.processInfo.environment
        guard let cloud = env["SIGMA_E2E_CLOUD"].flatMap(URL.init(string:)), let key = env["SIGMA_E2E_KEY"] else {
            throw XCTSkip("Set SIGMA_E2E_CLOUD and SIGMA_E2E_KEY to run against live servers.")
        }
        return SigmaClient(apiKey: key, baseURL: cloud)
    }

    func testUploadEditSaveDownload() async throws {
        let server = try server()
        let csv = "Item,Cost\nRent,1200\nFood,450\n"
        let doc = try await server.upload(Data(csv.utf8), filename: "native.csv", title: "Native test")
        var links = 0
        let session = SigmaSession {
            links += 1
            return try await server.link(for: doc.id, mode: .edit).url
        }
        session.saveDelay = 0.2
        session.start()
        try await waitFor("ready") { session.phase == .ready }
        let book = try XCTUnwrap(session.workbook)
        XCTAssertEqual(session.document?.format, .csv)
        XCTAssertEqual(session.document?.mode, .edit)
        XCTAssertEqual(book.input(at: SigmaAddress("B2")!), "1200", "opened from the uploaded file")

        try book.set(["A4": "Total", "B4": "=SUM(B2:B3)"].reduce(into: [:]) { $0[SigmaAddress($1.key)!] = $1.value })
        XCTAssertEqual(session.saveState, .unsaved)
        try await waitFor("autosave") { session.saveState == .saved && session.lastSaved != nil }

        let content = String(decoding: try await server.content(of: doc.id), as: UTF8.self)
        XCTAssertEqual(content, "Item,Cost\nRent,1200\nFood,450\nTotal,1650", "the server's file carries the edit, computed")
        let workbook = String(decoding: try await server.workbook(of: doc.id), as: UTF8.self)
        XCTAssertTrue(workbook.contains("=SUM(B2:B3)"))

        // Opened again, the sheet comes from Sigma's saved workbook, formula intact.
        let again = SigmaSession { try await server.link(for: doc.id, mode: .view).url }
        again.start()
        try await waitFor("reopened") { again.phase == .ready }
        XCTAssertEqual(again.document?.mode, .view)
        XCTAssertEqual(again.workbook?.input(at: SigmaAddress("B4")!), "=SUM(B2:B3)")
        do {
            try await again.save()
            XCTFail("a view link must not save")
        } catch {
            XCTAssertEqual(error as? SigmaError, .editor("This link can view the sheet but not change it."))
        }
        XCTAssertEqual(links, 1)
        try await server.delete(doc.id)
    }

    func testBlankXlsxAndDeadLink() async throws {
        let server = try server()
        let doc = try await server.createBlank(title: "Native blank")
        let session = SigmaSession { try await server.link(for: doc.id).url }
        session.saveDelay = 0.1
        session.start()
        try await waitFor("ready") { session.phase == .ready }
        let book = try XCTUnwrap(session.workbook)
        XCTAssertEqual(book.sheets.map(\.name), ["Sheet1"])
        try book.set("hello", at: SigmaAddress("A1")!)
        session.title = "Renamed natively"
        try await session.save()
        let stored = try await server.content(of: doc.id)
        guard let engine = EngineTests.engine else { throw XCTSkip("Sigma's engine build was not found.") }
        let reread = try await SigmaWorkbook.importing(stored, format: .xlsx, name: "x.xlsx", engine: engine)
        XCTAssertEqual(reread.input(at: SigmaAddress("A1")!), "hello")
        let meta = try await server.document(doc.id)
        XCTAssertEqual(meta.title, "Renamed natively")

        let dead = SigmaSession { URL(string: server.baseURL.absoluteString + "/v/sigma/\(doc.id)?exp=1&kv=1&mode=edit&sig=00&u=1")! }
        dead.start()
        try await waitFor("failed") { if case .failed = dead.phase { return true } else { return false } }
        XCTAssertEqual(dead.phase, .failed(.linkInvalid("This link is not valid or was revoked.")))
        try await server.delete(doc.id)
    }

    private func waitFor(_ what: String, timeout: TimeInterval = 20, _ ok: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !ok() {
            if Date() > end { return XCTFail("timed out waiting for \(what)") }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
