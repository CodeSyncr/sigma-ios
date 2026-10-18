import SwiftUI
import WebKit

/// Shows a ``SigmaEditor``: the sheet, a spinner while it opens, and what
/// went wrong when it cannot.
///
/// ```swift
/// struct SheetScreen: View {
///     @StateObject var editor: SigmaEditor
///
///     var body: some View {
///         SigmaEditorView(editor: editor)
///             .navigationTitle(editor.title)
///             .toolbar {
///                 Button("Export") { Task { file = try await editor.export(.xlsx) } }
///             }
///     }
/// }
/// ```
public struct SigmaEditorView: View {
    @ObservedObject private var editor: SigmaEditor

    public init(editor: SigmaEditor) {
        self.editor = editor
    }

    public var body: some View {
        ZStack {
            SigmaWebView(webView: editor.webView)
                .opacity(editor.phase == .ready ? 1 : 0)
            switch editor.phase {
            case .loading:
                ProgressView()
            case .ready:
                EmptyView()
            case let .failed(error):
                VStack(spacing: 12) {
                    Image(systemName: "tablecells.badge.ellipsis")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(.secondary)
                    Text(error.errorDescription ?? "The sheet could not be opened.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Try again") { editor.reload() }
                        .buttonStyle(.bordered)
                }
                .padding(32)
            }
        }
        .onAppear { editor.start() }
    }
}

#if canImport(UIKit)
import UIKit

/// The web view as a SwiftUI view.
struct SigmaWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

/// A ``SigmaEditor`` for UIKit apps.
///
/// ```swift
/// let editor = SigmaEditor(link: url) { try await api.freshLink(id) }
/// navigationController?.pushViewController(SigmaEditorViewController(editor: editor), animated: true)
/// ```
public final class SigmaEditorViewController: UIViewController {
    public let editor: SigmaEditor

    public init(editor: SigmaEditor) {
        self.editor = editor
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: SigmaEditorView(editor: editor))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }
}
#elseif canImport(AppKit)
import AppKit

/// The web view as a SwiftUI view.
struct SigmaWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
#endif
