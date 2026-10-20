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

#endif
