#if canImport(UIKit)
import SwiftUI
import UIKit

/// Edit the selected chart: its type, title, data and stacking.
struct ChartEditor: View {
    @ObservedObject var book: SigmaWorkbook
    @ObservedObject var controller: SigmaGridController
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SigmaChart?
    @State private var dataText = ""

    var body: some View {
        NavigationStack {
            Group {
                if let chart = draft {
                    Form {
                        Section("Type") {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                                ForEach(SigmaChart.Kind.allCases, id: \.self) { kind in
                                    Button { update { $0.kind = kind } } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: kind.symbol).font(.system(size: 20))
                                            Text(kind.label).font(.caption2)
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 54)
                                        .foregroundStyle(chart.kind == kind ? Color(GridColors.accent) : .primary)
                                        .background(chart.kind == kind ? Color(GridColors.headerSelected) : Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(chart.kind == kind ? .isSelected : [])
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        Section("Title") {
                            TextField("No title", text: Binding(get: { chart.title ?? "" }, set: { t in update { $0.title = t.isEmpty ? nil : t } }))
                        }
                        Section {
                            TextField("A1:C13", text: $dataText)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .font(.body.monospaced())
                                .onSubmit { update { $0.data = dataText.uppercased() } }
                        } header: { Text("Data") } footer: { Text("The chart reads these cells as they change.") }
                        if chart.kind.canStack {
                            Toggle("Stacked", isOn: Binding(get: { chart.stacked == true }, set: { on in update { $0.stacked = on ? true : nil } }))
                        }
                        Section {
                            Button("Delete Chart", role: .destructive) {
                                try? book.removeChart(id: chart.id)
                                controller.selectedChart = nil
                                dismiss()
                            }
                        }
                    }
                } else {
                    Text("Select a chart to edit it.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Chart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let d = draft, d.data != dataText.uppercased(), !dataText.isEmpty { update { $0.data = dataText.uppercased() } }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            draft = book.charts().first { $0.chart.id == controller.selectedChart }?.chart
            dataText = draft?.data ?? ""
        }
    }

    private func update(_ change: (inout SigmaChart) -> Void) {
        guard var d = draft else { return }
        change(&d)
        draft = d
        try? book.updateChart(d)
    }
}

/// Vani AI in the sheet: ask, read the answer, apply the change it proposes
/// (as one undo step).
struct VaniPanel: View {
    @ObservedObject var session: SigmaSession
    @ObservedObject var controller: SigmaGridController
    @State private var prompt = ""
    @State private var asking = false
    @State private var failure: String?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    private let suggestions = [
        "Add a total row and format it",
        "Chart this data",
        "Highlight values above average",
        "Build a monthly budget for a family of four",
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if controller.aiMessages.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Vani AI builds the sheet, not a description of one: tables, formulas, formats and charts bound to your cells.")
                                    .foregroundStyle(.secondary)
                                ForEach(suggestions, id: \.self) { s in
                                    Button { prompt = s; send() } label: {
                                        Text(s).font(.subheadline).padding(.horizontal, 12).padding(.vertical, 8)
                                            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        ForEach($controller.aiMessages) { $m in
                            MessageView(message: $m, apply: apply).id(m.id)
                        }
                        if asking {
                            HStack(spacing: 8) { ProgressView(); Text("Working on it…").foregroundStyle(.secondary) }.id("working")
                        }
                        if let failure {
                            Text(failure).font(.footnote).foregroundStyle(Color(GridColors.error))
                        }
                    }
                    .padding(16)
                }
                .onChange(of: controller.aiMessages.count) { _ in
                    withAnimation { scroller.scrollTo(controller.aiMessages.last?.id, anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    TextField("Ask Vani AI about this sheet", text: $prompt, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($focused)
                        .submitLabel(.send)
                        .onSubmit(send)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                    }
                    .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || asking)
                    .accessibilityLabel("Send")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .navigationTitle("Vani AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if !controller.aiMessages.isEmpty {
                    ToolbarItem(placement: .primaryAction) { Button("Clear") { controller.aiMessages = [] } }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func send() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !asking else { return }
        let history = controller.aiMessages
        controller.aiMessages.append(SigmaAIMessage(role: .user, text: text))
        prompt = ""
        failure = nil
        asking = true
        Task {
            do {
                let answer = try await session.ask(text, history: history, selection: controller.selection)
                controller.aiMessages.append(answer)
            } catch {
                failure = (error as? SigmaError)?.errorDescription ?? error.localizedDescription
            }
            asking = false
        }
    }

    private func apply(_ message: inout SigmaAIMessage) {
        guard let patch = message.patch, message.applied == nil, let book = session.workbook else { return }
        do {
            message.applied = try book.applyPatch(patch).summary
        } catch {
            failure = (error as? SigmaError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct MessageView: View {
    @Binding var message: SigmaAIMessage
    let apply: (inout SigmaAIMessage) -> Void

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color(GridColors.headerSelected), in: RoundedRectangle(cornerRadius: 14))
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label("Vani AI", systemImage: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(Self.markdown(message.text)).textSelection(.enabled)
                if message.patch != nil {
                    if let done = message.applied {
                        Label(done, systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(Color(GridColors.accent))
                    } else {
                        Button { apply(&message) } label: {
                            Label("Apply" + (message.patchSummary.map { " — \($0)" } ?? ""), systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(GridColors.accent))
                    }
                }
            }
        }
    }

    static func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
#endif
