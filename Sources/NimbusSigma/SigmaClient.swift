import Foundation

/// The Sigma documents API: upload spreadsheets, mint signed links, and
/// download them again with their edits.
///
/// - Important: An `sgm_` key can read and delete every document on its
///   account, and anything compiled into an app can be pulled back out of
///   it. **Do not ship this client inside an iOS app.** Keep the key on your
///   server, mint links there, and hand the app only the link — which is all
///   ``SigmaSession`` needs. `SigmaClient` is for server-side Swift (Vapor,
///   Hummingbird), command-line tools, and prototypes.
public struct SigmaClient: Sendable {
    public let baseURL: URL
    private let apiKey: String
    private let session: URLSession

    /// - Parameters:
    ///   - apiKey: A Sigma key (`sgm_live_…` or `sgm_test_…`) from Nimbus
    ///     Cloud › API & CLI Keys.
    ///   - baseURL: Where Nimbus Cloud is served.
    public init(apiKey: String, baseURL: URL = URL(string: "https://nimbusgo.space")!, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: Documents

    /// Uploads a spreadsheet (.xlsx or .csv, up to 5 MB) and returns it with a signed link.
    ///
    /// - Parameters:
    ///   - idempotencyKey: Send the same key when retrying, and a retried
    ///     upload returns the original document instead of a second one.
    ///   - retainDays: Delete the document automatically after this many days.
    ///   - ai: Whether the returned link offers Vani (it still needs a plan that includes it).
    public func upload(
        _ data: Data,
        filename: String,
        title: String? = nil,
        mode: SigmaLinkMode = .edit,
        linkLifetime: TimeInterval? = nil,
        retainDays: Int? = nil,
        idempotencyKey: String? = nil,
        ai: Bool = true
    ) async throws -> SigmaDocument {
        let boundary = "sigma-" + UUID().uuidString
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        if let title { field("title", title) }
        let mime = filename.lowercased().hasSuffix(".csv") ? SigmaFormat.csv.mimeType : SigmaFormat.xlsx.mimeType
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename.replacingOccurrences(of: "\"", with: "'"))\"\r\nContent-Type: \(mime)\r\n\r\n")
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n")

        var req = request("documents", query: linkQuery(mode: mode, lifetime: linkLifetime, retainDays: retainDays, ai: ai), method: "POST")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let idempotencyKey { req.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key") }
        req.httpBody = body
        return try await send(req)
    }

    /// Creates an empty sheet, ready to open in the editor.
    public func createBlank(
        title: String,
        format: SigmaFormat = .xlsx,
        mode: SigmaLinkMode = .edit,
        linkLifetime: TimeInterval? = nil,
        retainDays: Int? = nil,
        ai: Bool = true
    ) async throws -> SigmaDocument {
        var req = request("documents", query: linkQuery(mode: mode, lifetime: linkLifetime, retainDays: retainDays, ai: ai), method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["title": title, "blank": format.rawValue])
        return try await send(req)
    }

    /// The account's most recent documents, newest first.
    public func documents(limit: Int = 50) async throws -> [SigmaDocument] {
        struct List: Decodable { let documents: [SigmaDocument] }
        let list: List = try await send(request("documents", query: [URLQueryItem(name: "limit", value: String(limit))]))
        return list.documents
    }

    /// One document's details.
    public func document(_ id: Int) async throws -> SigmaDocument {
        try await send(request("documents/\(id)"))
    }

    /// A fresh signed link for a document — what your server hands the app.
    ///
    /// - Parameters:
    ///   - lifetime: How long the link may be used to open the sheet: one
    ///     minute to seven days, fifteen minutes by default.
    ///   - ai: Whether the person the link is for gets Vani. Pass false for
    ///     someone who has not paid you for AI; it is signed into the link.
    ///     Vani also needs a Nimbus Cloud plan that includes it.
    public func link(for id: Int, mode: SigmaLinkMode = .edit, lifetime: TimeInterval? = nil, ai: Bool = true) async throws -> SigmaLink {
        try await send(request("documents/\(id)/link", query: linkQuery(mode: mode, lifetime: lifetime, retainDays: nil, ai: ai), method: "POST"))
    }

    /// The document's file as it is now, edits included, in its own format.
    public func content(of id: Int) async throws -> Data {
        try await raw(request("documents/\(id)/content"))
    }

    /// Sigma's own JSON for a sheet that has been opened in the editor: every
    /// sheet, formula, style and chart. Fails with a server error (409) for a
    /// sheet that has never been opened.
    public func workbook(of id: Int) async throws -> Data {
        try await raw(request("documents/\(id)/content", query: [URLQueryItem(name: "format", value: "workbook")]))
    }

    /// Deletes a document and its content.
    public func delete(_ id: Int) async throws {
        _ = try await raw(request("documents/\(id)", method: "DELETE"))
    }

    /// Invalidates every link minted so far for this account.
    public func revokeAllLinks() async throws {
        _ = try await raw(request("links/revoke", method: "POST"))
    }

    /// This month's allowance.
    public func usage() async throws -> SigmaUsage {
        try await send(request("usage"))
    }

    // MARK: Plumbing

    private func linkQuery(mode: SigmaLinkMode, lifetime: TimeInterval?, retainDays: Int?, ai: Bool) -> [URLQueryItem] {
        var q = [URLQueryItem(name: "mode", value: mode.rawValue)]
        if !ai { q.append(URLQueryItem(name: "ai", value: "off")) }
        if let lifetime { q.append(URLQueryItem(name: "ttl", value: String(Int(lifetime.rounded())))) }
        if let retainDays { q.append(URLQueryItem(name: "retain_days", value: String(retainDays))) }
        return q
    }

    func request(_ path: String, query: [URLQueryItem] = [], method: String = "GET") -> URLRequest {
        var comps = URLComponents(url: baseURL.appendingPathComponent("api/v1/sigma/" + path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("nimbus-sigma-swift/\(NimbusSigma.version)", forHTTPHeaderField: "User-Agent")
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let data = try await raw(req)
        do {
            return try Dates.decoder().decode(T.self, from: data)
        } catch {
            throw SigmaError.server(status: 200, message: "Nimbus Cloud sent an answer this version cannot read: \(error.localizedDescription)")
        }
    }

    private func raw(_ req: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw SigmaError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw SigmaClient.error(status: status, body: data) }
        return data
    }

    static func error(status: Int, body: Data) -> SigmaError {
        let message = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["error"] as? String ?? ""
        return SigmaError.from(status: status, message: message)
    }
}

/// Facts about the package itself.
public enum NimbusSigma {
    public static let version = "2.1.1"
}

extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
