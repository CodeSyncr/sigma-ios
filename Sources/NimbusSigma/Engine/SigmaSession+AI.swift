import Foundation

/// One turn in a conversation with Vani AI.
public struct SigmaAIMessage: Identifiable, Hashable, Sendable {
    public enum Role: String, Sendable { case user, assistant }

    public let id = UUID()
    public let role: Role
    public let text: String
    /// The change Vani AI proposes, as Sigma's patch JSON; applied only when the person says so.
    public let patch: String?
    /// "12 cells · 3 formats · 1 chart".
    public let patchSummary: String?
    /// Set once the patch has been applied, so it cannot be applied twice.
    public var applied: String?

    public init(role: Role, text: String, patch: String? = nil, patchSummary: String? = nil) {
        self.role = role
        self.text = text
        self.patch = patch
        self.patchSummary = patchSummary
    }
}

extension SigmaSession {
    /// Asks Vani AI about the open sheet. The answer may carry a patch, which
    /// ``SigmaWorkbook/applyPatch(_:sheet:)`` applies as one undo step. Uses the
    /// document owner's plan; ``aiAvailable`` says whether they have it.
    public func ask(_ prompt: String, history: [SigmaAIMessage] = [], selection: SigmaSelection? = nil) async throws -> SigmaAIMessage {
        guard let book = workbook, let access = currentAccess else { throw SigmaError.notReady }
        let context = book.aiContext()
        let body: [String: Any] = [
            "prompt": prompt,
            "workbook_title": title,
            "sheet_name": book.sheets.indices.contains(book.activeSheet) ? book.sheets[book.activeSheet].name : "",
            "sheets": book.sheets.map(\.name),
            "selection": selection?.description ?? "",
            "grid": context.grid,
            "used_range": context.used,
            "history": history.suffix(10).map { ["role": $0.role.rawValue, "text": $0.text] },
            "chart_mode": "auto",
        ]
        var req = embedRequest(access, "/ai", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Building a whole sheet is a long generation.
        req.timeoutInterval = 240
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await sendEmbed(req)
        guard let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw SigmaError.server(status: 200, message: "Vani AI sent an answer this version cannot read.")
        }
        let reply = answer["reply"] as? String ?? "Done."
        var patch: String?
        if let ops = answer["ops"] as? [String: Any], !ops.isEmpty,
           let json = try? JSONSerialization.data(withJSONObject: ops) {
            patch = String(data: json, encoding: .utf8)
        }
        return SigmaAIMessage(role: .assistant, text: reply, patch: patch, patchSummary: patch.map { book.describePatch($0) })
    }
}
