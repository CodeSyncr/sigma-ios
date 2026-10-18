import Foundation

/// The sheet an editor has open, as the sheet described itself when it was ready.
public struct SigmaEditorDocument: Sendable, Hashable {
    public let id: Int
    public let title: String
    public let filename: String
    public let format: SigmaFormat
    public let mode: SigmaLinkMode
}

/// Something the open sheet reported.
public enum SigmaEvent: Sendable, Equatable {
    /// The sheet is open and accepts commands.
    case ready(SigmaEditorDocument)
    /// The person changed something; it will be saved within a couple of seconds.
    case changed
    /// Every change so far is saved back to the document.
    case saved(at: Date?, size: Int?, checksum: String?)
    /// The sheet was renamed.
    case titleChanged(String)
    /// Something failed. `status` is the HTTP status when there was one:
    /// 410 means the link or the editing session has expired, 403 that it is
    /// not valid, 0 that the network failed.
    case error(status: Int, message: String)

    /// Reads one message posted by the sheet, or nil for one this version does not know.
    static func decode(_ body: Any) -> SigmaEvent? {
        guard let m = body as? [String: Any], m["source"] as? String == "nimbus-docs", let type = m["type"] as? String else {
            return nil
        }
        switch type {
        case "ready":
            guard let d = m["document"] as? [String: Any], let id = int(d["id"]) else { return nil }
            return .ready(SigmaEditorDocument(
                id: id,
                title: d["title"] as? String ?? "",
                filename: d["filename"] as? String ?? "",
                format: (d["format"] as? String).flatMap(SigmaFormat.init(rawValue:)) ?? .csv,
                mode: (d["mode"] as? String).flatMap(SigmaLinkMode.init(rawValue:)) ?? .view
            ))
        case "change":
            return .changed
        case "saved":
            return .saved(at: (m["at"] as? String).flatMap(Dates.parse), size: int(m["size"]), checksum: m["checksum"] as? String)
        case "title":
            return .titleChanged(m["title"] as? String ?? "")
        case "error":
            return .error(status: int(m["status"]) ?? 0, message: m["message"] as? String ?? "Something went wrong.")
        default:
            return nil
        }
    }

    private static func int(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let n = v as? NSNumber { return n.intValue }
        return nil
    }
}
