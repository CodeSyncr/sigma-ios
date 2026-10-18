import XCTest
import WebKit
@testable import NimbusSigma

/// Opens a real sheet in a real WKWebView against a running Nimbus Cloud and
/// Sigma. Skipped unless pointed at them:
///
///     SIGMA_E2E_CLOUD=http://localhost:3343 SIGMA_E2E_KEY=sgm_test_… swift test
@MainActor
final class EditorEndToEndTests: XCTestCase {
    func testOpenEditExportAndRefresh() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let cloud = env["SIGMA_E2E_CLOUD"].flatMap(URL.init(string:)), let key = env["SIGMA_E2E_KEY"] else {
            throw XCTSkip("Set SIGMA_E2E_CLOUD and SIGMA_E2E_KEY to run against live servers.")
        }
        // The app's server, played by the client.
        let server = SigmaClient(apiKey: key, baseURL: cloud)
        let doc = try await server.createBlank(title: "From Swift", format: .xlsx)
        var minted = 0
        let editor = SigmaEditor {
            minted += 1
            return try await server.link(for: doc.id, mode: .edit).url
        }
        var events: [SigmaEvent] = []
        editor.onEvent = { events.append($0) }
        editor.start()

        try await waitFor("ready", timeout: 20) { editor.phase == .ready }
        XCTAssertEqual(editor.document?.id, doc.id)
        XCTAssertEqual(editor.document?.format, .xlsx)
        XCTAssertEqual(editor.document?.mode, .edit)
        XCTAssertEqual(minted, 1)

        try await editor.setCells(["A1": "42", "B1": "=A1*2", "C1": "=1/0", "D1": "total"])
        try await waitFor("change", timeout: 5) { editor.hasUnsavedChanges }
        let shown = try await editor.values("A1:E1")
        XCTAssertEqual(shown, [[.number(42), .number(84), .text("#DIV/0!"), .text("total"), .empty]])
        do {
            try await editor.setCells(["not-a-cell": "1"])
            XCTFail("a bad address must be refused")
        } catch {
            XCTAssertEqual(error as? SigmaError, .editor(#""not-a-cell" is not a cell address"#))
        }
        try await editor.save()
        XCTAssertFalse(editor.hasUnsavedChanges)
        XCTAssertTrue(events.contains { if case .saved = $0 { return true } else { return false } }, "\(events)")

        let file = try await editor.export(.xlsx)
        XCTAssertEqual(Array(file.data.prefix(2)), [0x50, 0x4B], "an .xlsx is a ZIP")
        XCTAssertEqual(file.filename, "From Swift.xlsx")
        let names = try await editor.sheetNames()
        XCTAssertEqual(names, ["Sheet1"])

        // The server's copy now carries the edit.
        let stored = try await server.content(of: doc.id)
        XCTAssertEqual(Array(stored.prefix(2)), [0x50, 0x4B])
        let workbook = try await server.workbook(of: doc.id)
        XCTAssertTrue(String(decoding: workbook, as: UTF8.self).contains(#""0,1":{"v":"=A1*2"}"#), String(decoding: workbook, as: UTF8.self).prefix(300).description)

        // A dead link is replaced by asking for a fresh one.
        let expired = SigmaEditor(link: URL(string: cloud.absoluteString + "/v/sigma/\(doc.id)?exp=1&kv=1&mode=edit&sig=00&u=1")!) {
            try await server.link(for: doc.id, mode: .view).url
        }
        expired.start()
        try await waitFor("refreshed", timeout: 20) { expired.phase == .ready }
        XCTAssertEqual(expired.document?.mode, .view)
        do {
            try await expired.save()
            XCTFail("a view link must not save")
        } catch {
            XCTAssertEqual(error as? SigmaError, .editor("This link can view the sheet but not change it."))
        }

        // Without a way to refresh, a dead link fails plainly.
        let dead = SigmaEditor(link: URL(string: cloud.absoluteString + "/v/sigma/\(doc.id)?exp=1&kv=1&mode=edit&sig=00&u=1")!)
        dead.start()
        try await waitFor("failed", timeout: 20) { if case .failed = dead.phase { return true } else { return false } }

        try await server.delete(doc.id)
    }

    private func waitFor(_ what: String, timeout: TimeInterval, _ ok: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !ok() {
            if Date() > end { return XCTFail("timed out waiting for \(what)") }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
