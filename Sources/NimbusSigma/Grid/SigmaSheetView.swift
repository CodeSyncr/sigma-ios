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

    /// - Parameter controller: Pass your own to read the selection or drive
    ///   the grid from your controls; one is kept for the view otherwise.
    public init(session: SigmaSession, controller: SigmaGridController? = nil) {
        self.session = session
        self.external = controller
    }

    private var controller: SigmaGridController { external ?? ownController }

    public var body: some View {
        Group {
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
                }
            }
        }
        .onAppear { session.start() }
    }
}

/// ``SigmaSheetView`` for UIKit apps.
///
/// ```swift
/// let session = SigmaSession { try await MyAPI.sheetLink(id: 42) }
/// navigationController?.pushViewController(SigmaSheetViewController(session: session), animated: true)
/// ```
public final class SigmaSheetViewController: UIViewController {
    public let session: SigmaSession
    public let controller: SigmaGridController

    public init(session: SigmaSession, controller: SigmaGridController? = nil) {
        self.session = session
        self.controller = controller ?? SigmaGridController()
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: SigmaSheetView(session: session, controller: controller))
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
    @State private var shared: SigmaFile?
    @State private var shareFailed: String?

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
                FormatBar(controller: controller) { format in
                    Task {
                        do { shared = try await session.export(format) } catch { shareFailed = (error as? SigmaError)?.errorDescription ?? error.localizedDescription }
                    }
                }
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
            case .find: EmptyView()
            }
        }
        .background(EmptyView().sheet(item: $shared) { file in
            if let sheet = try? SigmaShareSheet(file: file) { sheet.ignoresSafeArea() }
        })
        .alert("The sheet could not be exported", isPresented: Binding(get: { shareFailed != nil }, set: { if !$0 { shareFailed = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(shareFailed ?? "") }
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
                        let on = i == book.activeSheet
                        Button { book.selectSheet(i) } label: {
                            Text(sheet.name)
                                .font(.system(size: 13, weight: on ? .semibold : .regular))
                                .foregroundStyle(on ? Color(GridColors.accent) : Color.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(on ? Color(GridColors.headerSelected) : Color.clear, in: Capsule())
                        }
                        .contextMenu {
                            if !readOnly {
                                Button { newName = sheet.name; renaming = i } label: { Label("Rename", systemImage: "pencil") }
                                Button(role: .destructive) { try? book.deleteSheet(i) } label: { Label("Delete", systemImage: "trash") }
                                    .disabled(book.sheets.count < 2)
                            }
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
