import Foundation

/// The file format a Sigma sheet is kept in. Every save in the editor
/// rewrites the document's file in its own format, so what you uploaded is
/// what you download — with the edits.
public enum SigmaFormat: String, Sendable, Codable, CaseIterable {
    case xlsx
    case csv

    public var mimeType: String {
        switch self {
        case .xlsx: return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case .csv: return "text/csv"
        }
    }

    public var fileExtension: String { rawValue }
}

/// What a signed link lets the person holding it do.
public enum SigmaLinkMode: String, Sendable, Codable {
    /// Read the sheet; no editing and no saving.
    case view
    /// Edit the sheet; every change is saved back to the document.
    case edit
}

/// A spreadsheet stored in Nimbus Cloud through the Sigma API.
public struct SigmaDocument: Sendable, Codable, Identifiable, Hashable {
    public let id: Int
    public let title: String
    public let filename: String
    public let mime: String
    public let size: Int
    public let checksum: String
    public let createdAt: Date
    public let expiresAt: Date?
    /// A signed link, when the call that returned the document minted one.
    public let link: SigmaLink?

    enum CodingKeys: String, CodingKey {
        case id, title, filename, mime, size, checksum, url, mode
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case urlExpiresAt = "url_expires_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        filename = try c.decodeIfPresent(String.self, forKey: .filename) ?? ""
        mime = try c.decodeIfPresent(String.self, forKey: .mime) ?? ""
        size = try c.decodeIfPresent(Int.self, forKey: .size) ?? 0
        checksum = try c.decodeIfPresent(String.self, forKey: .checksum) ?? ""
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        if let url = try c.decodeIfPresent(URL.self, forKey: .url) {
            link = SigmaLink(
                url: url,
                mode: try c.decodeIfPresent(SigmaLinkMode.self, forKey: .mode) ?? .view,
                expiresAt: try c.decodeIfPresent(Date.self, forKey: .urlExpiresAt) ?? .distantFuture
            )
        } else {
            link = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(filename, forKey: .filename)
        try c.encode(mime, forKey: .mime)
        try c.encode(size, forKey: .size)
        try c.encode(checksum, forKey: .checksum)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(expiresAt, forKey: .expiresAt)
        try c.encodeIfPresent(link?.url, forKey: .url)
        try c.encodeIfPresent(link?.mode, forKey: .mode)
        try c.encodeIfPresent(link?.expiresAt, forKey: .urlExpiresAt)
    }

    /// The format the document is kept in, from its file name and type.
    public var format: SigmaFormat {
        let name = filename.lowercased()
        return name.hasSuffix(".xlsx") || name.hasSuffix(".xlsm") || mime.contains("spreadsheetml") ? .xlsx : .csv
    }
}

/// A signed link to a document. It is a door, not a leash: the link only has
/// to be valid when the editor opens it, and an editing session it starts
/// lasts eight hours.
public struct SigmaLink: Sendable, Codable, Hashable {
    public let url: URL
    public let mode: SigmaLinkMode
    public let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case url, mode
        case expiresAt = "expires_at"
    }

    public init(url: URL, mode: SigmaLinkMode, expiresAt: Date) {
        self.url = url
        self.mode = mode
        self.expiresAt = expiresAt
    }
}

/// This month's document allowance.
public struct SigmaUsage: Sendable, Codable, Hashable {
    public let period: String
    public let limit: Int
    public let used: Int
    public let remaining: Int
    public let overage: Int
    public let allowed: Bool
    public let warn: Bool
    public let paid: Bool

    enum CodingKeys: String, CodingKey {
        case period, limit, used, remaining, overage, allowed, warn, paid
    }
}

/// What one cell shows.
public enum SigmaValue: Sendable, Hashable, CustomStringConvertible {
    case number(Double)
    case text(String)
    case bool(Bool)
    case empty

    init(_ raw: Any) {
        // JavaScript booleans arrive as NSNumber too; tell them apart first.
        if let n = raw as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) }
        else if let d = raw as? Double { self = .number(d) }
        else if let i = raw as? Int { self = .number(Double(i)) }
        else if let s = raw as? String { self = s.isEmpty ? .empty : .text(s) }
        else { self = .empty }
    }

    public var description: String {
        switch self {
        case let .number(d): return d.rounded() == d && abs(d) < 1e15 ? String(Int(d)) : String(d)
        case let .text(s): return s
        case let .bool(b): return b ? "TRUE" : "FALSE"
        case .empty: return ""
        }
    }
}

/// A sheet exported from the editor. Identifiable, so it can drive `.sheet(item:)`.
public struct SigmaFile: Sendable, Hashable, Identifiable {
    public let id = UUID()
    public let data: Data
    public let filename: String
    public let format: SigmaFormat

    public init(data: Data, filename: String, format: SigmaFormat) {
        self.data = data
        self.filename = filename
        self.format = format
    }
}

/// Everything that can go wrong, with the message Nimbus Cloud gave.
public enum SigmaError: Error, Sendable, Equatable, LocalizedError {
    /// The API key is missing, wrong or revoked (401).
    case unauthorized(String)
    /// This month's allowance is used up (402).
    case quotaExceeded(String)
    /// The document does not exist (404).
    case notFound(String)
    /// The link has expired, or the editing session it started has ended.
    case linkExpired(String)
    /// The link is not valid or was revoked.
    case linkInvalid(String)
    /// The editor answered a command with an error.
    case editor(String)
    /// The editor is not ready for commands yet.
    case notReady
    /// Sigma's spreadsheet engine refused or failed.
    case engine(String)
    /// Any other answer from the server.
    case server(status: Int, message: String)
    /// The request did not reach the server.
    case network(String)

    public var errorDescription: String? {
        switch self {
        case let .unauthorized(m), let .quotaExceeded(m), let .notFound(m), let .linkExpired(m),
             let .linkInvalid(m), let .editor(m), let .network(m), let .engine(m):
            return m
        case .notReady:
            return "The sheet is still opening."
        case let .server(status, m):
            return m.isEmpty ? "Nimbus Cloud answered \(status)." : m
        }
    }
}

extension SigmaError {
    /// The error an HTTP status from Nimbus Cloud or Sigma means.
    public static func from(status: Int, message: String) -> SigmaError {
        switch status {
        case 401: return .unauthorized(message)
        case 402: return .quotaExceeded(message)
        case 404: return .notFound(message)
        case 410: return .linkExpired(message)
        case 403: return .linkInvalid(message)
        case 0: return .network(message)
        default: return .server(status: status, message: message)
        }
    }
}

enum Dates {
    /// Nimbus Cloud writes RFC 3339 dates, usually with fractional seconds.
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = parse(raw) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a date: \(raw)"))
        }
        return d
    }

    static func parse(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: raw) { return d }
        return ISO8601DateFormatter().date(from: raw)
    }
}
