import XCTest
@testable import NimbusSigma

/// Answers every request with a canned response and remembers what was asked.
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var seen: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var req = request
        // URLSession moves a body into a stream; keep it readable for the assertions.
        if req.httpBody == nil, let stream = req.httpBodyStream {
            stream.open()
            var data = Data()
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            while stream.hasBytesAvailable { let n = stream.read(buf, maxLength: 4096); if n <= 0 { break }; data.append(buf, count: n) }
            buf.deallocate()
            stream.close()
            req.httpBody = data
        }
        StubProtocol.seen.append(req)
        let (status, body) = StubProtocol.handler?(req) ?? (500, Data())
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ClientTests: XCTestCase {
    var client: SigmaClient!

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        client = SigmaClient(apiKey: "sgm_test_abc", baseURL: URL(string: "https://cloud.example")!, session: URLSession(configuration: config))
        StubProtocol.seen = []
    }

    // What the cloud returned in the end-to-end run, verbatim.
    let created = #"{"checksum":"7568c95b","created_at":"2026-10-18T21:14:59.850041Z","filename":"small.csv","id":1,"mime":"text/csv","mode":"edit","product":"sigma","size":38,"title":"small.csv","url":"http://localhost:3343/v/sigma/1?exp=1792358999&kv=1&mode=edit&sig=58cc&u=1","url_expires_at":"2026-10-18T21:29:59.855526Z"}"#

    func testUpload() async throws {
        StubProtocol.handler = { _ in (201, Data(self.created.utf8)) }
        let doc = try await client.upload(Data("a,b\n1,2\n".utf8), filename: "small.csv", title: "Small", mode: .edit, linkLifetime: 3600, idempotencyKey: "k1")
        XCTAssertEqual(doc.id, 1)
        XCTAssertEqual(doc.format, .csv)
        XCTAssertEqual(doc.link?.mode, .edit)
        XCTAssertEqual(doc.link?.url.absoluteString, "http://localhost:3343/v/sigma/1?exp=1792358999&kv=1&mode=edit&sig=58cc&u=1")
        XCTAssertNotNil(doc.link?.expiresAt)

        let req = try XCTUnwrap(StubProtocol.seen.first)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.path, "/api/v1/sigma/documents")
        XCTAssertEqual(req.url?.query, "mode=edit&ttl=3600")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sgm_test_abc")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Idempotency-Key"), "k1")
        let body = String(decoding: req.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains(#"name="file"; filename="small.csv""#), body)
        XCTAssertTrue(body.contains("Content-Type: text/csv"))
        XCTAssertTrue(body.contains("a,b\n1,2\n"))
        XCTAssertTrue(body.contains(#"name="title""#))
    }

    func testBlankAndLink() async throws {
        StubProtocol.handler = { req in
            req.url!.path.hasSuffix("/link")
                ? (200, Data(#"{"url":"https://cloud.example/v/sigma/2?sig=x","mode":"view","expires_at":"2026-10-18T21:29:59Z"}"#.utf8))
                : (201, Data(self.created.utf8))
        }
        _ = try await client.createBlank(title: "Budget", format: .xlsx)
        let blank = try XCTUnwrap(StubProtocol.seen.last)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: blank.httpBody!) as? [String: String], ["title": "Budget", "blank": "xlsx"])

        let link = try await client.link(for: 2, mode: .view, lifetime: 120)
        XCTAssertEqual(link.mode, .view)
        XCTAssertEqual(StubProtocol.seen.last?.url?.query, "mode=view&ttl=120")

        // A link for someone who should not have Vani.
        _ = try await client.link(for: 2, ai: false)
        XCTAssertEqual(StubProtocol.seen.last?.url?.query, "mode=edit&ai=off")
    }

    func testErrors() async {
        StubProtocol.handler = { _ in (402, Data(#"{"error":"This month's allowance of 50 documents is used up."}"#.utf8)) }
        do {
            _ = try await client.upload(Data(), filename: "x.csv")
            XCTFail("expected a quota error")
        } catch {
            XCTAssertEqual(error as? SigmaError, .quotaExceeded("This month's allowance of 50 documents is used up."))
        }
        StubProtocol.handler = { _ in (404, Data(#"{"error":"Document not found"}"#.utf8)) }
        do {
            _ = try await client.content(of: 9)
            XCTFail("expected not found")
        } catch {
            XCTAssertEqual(error as? SigmaError, .notFound("Document not found"))
            XCTAssertEqual(StubProtocol.seen.last?.url?.path, "/api/v1/sigma/documents/9/content")
        }
    }
}
