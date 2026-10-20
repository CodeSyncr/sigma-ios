#if canImport(UIKit)
import SwiftUI
import UIKit

/// Find (and replace) in the sheet, as a bar over the grid: each hit is
/// selected in turn, so the grid scrolls to it.
struct FindBar: View {
    @ObservedObject var book: SigmaWorkbook
    @ObservedObject var controller: SigmaGridController
    let readOnly: Bool
    @State private var query = ""
    @State private var replacement = ""
    @State private var matchCase = false
    @State private var replacing = false
    @State private var hits: [SigmaAddress] = []
    @State private var at = 0
    @State private var replaced: Int?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find in sheet", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .focused($focused)
                        .onSubmit { step(1) }
                    if !query.isEmpty {
                        Text(hits.isEmpty ? "No results" : "\(at + 1) of \(hits.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 9))
                Button { step(-1) } label: { Image(systemName: "chevron.up") }.disabled(hits.isEmpty).accessibilityLabel("Previous")
                Button { step(1) } label: { Image(systemName: "chevron.down") }.disabled(hits.isEmpty).accessibilityLabel("Next")
                MenuButton(controller: controller, items: {
                    var items = [SigmaMenuItem(title: "Match case", icon: .matchCase, checked: matchCase) { matchCase.toggle() }]
                    if !readOnly { items.append(SigmaMenuItem(title: "Replace", icon: .replace, checked: replacing) { replacing.toggle() }) }
                    return items
                }) { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("Find options")
                Button("Done") { controller.panel = nil }.fontWeight(.semibold)
            }
            if replacing && !readOnly {
                HStack(spacing: 8) {
                    TextField("Replace with", text: $replacement)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 9))
                    Button(replaced.map { "Replaced \($0)" } ?? "Replace All") {
                        replaced = (try? book.replaceAll(query, with: replacement, matchCase: matchCase)) ?? 0
                    }
                    .buttonStyle(.bordered)
                    .disabled(query.isEmpty)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear { focused = true }
        .onChange(of: query) { _ in search(); replaced = nil }
        .onChange(of: matchCase) { _ in search() }
        .onChange(of: book.revision) { _ in search(keepPlace: true) }
    }

    private func search(keepPlace: Bool = false) {
        hits = query.isEmpty ? [] : book.find(query, matchCase: matchCase)
        at = keepPlace ? min(at, max(0, hits.count - 1)) : 0
        if !keepPlace, let first = hits.first { controller.select(SigmaSelection(first)) }
    }

    private func step(_ by: Int) {
        guard !hits.isEmpty else { return }
        at = (at + by + hits.count) % hits.count
        controller.select(SigmaSelection(hits[at]))
    }
}

/// A cell's note: shown under the formula bar when the cell has one.
struct NoteBanner: View {
    let note: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "note.text").foregroundStyle(Color(GridColors.note))
                Text(note).font(.footnote).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(GridColors.note).opacity(0.10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Note: \(note)")
    }
}

struct NoteSheet: View {
    @ObservedObject var controller: SigmaGridController
    let readOnly: Bool
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($focused)
                .padding(.horizontal, 12)
                .disabled(readOnly)
                .navigationTitle("Note on \(controller.selection.active.description)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(readOnly ? "Close" : "Cancel") { dismiss() } }
                    if !readOnly {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { controller.setNote(text); dismiss() }
                        }
                        if !controller.activeNote.isEmpty {
                            ToolbarItem(placement: .bottomBar) {
                                Button("Delete Note", role: .destructive) { controller.setNote(""); dismiss() }
                            }
                        }
                    }
                }
        }
        .onAppear {
            text = controller.activeNote
            if !readOnly { focused = true }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The sheet's conditional formatting rules: see, add and delete them.
struct ConditionalFormattingSheet: View {
    @ObservedObject var book: SigmaWorkbook
    @ObservedObject var controller: SigmaGridController
    let readOnly: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                let rules = book.conditionalRules()
                if rules.isEmpty {
                    Text("Colour cells by their value — for example, fill scores under 50 in red.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(rules.enumerated()), id: \.offset) { i, rule in
                    HStack(spacing: 12) {
                        Text("Aa")
                            .font(.system(size: 13, weight: rule.bold == true ? .bold : .regular))
                            .foregroundStyle(Palette.color(rule.textColor) ?? .primary)
                            .frame(width: 34, height: 26)
                            .background(Palette.color(rule.fill) ?? Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 5))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.range.description).font(.subheadline.weight(.semibold).monospaced())
                            Text(describe(rule)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        if !readOnly {
                            Button(role: .destructive) { try? book.removeConditionalRule(at: i) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }
            .navigationTitle("Conditional Formatting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if !readOnly {
                    ToolbarItem(placement: .primaryAction) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add rule") }
                }
            }
            .navigationDestination(isPresented: $adding) {
                RuleEditor(controller: controller, range: controller.selection) { rule in
                    try? book.addConditionalRule(rule)
                    adding = false
                }
            }
        }
        // This sheet covers the editor, so its menus open over it here.
        .overlay { SigmaMenuLayer(controller: controller) }
        .presentationDetents([.medium, .large])
    }

    private func describe(_ r: SigmaConditionalRule) -> String {
        switch r.condition {
        case .notEmpty: return r.condition.label
        case .between: return "\(r.condition.label) \(r.value) and \(r.value2 ?? "")"
        case .contains: return "\(r.condition.label) “\(r.value)”"
        default: return "\(r.condition.label) \(r.value)"
        }
    }
}

struct RuleEditor: View {
    @ObservedObject var controller: SigmaGridController
    let range: SigmaSelection
    let add: (SigmaConditionalRule) -> Void
    @State private var rangeText = ""
    @State private var condition: SigmaConditionalRule.Condition = .greaterThan
    @State private var value = ""
    @State private var value2 = ""
    @State private var look = 0
    @State private var bold = false

    /// Ready-made looks, as fill and text colour.
    private let looks: [(name: String, fill: String?, text: String?)] = [
        ("Green", "#d9ead3", "#1e5e2b"), ("Red", "#f4cccc", "#99231b"), ("Yellow", "#fff2cc", "#7a5b00"),
        ("Blue", "#cfe2f3", "#1c4a73"), ("Bold red text", nil, "#c0392b"),
    ]

    var body: some View {
        Form {
            Section("Cells") {
                TextField("Range, e.g. B2:B20", text: $rangeText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            }
            Section("When the value is") {
                let conditions = SigmaConditionalRule.Condition.allCases
                SigmaPicker(controller: controller, title: "Condition", options: conditions.map(\.label), selection: Binding(
                    get: { conditions.firstIndex(of: condition) ?? 0 },
                    set: { condition = conditions[$0] }
                ))
                if condition.needsValue {
                    TextField(condition == .contains ? "Text" : "Value", text: $value)
                    if condition == .between { TextField("And", text: $value2) }
                }
            }
            Section("Format them") {
                SigmaPicker(controller: controller, title: "Look", options: looks.map(\.name), selection: $look)
                Toggle("Bold", isOn: $bold)
                HStack {
                    Text("Preview")
                    Spacer()
                    Text("1,234")
                        .font(.system(size: 14, weight: bold ? .bold : .regular))
                        .foregroundStyle(Palette.color(looks[look].text) ?? .primary)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Palette.color(looks[look].fill) ?? .clear, in: RoundedRectangle(cornerRadius: 5))
                }
            }
        }
        .navigationTitle("New Rule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    guard let r = parsedRange else { return }
                    add(SigmaConditionalRule(range: r, condition: condition, value: value, value2: condition == .between ? value2 : nil,
                                             fill: looks[look].fill, textColor: looks[look].text,
                                             // The text-only look is bold, or it hardly shows.
                                             bold: (bold || looks[look].fill == nil) ? true : nil))
                }
                .disabled(parsedRange == nil || (condition.needsValue && value.isEmpty))
            }
        }
        .onAppear { rangeText = range.description }
    }

    private var parsedRange: SigmaSelection? {
        let parts = rangeText.replacingOccurrences(of: " ", with: "").split(separator: ":").map(String.init)
        guard let a = parts.first.flatMap(SigmaAddress.init) else { return nil }
        let b = parts.count > 1 ? SigmaAddress(parts[1]) : a
        guard let b, parts.count <= 2 else { return nil }
        return SigmaSelection(active: a, corner: b)
    }
}
/// Every function formulas can use, searchable and by category. A tap puts
/// the function into the formula being typed, or starts one in the active cell.
struct FunctionsSheet: View {
    @ObservedObject var book: SigmaWorkbook
    @ObservedObject var controller: SigmaGridController
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                let shown = book.functions().filter {
                    query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.description.localizedCaseInsensitiveContains(query)
                }
                if shown.isEmpty {
                    Text("No function matches “\(query)”.").foregroundStyle(.secondary)
                }
                ForEach(Dictionary(grouping: shown, by: \.category).sorted(by: { $0.key < $1.key }), id: \.key) { category, fns in
                    Section(category) {
                        ForEach(fns) { f in
                            Button {
                                dismiss()
                                controller.insertFunction(f.name)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(f.syntax).font(.system(.subheadline, design: .monospaced).weight(.semibold)).foregroundStyle(.primary)
                                    if !f.description.isEmpty {
                                        Text(f.description).font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search functions")
            .navigationTitle("Insert Function")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
#endif
