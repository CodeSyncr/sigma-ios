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
    @StateObject private var editor: SigmaEditor
    @State private var shared: SigmaFile?

    init(id: Int) {
        // The editor asks your server for a link when it opens, and again if one expires.
        _editor = StateObject(wrappedValue: SigmaEditor { try await YourServer.editLink(for: id) })
    }

    var body: some View {
        SigmaEditorView(editor: editor)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(editor.title.isEmpty ? "Sheet" : editor.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if editor.hasUnsavedChanges { ProgressView() }
                    Menu {
                        Button("Fill in a sample") {
                            Task {
                                try? await editor.setCells([
                                    "A1": "Item", "B1": "Cost",
                                    "A2": "Rent", "B2": "1200",
                                    "A3": "Food", "B3": "450",
                                    "A4": "Total", "B4": "=SUM(B2:B3)",
                                ])
                            }
                        }
                        Button("Export as Excel") { Task { shared = try? await editor.export(.xlsx) } }
                        Button("Export as CSV") { Task { shared = try? await editor.export(.csv) } }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(editor.phase != .ready)
                }
            }
            .sheet(item: $shared) { file in
                if let sheet = try? SigmaShareSheet(file: file) { sheet }
            }
    }
}
