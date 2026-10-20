#if canImport(UIKit)
import SwiftUI
import UIKit

/// A Sigma sheet, native: formula bar, grid and sheet tabs, opened from a
/// ``SigmaSession`` and saving as people edit.
///
/// ```swift
/// struct SheetScreen: View {
///     @StateObject var session = SigmaSession { try await MyAPI.sheetLink(id: 42) }
///
///     var body: some View {
///         SigmaSheetView(session: session)
///             .navigationTitle(session.title)
///     }
/// }
/// ```
public struct SigmaSheetView: View {
    @ObservedObject private var session: SigmaSession
    @StateObject private var ownController = SigmaGridController()
    private let external: SigmaGridController?
    private let header: SigmaHeader
    @Environment(\.dismiss) private var dismiss
    @State private var shared: SigmaFile?
    @State private var shareFailed: String?
    @State private var renaming = false
    @State private var newTitle = ""

    /// - Parameters:
    ///   - controller: Pass your own to read the selection or drive the grid
    ///     from your controls; one is kept for the view otherwise.
    ///   - header: What the header shows; ``SigmaHeader/hidden`` removes it.
    public init(session: SigmaSession, controller: SigmaGridController? = nil, header: SigmaHeader = .standard) {
        self.session = session
        self.external = controller
        self.header = header
    }

    private var controller: SigmaGridController { external ?? ownController }

    private var canEdit: Bool { session.phase == .ready && session.document?.mode == .edit }

    /// Where the sheet's edits are, as the header says it.
    private var status: String {
        switch session.phase {
        case .loading: return "Opening…"
        case .failed: return "Could not open"
        case .ready:
            guard canEdit else { return "View only" }
            switch session.saveState {
            case .saved: return "Saved"
            case .unsaved: return "Edited"
            case .saving: return "Saving…"
            case .failed: return "Not saved"
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            if header.isVisible {
                HeaderBar(
                    header: header,
                    title: session.title.isEmpty ? (session.document?.title ?? "") : session.title,
                    status: status,
                    canShare: canEdit,
                    canRename: canEdit,
                    back: { header.onBack?() ?? dismiss() },
                    rename: { newTitle = session.title; renaming = true },
                    share: { frame in
                        controller.showMenu([
                            SigmaMenuItem(title: "Excel workbook (.xlsx)", icon: .xlsx) { export(.xlsx) },
                            SigmaMenuItem(title: "CSV of this sheet", icon: .csv) { export(.csv) },
                        ], at: frame)
                    }
                )
                Divider()
            }
            content
        }
        .background(Color(uiColor: .systemBackground))
        .overlay { SigmaMenuLayer(controller: controller) }
        .background(EmptyView().sheet(item: $shared) { file in
            if let sheet = try? SigmaShareSheet(file: file) { sheet.ignoresSafeArea() }
        })
        .alert("The sheet could not be exported", isPresented: Binding(get: { shareFailed != nil }, set: { if !$0 { shareFailed = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(shareFailed ?? "") }
        .alert("Rename", isPresented: $renaming) {
            TextField("Name", text: $newTitle)
            Button("Rename") {
                let name = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, name != session.title { session.title = name }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { session.start() }
    }

    @ViewBuilder private var content: some View {
        switch session.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(error):
            VStack(spacing: 12) {
                Image(systemName: "tablecells.badge.ellipsis")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text(error.errorDescription ?? "The sheet could not be opened.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Try again") { session.reload() }.buttonStyle(.bordered)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            if let book = session.workbook {
                SheetEditor(session: session, book: book, controller: controller, readOnly: session.document?.mode != .edit)
            } else {
                Color.clear
            }
        }
    }

    private func export(_ format: SigmaFormat) {
        Task {
            do { shared = try await session.export(format) } catch { shareFailed = (error as? SigmaError)?.errorDescription ?? error.localizedDescription }
        }
    }
}

/// ``SigmaSheetView`` for UIKit apps. Its back arrow pops it, or closes it
/// when it was presented, unless the header has its own ``SigmaHeader/onBack``.
///
/// ```swift
/// let session = SigmaSession { try await MyAPI.sheetLink(id: 42) }
/// navigationController?.pushViewController(SigmaSheetViewController(session: session), animated: true)
/// ```
public final class SigmaSheetViewController: UIViewController {
    public let session: SigmaSession
    public let controller: SigmaGridController
    public let header: SigmaHeader

    public init(session: SigmaSession, controller: SigmaGridController? = nil, header: SigmaHeader = .standard) {
        self.session = session
        self.controller = controller ?? SigmaGridController()
        self.header = header
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        var header = header
        if header.onBack == nil {
            header.onBack = { [weak self] in
                guard let self else { return }
                if let nav = navigationController, nav.viewControllers.count > 1, nav.topViewController === self {
                    nav.popViewController(animated: true)
                } else {
                    dismiss(animated: true)
                }
            }
        }
        let host = UIHostingController(rootView: SigmaSheetView(session: session, controller: controller, header: header))
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

struct SheetEditor: View {
    @ObservedObject var session: SigmaSession
    @ObservedObject var book: SigmaWorkbook
    @ObservedObject var controller: SigmaGridController
    let readOnly: Bool

    var body: some View {
        VStack(spacing: 0) {
            FormulaBar(controller: controller, readOnly: readOnly)
            Divider()
            if session.document?.test == true {
                Label("Test mode — opened with a test API key. Use a live key in production.", systemImage: "testtube.2")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.54, green: 0.35, blue: 0))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Color(red: 1, green: 0.95, blue: 0.8))
            }
            if !readOnly {
                FormatBar(controller: controller)
                Divider()
            }
            if controller.panel == .find {
                FindBar(book: book, controller: controller, readOnly: readOnly)
                Divider()
            }
            if !controller.activeNote.isEmpty && !controller.isEditing {
                NoteBanner(note: controller.activeNote) { controller.panel = .note }
                Divider()
            }
            GridRepresentable(book: book, controller: controller, readOnly: readOnly)
                .overlay { if controller.aiAvailable { VaniBall(controller: controller) } }
            FormulaHelpStrip(book: book, controller: controller)
            Divider()
            SheetTabs(book: book, controller: controller, readOnly: readOnly)
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(item: Binding(get: { controller.panel == .find ? nil : controller.panel }, set: { controller.panel = $0 })) { panel in
            switch panel {
            case .note: NoteSheet(controller: controller, readOnly: readOnly)
            case .conditionalFormatting: ConditionalFormattingSheet(book: book, controller: controller, readOnly: readOnly)
            case .chart: ChartEditor(book: book, controller: controller)
            case .ai: VaniPanel(session: session, controller: controller)
            case .functions: FunctionsSheet(book: book, controller: controller)
            case .find: EmptyView()
            }
        }
        .onAppear { controller.aiAvailable = session.aiAvailable && !readOnly }
        .onChange(of: session.aiAvailable) { on in controller.aiAvailable = on && !readOnly }
    }
}

struct GridRepresentable: UIViewRepresentable {
    let book: SigmaWorkbook
    let controller: SigmaGridController
    let readOnly: Bool

    func makeUIView(context: Context) -> SigmaGridView {
        let grid = SigmaGridView(controller: controller)
        grid.show(book, readOnly: readOnly)
        return grid
    }

    func updateUIView(_ grid: SigmaGridView, context: Context) {
        grid.show(book, readOnly: readOnly)
    }
}

/// While a formula is typed: the functions a half-typed name could be, or the
/// syntax of the function being filled in with the current argument in bold.
struct FormulaHelpStrip: View {
    @ObservedObject var book: SigmaWorkbook
    @ObservedObject var controller: SigmaGridController

    var body: some View {
        let hint = controller.isEditing ? FormulaHint.of(controller.editText, functions: book.functions()) : .none
        switch hint {
        case .none:
            EmptyView()
        case let .suggest(_, matches):
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(matches) { f in
                        Button { controller.insertFunction(f.name) } label: {
                            Text(f.name)
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(GridColors.accent))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(uiColor: .systemBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(f.name): \(f.description)")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .background(Color(uiColor: .secondarySystemBackground))
        case let .arguments(fn, argument):
            Text(AttributedString(FormulaKeys.syntax(fn, argument: argument)))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(uiColor: .secondarySystemBackground))
        }
    }
}

/// The cell's name and what it holds; edit a formula here as well as in the cell.
struct FormulaBar: View {
    @ObservedObject var controller: SigmaGridController
    let readOnly: Bool
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(controller.selection.description)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 52, alignment: .leading)
            Rectangle().fill(Color(uiColor: .separator)).frame(width: 1, height: 20)
            Text("fx").font(.system(size: 13, weight: .regular, design: .serif)).italic().foregroundStyle(.tertiary)
            TextField("", text: Binding(
                get: { controller.isEditing ? controller.editText : controller.activeInput },
                set: { controller.edit($0) }
            ))
            .font(.system(size: 14, design: .monospaced))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($focused)
            .disabled(readOnly)
            .onSubmit { controller.commit() }
            if controller.isEditing {
                Button { controller.cancel() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .accessibilityLabel("Cancel")
                Button { controller.commit() } label: { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(GridColors.accent)) }
                    .accessibilityLabel("Done")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .onChange(of: focused) { now in if now { controller.formulaBarFocused() } }
        .onChange(of: controller.isEditing) { now in if !now { focused = false } }
    }
}

/// One sheet's tab: a tap opens it, a long press its menu.
private struct SheetTab: View {
    let name: String
    let on: Bool
    let select: () -> Void
    let menu: (CGRect) -> Void
    @State private var frame: CGRect = .zero

    var body: some View {
        Text(name)
            .font(.system(size: 13, weight: on ? .semibold : .regular))
            .foregroundStyle(on ? Color(GridColors.accent) : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(on ? Color(GridColors.headerSelected) : Color.clear, in: Capsule())
            .contentShape(Capsule())
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { frame = g.frame(in: .global) }
                    .onChange(of: g.frame(in: .global)) { frame = $0 }
            })
            .onTapGesture(perform: select)
            .onLongPressGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                menu(frame)
            }
            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(named: "Sheet options") { menu(frame) }
    }
}

/// Sheets along the bottom, with undo and redo.
struct SheetTabs: View {
    @ObservedObject var book: SigmaWorkbook
    @ObservedObject var controller: SigmaGridController
    let readOnly: Bool
    @State private var renaming: Int?
    @State private var newName = ""

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(book.sheets.enumerated()), id: \.offset) { i, sheet in
                        SheetTab(name: sheet.name, on: i == book.activeSheet) {
                            book.selectSheet(i)
                        } menu: { frame in
                            guard !readOnly else { return }
                            let count = book.sheets.count
                            controller.showMenu([
                                SigmaMenuItem(title: "Rename", icon: .rename) { newName = sheet.name; renaming = i },
                                SigmaMenuItem(title: "Duplicate", icon: .duplicate) { _ = try? book.duplicateSheet(i) },
                                SigmaMenuItem(title: "Move left", icon: .moveLeft, enabled: i > 0) { try? book.moveSheet(from: i, to: i - 1) },
                                SigmaMenuItem(title: "Move right", icon: .moveRight, enabled: i < count - 1) { try? book.moveSheet(from: i, to: i + 1) },
                                SigmaMenuItem(title: "Delete", icon: .delete, destructive: true, enabled: count > 1) { try? book.deleteSheet(i) },
                            ], at: frame)
                        }
                    }
                    if !readOnly {
                        Button { _ = try? book.addSheet() } label: {
                            Image(systemName: "plus").font(.system(size: 14, weight: .medium)).padding(8)
                        }
                        .accessibilityLabel("Add sheet")
                    }
                }
                .padding(.horizontal, 8)
            }
            if !readOnly {
                Button { controller.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .accessibilityLabel("Undo")
                Button { controller.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .accessibilityLabel("Redo")
                    .padding(.trailing, 12)
            }
        }
        .frame(height: 44)
        .alert("Rename sheet", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { if let i = renaming { try? book.renameSheet(i, to: newName) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: {
            Text("Formulas that use this sheet are updated to the new name.")
        }
    }
}
#endif
