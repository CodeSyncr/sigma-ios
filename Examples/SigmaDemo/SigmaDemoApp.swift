import SwiftUI
import NimbusSigma

/*
 * A small app for trying NimbusSigma: list your sheets, create one, open it,
 * edit it, export it.
 *
 * Open Examples/SigmaDemo/SigmaDemo.xcodeproj, run it, and enter your Nimbus
 * Cloud address and a Sigma test key in Settings.
 */

@main
struct SigmaDemoApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationView { SheetsScreen() }
                .navigationViewStyle(.stack)
        }
    }
}

/// Stands in for YOUR server. A real app asks its own backend, which keeps
/// the sgm_ key and mints links — never the key in the app. The demo calls
/// the API directly so it runs on its own, with a key typed into Settings.
enum YourServer {
    static var sigma: SigmaClient {
        let d = UserDefaults.standard
        let env = ProcessInfo.processInfo.environment.filter { !$0.value.isEmpty }
        let cloud = env["SIGMA_CLOUD"] ?? d.string(forKey: "cloud") ?? Settings.defaultCloud
        return SigmaClient(apiKey: env["SIGMA_KEY"] ?? d.string(forKey: "key") ?? "",
                           baseURL: URL(string: cloud) ?? URL(string: Settings.defaultCloud)!)
    }

    static func sheets() async throws -> [SigmaDocument] { try await sigma.documents() }

    static func newSheet(_ title: String) async throws -> Int { try await sigma.createBlank(title: title).id }

    static func uploadSample() async throws -> Int {
        let csv = "Item,Cost,Qty,Total\nRent,1200,1,=B2*C2\nGroceries,85,4,=B3*C3\nTransport,40,10,=B4*C4\nTotal,,,=SUM(D2:D4)\n"
        return try await sigma.upload(Data(csv.utf8), filename: "Monthly budget.csv", title: "Monthly budget").id
    }

    static func editLink(for id: Int) async throws -> URL { try await sigma.link(for: id, mode: .edit).url }
}

struct SheetsScreen: View {
    @AppStorage("key") private var key = ""
    @State private var sheets: [SigmaDocument] = []
    @State private var openID: Int? = ProcessInfo.processInfo.environment["SIGMA_DOC_ID"].flatMap(Int.init)
    @State private var problem: String?
    @State private var busy = false
    @State private var showSettings = false

    var body: some View {
        List {
            Section {
                Button("New blank sheet") { run { openID = try await YourServer.newSheet("Untitled sheet") } }
                Button("Upload a sample budget") { run { openID = try await YourServer.uploadSample() } }
            } footer: {
                if let problem { Text(problem).foregroundColor(.red) }
            }
            Section("Your sheets") {
                if sheets.isEmpty { Text(busy ? "Loading…" : "None yet").foregroundColor(.secondary) }
                ForEach(sheets) { doc in
                    Button { openID = doc.id } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(doc.title).foregroundColor(.primary)
                            Text("\(doc.filename) · \(doc.size) bytes").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Sigma sheets")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
        }
        .refreshable { await load() }
        .task { if key.isEmpty && (ProcessInfo.processInfo.environment["SIGMA_KEY"] ?? "").isEmpty { showSettings = true } else { await load() } }
        .sheet(isPresented: $showSettings, onDismiss: { Task { await load() } }) { Settings() }
        .background(
            NavigationLink(isActive: Binding(get: { openID != nil }, set: { if !$0 { openID = nil; Task { await load() } } })) {
                if let id = openID { SheetScreen(id: id) }
            } label: { EmptyView() }
        )
    }

    private func load() async {
        busy = true
        defer { busy = false }
        do {
            sheets = try await YourServer.sheets()
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    private func run(_ job: @escaping () async throws -> Void) {
        Task {
            do { try await job(); problem = nil } catch { problem = error.localizedDescription }
        }
    }
}

struct Settings: View {
    static let defaultCloud = "http://localhost:3333"
    @AppStorage("cloud") private var cloud = Settings.defaultCloud
    @AppStorage("key") private var key = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Cloud address", text: $cloud)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("sgm_test_…", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: {
                    Text("Nimbus Cloud")
                } footer: {
                    Text("Make a Sigma key in Nimbus Cloud › API & CLI Keys. This demo keeps it on the device so it can run on its own; a real app keeps it on its server and asks the server for links.\n\nIn the Simulator, http://localhost:3333 is the cloud running on this Mac.")
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

struct SheetScreen: View {
    @StateObject private var session: SigmaSession
    @StateObject private var grid = SigmaGridController()
    @State private var shared: SigmaFile?

    init(id: Int) {
        // The session asks your server for a link when it opens, and again if one expires.
        _session = StateObject(wrappedValue: SigmaSession { try await YourServer.editLink(for: id) })
    }

    var body: some View {
        SigmaSheetView(session: session, controller: grid)
            .navigationTitle(session.title.isEmpty ? "Sheet" : session.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    switch session.saveState {
                    case .saving, .unsaved: ProgressView()
                    case .failed: Image(systemName: "exclamationmark.icloud").foregroundColor(.red)
                    case .saved: EmptyView()
                    }
                    Menu {
                        Button("Fill in a sample") {
                            try? session.workbook?.set([
                                SigmaAddress("A1")!: "Item", SigmaAddress("B1")!: "Cost",
                                SigmaAddress("A2")!: "Rent", SigmaAddress("B2")!: "1200",
                                SigmaAddress("A3")!: "Food", SigmaAddress("B3")!: "450",
                                SigmaAddress("A4")!: "Total", SigmaAddress("B4")!: "=SUM(B2:B3)",
                            ])
                        }
                        Button("Export as Excel") { export(.xlsx) }
                        Button("Export as CSV") { export(.csv) }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(session.phase != .ready)
                }
            }
            .sheet(item: $shared) { file in
                if let sheet = try? SigmaShareSheet(file: file) { sheet }
            }
            .task(id: session.phase == .ready) { await DemoTour.run(session: session, grid: grid) }
            .task(id: session.phase == .ready) { DemoVani.seed(session: session, grid: grid) }
    }

    private func export(_ format: SigmaFormat) {
        Task {
            guard let book = session.workbook, let data = try? await book.export(format) else { return }
            let name = (session.title.isEmpty ? "Sheet" : session.title) + "." + format.fileExtension
            shared = SigmaFile(data: data, filename: name, format: format)
        }
    }
}

/// With SIGMA_DEMO_VANI=1 the demo opens Vani with a sample conversation,
/// to look at the panel without asking the model anything.
enum DemoVani {
    @MainActor
    static func seed(session: SigmaSession, grid: SigmaGridController) {
        guard ProcessInfo.processInfo.environment["SIGMA_DEMO_VANI"] == "1", session.phase == .ready else { return }
        var done = SigmaAIMessage(role: .assistant, text: "I added a **Grand total** row under your data and made the header bold.\n- Costs show as rupees\n- A border separates the totals", patch: "{}", patchSummary: "2 cells · 6 formats")
        done.applied = "2 cells, 6 formats"
        grid.aiMessages = [
            SigmaAIMessage(role: .user, text: "Add a total row and format it"),
            done,
            SigmaAIMessage(role: .user, text: "Highlight anything above ₹500"),
            SigmaAIMessage(role: .assistant, text: "Rent is the only cost above ₹500. I can colour it amber so it stands out.", patch: "{}", patchSummary: "1 format rule"),
        ]
        grid.panel = .ai
    }
}

/// With SIGMA_DEMO_TOUR=1 the demo drives itself through the grid, for
/// screenshots without a person at the Simulator.
enum DemoTour {
    @MainActor
    static func run(session: SigmaSession, grid: SigmaGridController) async {
        guard ProcessInfo.processInfo.environment["SIGMA_DEMO_TOUR"] == "1", session.phase == .ready,
              let book = session.workbook else { return }
        func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
        // SIGMA_DEMO_SHOTS=<folder> saves a picture of the screen at each step.
        func step(_ name: String) {
            print("TOUR", name)
            guard let dir = ProcessInfo.processInfo.environment["SIGMA_DEMO_SHOTS"],
                  let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try? image.pngData()?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("tour-\(name).png"))
        }
        await pause(1.5)
        step("opened")
        grid.select(SigmaSelection(SigmaAddress("B4")!))
        await pause(1.0)
        step("selected")
        grid.beginEditing(with: "=SUM(B2:B3)*2")
        await pause(2.0)
        step("editing")
        grid.commit()
        await pause(1.5)
        step("committed")
        grid.select(SigmaSelection(active: SigmaAddress("A1")!, corner: SigmaAddress("B3")!))
        try? book.applyStyle(SigmaStyle(bold: true, fill: "#fde68a"), from: SigmaAddress("A1")!, to: SigmaAddress("B1")!)
        try? book.freeze(rows: 1, columns: 1)
        await pause(1.5)
        step("range-frozen")
        grid.select(SigmaSelection(SigmaAddress("H40")!))
        await pause(2.0)
        step("scrolled")
    }
}
