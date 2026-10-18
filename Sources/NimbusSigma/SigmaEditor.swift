import Foundation
import WebKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// One open Sigma sheet: the full spreadsheet editor (formulas, formatting,
/// charts, several sheets, Vani AI where the account has it), running in a
/// web view and saving every change back to the document.
///
/// Give it a signed link your server minted with its Sigma key:
///
/// ```swift
/// @StateObject var editor = SigmaEditor(link: url) {
///     try await MyAPI.freshSheetLink(id: 42)   // asked only when a link expires
/// }
///
/// var body: some View {
///     SigmaEditorView(editor: editor)
/// }
/// ```
///
/// The sheet saves itself a moment after each change. ``save()`` forces it,
/// and ``export(_:)`` hands you the file.
@MainActor
public final class SigmaEditor: NSObject, ObservableObject {
    /// Where the editor is in opening the sheet.
    public enum Phase: Equatable {
        case loading
        case ready
        case failed(SigmaError)
    }

    @Published public private(set) var phase: Phase = .loading
    /// The open sheet, once it is ready.
    @Published public private(set) var document: SigmaEditorDocument?
    @Published public private(set) var title: String = ""
    /// True from a change until it has been saved.
    @Published public private(set) var hasUnsavedChanges = false
    @Published public private(set) var lastSaved: Date?
    /// The last failure the sheet reported while open (a save that did not go through, say).
    @Published public private(set) var lastError: SigmaError?

    /// Every event the sheet sends, for apps that want more than the published state.
    public var onEvent: ((SigmaEvent) -> Void)?

    /// The web view the sheet runs in. ``SigmaEditorView`` and
    /// ``SigmaEditorViewController`` show it; use it directly to place it yourself.
    public let webView: WKWebView

    private var link: URL?
    private let refreshLink: (() async throws -> URL)?
    private var refreshedForThisLoad = false
    private var started = false

    /// - Parameters:
    ///   - link: A signed link from `POST /api/v1/sigma/documents/:id/link`.
    ///   - refreshLink: Asked for a fresh link when this one has expired or
    ///     the editing session it started (eight hours) has ended. Without it
    ///     an expired link fails with ``SigmaError/linkExpired(_:)``.
    public init(link: URL, refreshLink: (() async throws -> URL)? = nil) {
        self.link = link
        self.refreshLink = refreshLink
        self.webView = WKWebView(frame: .zero, configuration: SigmaEditor.configuration())
        super.init()
        wire()
    }

    /// An editor that asks for its first link too, so the app never holds one
    /// longer than it takes to open it.
    public init(link: @escaping () async throws -> URL) {
        self.link = nil
        self.refreshLink = link
        self.webView = WKWebView(frame: .zero, configuration: SigmaEditor.configuration())
        super.init()
        wire()
    }

    /// Opens the sheet. The views call this when they first appear; call it
    /// yourself only when you place ``webView`` on your own.
    public func start() {
        guard !started else { return }
        started = true
        if let link { open(link) } else { Task { await refresh(reason: nil) } }
    }

    /// Opens the sheet again from a fresh link, discarding the page (not the document).
    public func reload() {
        started = true
        if refreshLink != nil {
            Task { await refresh(reason: nil) }
        } else if let link {
            open(link)
        }
    }

    // MARK: Commands

    /// Saves every change now. Throws for a view-only link.
    public func save() async throws {
        _ = try await call("save")
    }

    /// The sheet as a file: the whole workbook as .xlsx, or the sheet on screen as CSV.
    public func export(_ format: SigmaFormat = .xlsx) async throws -> SigmaFile {
        guard let out = try await call("export", ["format": format.rawValue]) as? [String: Any],
              let b64 = out["base64"] as? String, let data = Data(base64Encoded: b64) else {
            throw SigmaError.editor("The sheet could not be exported.")
        }
        return SigmaFile(data: data, filename: out["filename"] as? String ?? "sheet.\(format.fileExtension)", format: format)
    }

    /// Undoes the last change. Returns false when there was nothing to undo.
    @discardableResult
    public func undo() async throws -> Bool {
        try await call("undo") as? Bool ?? false
    }

    /// Redoes the last undone change. Returns false when there was nothing to redo.
    @discardableResult
    public func redo() async throws -> Bool {
        try await call("redo") as? Bool ?? false
    }

    /// Fills in cells, as one undo step: `["A1": "Total", "B1": "=SUM(B2:B9)"]`.
    /// Values are what a person would type — numbers, text, or formulas
    /// starting with `=`. `sheet` defaults to the one on screen.
    public func setCells(_ cells: [String: String], sheet: String? = nil) async throws {
        var args: [String: Any] = ["cells": cells]
        if let sheet { args["sheet"] = sheet }
        _ = try await call("setCells", args)
    }

    /// What a range shows, with formulas computed: rows of numbers, strings,
    /// booleans, or error codes such as `"#DIV/0!"`. Empty cells are `""`.
    public func values(_ range: String, sheet: String? = nil) async throws -> [[SigmaValue]] {
        var args: [String: Any] = ["range": range]
        if let sheet { args["sheet"] = sheet }
        let rows = (try await call("values", args) as? [String: Any])?["rows"] as? [[Any]] ?? []
        return rows.map { $0.map(SigmaValue.init) }
    }

    /// The names of the workbook's sheets, in order.
    public func sheetNames() async throws -> [String] {
        (try await call("state") as? [String: Any])?["sheets"] as? [String] ?? []
    }

    private func call(_ command: String, _ args: [String: Any] = [:]) async throws -> Any? {
        guard phase == .ready else { throw SigmaError.notReady }
        do {
            return try await webView.callAsyncJavaScript(
                "return await window.sigma[command](args);",
                arguments: ["command": command, "args": args],
                contentWorld: .page
            )
        } catch {
            let ns = error as NSError
            let message = ns.userInfo["WKJavaScriptExceptionMessage"] as? String ?? ns.localizedDescription
            throw SigmaError.editor(message.replacingOccurrences(of: "Error: ", with: ""))
        }
    }

    // MARK: Internals

    private static func configuration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        #if os(iOS)
        config.allowsInlineMediaPlayback = true
        #endif
        return config
    }

    private func wire() {
        webView.configuration.userContentController.add(WeakHandler(self), contentWorld: .page, name: "sigma")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        #if os(iOS)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        #endif
        #if DEBUG
        if #available(iOS 16.4, macOS 13.3, *) { webView.isInspectable = true }
        #endif
    }

    private func open(_ url: URL) {
        link = url
        refreshedForThisLoad = false
        phase = .loading
        document = nil
        webView.load(URLRequest(url: url))
    }

    private func refresh(reason: SigmaError?) async {
        guard let refreshLink else {
            if let reason { phase = .failed(reason) }
            return
        }
        phase = .loading
        do {
            let url = try await refreshLink()
            open(url)
            if reason != nil { refreshedForThisLoad = true }
        } catch {
            phase = .failed(reason ?? .network(error.localizedDescription))
        }
    }

    fileprivate func receive(_ body: Any) {
        guard let event = SigmaEvent.decode(body) else { return }
        switch event {
        case let .ready(doc):
            document = doc
            title = doc.title
            hasUnsavedChanges = false
            lastError = nil
            phase = .ready
        case .changed:
            hasUnsavedChanges = true
        case let .saved(at, _, _):
            hasUnsavedChanges = false
            lastSaved = at ?? Date()
            lastError = nil
        case let .titleChanged(t):
            title = t
        case let .error(status, message):
            let err = SigmaEditor.error(status: status, message: message)
            if phase == .ready {
                lastError = err
                // The session ended mid-edit: open the sheet again from a fresh link.
                if status == 410, refreshLink != nil { Task { await refresh(reason: err) } }
            }
        }
        onEvent?(event)
    }

    nonisolated static func error(status: Int, message: String) -> SigmaError {
        switch status {
        case 410: return .linkExpired(message)
        case 403: return .linkInvalid(message)
        case 0: return .network(message)
        default: return .server(status: status, message: message)
        }
    }

    fileprivate func openOutside(_ url: URL) {
        #if canImport(UIKit) && !os(watchOS)
        UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }
}

// MARK: - Navigation

extension SigmaEditor: WKNavigationDelegate, WKUIDelegate {
    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        guard navigationResponse.isForMainFrame, let http = navigationResponse.response as? HTTPURLResponse, http.statusCode >= 400 else {
            return .allow
        }
        let status = http.statusCode
        let err: SigmaError = status == 410
            ? .linkExpired("This link has expired.")
            : status == 403 ? .linkInvalid("This link is not valid or was revoked.") : .server(status: status, message: "The sheet could not be opened.")
        // An expired link gets one fresh try; the page explains anything else.
        if (status == 410 || status == 403), refreshLink != nil, !refreshedForThisLoad {
            refreshedForThisLoad = true
            Task { await refresh(reason: err) }
            return .cancel
        }
        phase = .failed(err)
        return .allow
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Links in the sheet (in a cell, or in an AI answer) open in the browser, not over the sheet.
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            openOutside(url)
            return .cancel
        }
        return .allow
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if phase == .loading { phase = .failed(.network(error.localizedDescription)) }
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let ns = error as NSError
        // A cancelled load is one this editor replaced on purpose.
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return }
        if phase == .loading { phase = .failed(.network(error.localizedDescription)) }
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // The system reclaimed the page; saved work is in the document, so open it again.
        reload()
    }

    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { openOutside(url) }
        return nil
    }
}

/// WKUserContentController holds its handlers strongly; this keeps it from
/// holding the editor alive.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var editor: SigmaEditor?
    init(_ editor: SigmaEditor) { self.editor = editor }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        MainActor.assumeIsolated { editor?.receive(body) }
    }
}
