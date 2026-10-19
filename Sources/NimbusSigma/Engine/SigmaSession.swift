import Foundation
import CryptoKit

/// One sheet from the Sigma API, open natively: the signed link your server
/// minted becomes a ``SigmaWorkbook`` here, and every change is saved back to
/// the document — the file in its own format, and Sigma's workbook beside it.
///
/// ```swift
/// @StateObject var session = SigmaSession { try await MyAPI.sheetLink(id: 42) }
/// ```
@MainActor
public final class SigmaSession: ObservableObject {
    public enum Phase: Equatable {
        case loading
        case ready
        case failed(SigmaError)
    }

    /// The sheet that is open, as Sigma described it.
    public struct Document: Sendable, Hashable {
        public let id: Int
        public let title: String
        public let filename: String
        /// The format the file is kept in; every save rewrites it in this format.
        public let format: SigmaFormat
        /// Whether the link can edit, or only view.
        public let mode: SigmaLinkMode
        /// Opened with a test-mode API key (capped, and deleted after a week).
        public let test: Bool
    }

    public enum SaveState: Equatable {
        case saved
        case unsaved
        case saving
        case failed(SigmaError)
    }

    @Published public private(set) var phase: Phase = .loading
    @Published public private(set) var workbook: SigmaWorkbook?
    @Published public private(set) var document: Document?
    @Published public var title: String = "" {
        didSet { if oldValue != title, phase == .ready { scheduleSave() } }
    }
    @Published public private(set) var saveState: SaveState = .saved
    @Published public private(set) var lastSaved: Date?
    /// Whether the document's owner can use Vani AI here.
    @Published public private(set) var aiAvailable = false

    /// Seconds between the last change and the save.
    public var saveDelay: TimeInterval = 1.2

    private let linkProvider: () async throws -> URL
    private let session: URLSession
    private var access: Access?
    private var saveTask: Task<Void, Never>?
    private var started = false

    /// Where the editor's API lives, and the token that opens it.
    struct Access: Equatable {
        let base: URL
        let id: Int
        let token: String
    }

    /// - Parameter link: Asked for a signed link when the sheet opens, and
    ///   again when one expires. Your server mints it with its Sigma key.
    public init(session: URLSession = .shared, link: @escaping () async throws -> URL) {
        self.linkProvider = link
        self.session = session
    }

    /// Opens the sheet. ``SigmaSheetView`` calls this when it appears.
    public func start() {
        guard !started else { return }
        started = true
        Task { await open() }
    }

    /// Opens the sheet again from a fresh link.
    public func reload() {
        started = true
        Task { await open() }
    }

    /// Saves now, without waiting for the pause after typing.
    public func save() async throws {
        saveTask?.cancel()
        try await persist()
    }

    // MARK: Opening

    private func open() async {
        phase = .loading
        do {
            let access = try await resolve()
            self.access = access
            struct Info: Decodable {
                struct Engine: Decodable { let version: String; let sha256: String }
                let id: Int
                let title: String
                let filename: String
                let format: String
                let mode: String
                let ai: Bool
                let data: String
                let test: Bool?
                let engine: Engine?
            }
            let info: Info = try await get(access, "")
            guard let expected = info.engine else {
                throw SigmaError.server(status: 200, message: "This Sigma server is too old for NimbusSigma \(NimbusSigma.version).")
            }
            let engine = try await loadEngine(access, version: expected.version, sha256: expected.sha256)
            let format = SigmaFormat(rawValue: info.format) ?? .csv
            let book: SigmaWorkbook
            if info.data.isEmpty {
                let file: Data = try await getData(access, "/source")
                book = try await SigmaWorkbook.importing(file, format: format, name: info.filename, engine: engine)
            } else {
                book = try SigmaWorkbook(engine: engine, json: info.data)
            }
            let mode = SigmaLinkMode(rawValue: info.mode) ?? .view
            book.onChange = { [weak self] in self?.scheduleSave() }
            document = Document(id: info.id, title: info.title, filename: info.filename, format: format, mode: mode, test: info.test ?? false)
            workbook = book
            title = info.title
            aiAvailable = info.ai
            saveState = .saved
            phase = .ready
        } catch let e as SigmaError {
            phase = .failed(e)
        } catch {
            phase = .failed(.network(error.localizedDescription))
        }
    }

    /// Follows the signed link to the cloud, which checks it and answers with
    /// a redirect to Sigma carrying an editing token.
    private func resolve() async throws -> Access {
        let link = try await linkProvider()
        var req = URLRequest(url: link)
        req.setValue("nimbus-sigma-swift/\(NimbusSigma.version)", forHTTPHeaderField: "User-Agent")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req, delegate: StopAtRedirect())
        } catch {
            throw SigmaError.network(error.localizedDescription)
        }
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        guard (300..<400).contains(status), let location = http?.value(forHTTPHeaderField: "Location"),
              let target = URL(string: location, relativeTo: link)?.absoluteURL,
              let access = SigmaSession.access(from: target) else {
            switch status {
            case 402: throw SigmaError.quotaExceeded("This account has used this month's allowance of sheet opens (or a test key's cap). Its owner can upgrade on Nimbus Cloud.")
            case 410: throw SigmaError.linkExpired("This link has expired.")
            case 403: throw SigmaError.linkInvalid("This link is not valid or was revoked.")
            case 404: throw SigmaError.notFound("This sheet does not exist or was deleted.")
            default:
                _ = data
                throw SigmaError.server(status: status, message: "The link did not open a Sigma sheet.")
            }
        }
        return access
    }

    /// Sigma's engine for this session: downloaded from Sigma with the
    /// session's token and checked against the checksum Sigma reported. It
    /// is kept in memory only, never written to disk.
    private func loadEngine(_ a: Access, version: String, sha256: String) async throws -> String {
        if let cached = EngineCache.source(version: version, sha256: sha256) { return cached }
        let data = try await getData(a, "/engine")
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == sha256.lowercased(), let source = String(data: data, encoding: .utf8) else {
            throw SigmaError.engine("The Sigma engine did not arrive intact. Try again.")
        }
        EngineCache.store(source, version: version, sha256: sha256)
        return source
    }

    /// Reads ".../embed/<id>?t=<token>".
    static func access(from url: URL) -> Access? {
        let parts = url.pathComponents
        guard let i = parts.lastIndex(of: "embed"), i + 1 < parts.count, let id = Int(parts[i + 1]),
              let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "t" })?.value,
              var base = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        base.path = parts[1..<i].isEmpty ? "" : "/" + parts[1..<i].joined(separator: "/")
        base.query = nil
        guard let root = base.url else { return nil }
        return Access(base: root, id: id, token: token)
    }

    // MARK: Saving

    private func scheduleSave() {
        guard document?.mode == .edit else { return }
        saveState = .unsaved
        saveTask?.cancel()
        let delay = saveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            try? await self?.persist()
        }
    }

    private func persist(retried: Bool = false) async throws {
        guard let workbook, let document, let access else { throw SigmaError.notReady }
        guard document.mode == .edit else { throw SigmaError.editor("This link can view the sheet but not change it.") }
        let revision = workbook.revision
        saveState = .saving
        do {
            let file = try await workbook.export(document.format)
            var req = request(access, "", method: "PUT")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "title": title, "data": workbook.serialize(), "file": file.base64EncodedString(),
            ])
            _ = try await send(req)
            lastSaved = Date()
            // Changes made while the request was out are still unsaved.
            saveState = workbook.revision == revision ? .saved : .unsaved
            if saveState == .unsaved { scheduleSave() }
        } catch SigmaError.linkExpired(let m) where !retried {
            // The editing session ended (it lasts eight hours): get a fresh
            // token and save again. The workbook in memory is kept.
            do {
                self.access = try await resolve()
                try await persist(retried: true)
            } catch {
                saveState = .failed(error as? SigmaError ?? .linkExpired(m))
                throw error
            }
        } catch {
            let e = error as? SigmaError ?? .network(error.localizedDescription)
            saveState = .failed(e)
            throw e
        }
    }

    // MARK: HTTP

    var currentAccess: Access? { access }
    func embedRequest(_ a: Access, _ path: String, method: String) -> URLRequest { request(a, path, method: method) }
    func sendEmbed(_ req: URLRequest) async throws -> Data { try await send(req) }

    /// The sheet as a file in the format it is kept in (or another), named after its title.
    public func export(_ format: SigmaFormat? = nil) async throws -> SigmaFile {
        guard let workbook, let document else { throw SigmaError.notReady }
        let f = format ?? document.format
        let data = try await workbook.export(f)
        let base = (title.isEmpty ? document.filename : title)
            .replacingOccurrences(of: #"\.(xlsx|xlsm|csv)$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "/", with: "-")
        return SigmaFile(data: data, filename: base + "." + f.fileExtension, format: f)
    }

    private func request(_ a: Access, _ path: String, method: String = "GET") -> URLRequest {
        var req = URLRequest(url: a.base.appendingPathComponent("api/embed/\(a.id)" + path))
        req.httpMethod = method
        req.setValue(a.token, forHTTPHeaderField: "X-Sigma-Embed")
        req.setValue("nimbus-sigma-swift/\(NimbusSigma.version)", forHTTPHeaderField: "User-Agent")
        return req
    }

    private func get<T: Decodable>(_ a: Access, _ path: String) async throws -> T {
        let data = try await send(request(a, path))
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SigmaError.server(status: 200, message: "Sigma sent an answer this version cannot read.")
        }
    }

    private func getData(_ a: Access, _ path: String) async throws -> Data {
        try await send(request(a, path))
    }

    private func send(_ req: URLRequest) async throws -> Data {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw SigmaError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? String ?? ""
            throw SigmaError.from(status: status, message: message.isEmpty ? "Sigma answered \(status)." : message)
        }
        return data
    }
}

/// Keeps a request from following the redirect, so its Location can be read.
private final class StopAtRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}

/// The engine sessions downloaded in this process, by version: in memory
/// only, so it is fetched again with a valid session after every launch.
@MainActor
enum EngineCache {
    private static var entry: (version: String, sha256: String, source: String)?

    static func source(version: String, sha256: String) -> String? {
        guard let e = entry, e.version == version, e.sha256 == sha256 else { return nil }
        return e.source
    }

    static func store(_ source: String, version: String, sha256: String) {
        entry = (version, sha256, source)
    }
}
