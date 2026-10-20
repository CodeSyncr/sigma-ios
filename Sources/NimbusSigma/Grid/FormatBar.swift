#if canImport(UIKit)
import SwiftUI
import UIKit

/// Sigma's colour palette, the same swatches as the web editor's pickers.
enum Palette {
    static let rows: [[String]] = [
        ["#000000", "#434343", "#666666", "#999999", "#cccccc", "#efefef", "#ffffff"],
        ["#c0392b", "#e67e22", "#f1c40f", "#27ae60", "#16a085", "#2980b9", "#8e44ad"],
        ["#f4cccc", "#fce5cd", "#fff2cc", "#d9ead3", "#d0e0e3", "#cfe2f3", "#d9d2e9"],
        ["#e06666", "#f6b26b", "#ffd966", "#93c47d", "#76a5af", "#6fa8dc", "#8e7cc3"],
    ]

    static func color(_ hex: String?) -> Color? {
        GridColors.hex(hex).map { Color(uiColor: $0) }
    }
}

/// Bold, colours, alignment, number formats, text size, borders, sort and
/// the panels: one row that scrolls sideways, over the grid.
struct FormatBar: View {
    @ObservedObject var controller: SigmaGridController
    /// Shares the sheet as a file; nil hides sharing.
    var share: ((SigmaFormat) -> Void)?
    @State private var picking: ColorTarget?

    enum ColorTarget: String, Identifiable {
        case text, fill
        var id: String { rawValue }
    }

    private var s: SigmaStyle { controller.activeStyle }

    var body: some View {
        HStack(spacing: 0) {
            bar
            // Pinned, so sheet commands never scroll out of reach.
            Rectangle().fill(Color(uiColor: .separator)).frame(width: 1, height: 28)
            MoreMenu(controller: controller)
        }
    }

    private var bar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                if controller.aiAvailable {
                    Button { controller.panel = .ai } label: {
                        Label("Vani AI", systemImage: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .foregroundStyle(.white)
                            .background(LinearGradient(colors: [Color(red: 0.91, green: 0.3, blue: 0.24), Color(red: 0.98, green: 0.45, blue: 0.09)], startPoint: .leading, endPoint: .trailing), in: Capsule())
                    }
                    divider
                }
                toggle("bold", s.bold == true, "Bold") { controller.toggleBold() }
                toggle("italic", s.italic == true, "Italic") { controller.toggleItalic() }
                toggle("underline", s.underline == true, "Underline") { controller.toggleUnderline() }
                toggle("strikethrough", s.strikethrough == true, "Strikethrough") { controller.toggleStrikethrough() }
                divider
                colorButton(.text, icon: "character", swatch: s.textColor ?? "#1f2328", label: "Text colour")
                colorButton(.fill, icon: "drop", swatch: s.fill, label: "Fill colour")
                divider
                Menu {
                    Button { controller.setAlign(.left) } label: { Label("Left", systemImage: "text.alignleft") }
                    Button { controller.setAlign(.center) } label: { Label("Centre", systemImage: "text.aligncenter") }
                    Button { controller.setAlign(.right) } label: { Label("Right", systemImage: "text.alignright") }
                    Button { controller.setAlign(nil) } label: { Label("Automatic", systemImage: "text.justify") }
                } label: {
                    icon(s.align == .center ? "text.aligncenter" : s.align == .right ? "text.alignright" : "text.alignleft")
                }
                .accessibilityLabel("Alignment")
                Menu {
                    ForEach([SigmaStyle.NumberFormat.auto, .number, .percent, .currency, .text], id: \.self) { f in
                        Button { controller.setNumberFormat(f) } label: {
                            if (s.numberFormat ?? .auto) == f { Label(name(f), systemImage: "checkmark") } else { Text(name(f)) }
                        }
                    }
                } label: {
                    Text(short(s.numberFormat ?? .auto)).font(.system(size: 14, weight: .medium)).frame(minWidth: 36, minHeight: 36)
                }
                .accessibilityLabel("Number format")
                textButton(".0←", "Fewer decimal places") { controller.stepDecimals(-1) }
                textButton(".00→", "More decimal places") { controller.stepDecimals(1) }
                divider
                Button { controller.setFontSize((s.fontSize ?? 13) - 1) } label: { icon("minus") }
                    .accessibilityLabel("Smaller text")
                Text("\(Int(s.fontSize ?? 13))")
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .frame(minWidth: 24)
                Button { controller.setFontSize((s.fontSize ?? 13) + 1) } label: { icon("plus") }
                    .accessibilityLabel("Larger text")
                divider
                Menu {
                    Button { controller.setBorders(.all) } label: { Label("All borders", systemImage: "squareshape.split.2x2") }
                    Button { controller.setBorders(.outer) } label: { Label("Outer border", systemImage: "square") }
                    Button { controller.setBorders(.top) } label: { Label("Top", systemImage: "arrow.up.to.line") }
                    Button { controller.setBorders(.bottom) } label: { Label("Bottom", systemImage: "arrow.down.to.line") }
                    Button { controller.setBorders(.left) } label: { Label("Left", systemImage: "arrow.left.to.line") }
                    Button { controller.setBorders(.right) } label: { Label("Right", systemImage: "arrow.right.to.line") }
                    Button(role: .destructive) { controller.setBorders(.clear) } label: { Label("No borders", systemImage: "square.dashed") }
                } label: { icon("squareshape.split.2x2") }
                .accessibilityLabel("Borders")
                Button { controller.clearFormatting() } label: { icon("eraser") }
                    .accessibilityLabel("Clear formatting")
                divider
                Button { controller.autoSum() } label: { icon("sum") }
                    .accessibilityLabel("AutoSum")
                Button { controller.panel = .functions } label: {
                    Text("ƒx").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.primary).frame(width: 36, height: 36)
                }
                .accessibilityLabel("Insert function")
                Menu {
                    Button { controller.sort(ascending: true) } label: { Label("Sort A → Z", systemImage: "arrow.up") }
                    Button { controller.sort(ascending: false) } label: { Label("Sort Z → A", systemImage: "arrow.down") }
                } label: { icon("arrow.up.arrow.down") }
                .accessibilityLabel("Sort")
                Button { controller.insertChart() } label: { icon("chart.bar") }
                    .accessibilityLabel("Insert chart")
                Button { controller.panel = .find } label: { icon("magnifyingglass") }
                    .accessibilityLabel("Find and replace")
                Button { controller.panel = .conditionalFormatting } label: { icon("paintpalette") }
                    .accessibilityLabel("Conditional formatting")
                Button { controller.panel = .note } label: { icon(controller.activeNote.isEmpty ? "note.text.badge.plus" : "note.text") }
                    .accessibilityLabel(controller.activeNote.isEmpty ? "Add note" : "Edit note")
                if let share {
                    divider
                    Menu {
                        Button { share(.xlsx) } label: { Label("Excel workbook (.xlsx)", systemImage: "tablecells") }
                        Button { share(.csv) } label: { Label("CSV of this sheet", systemImage: "doc.plaintext") }
                    } label: { icon("square.and.arrow.up") }
                    .accessibilityLabel("Share")
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 44)
        .buttonStyle(.plain)
        .sheet(item: $picking) { target in
            ColorSheet(title: target == .text ? "Text colour" : "Fill colour",
                       current: target == .text ? s.textColor : s.fill,
                       clearTitle: target == .text ? "Automatic" : "No fill") { hex in
                if target == .text { controller.setTextColor(hex) } else { controller.setFill(hex) }
                picking = nil
            }
            .presentationDetents([.height(300)])
        }
    }

    private var divider: some View {
        Rectangle().fill(Color(uiColor: .separator)).frame(width: 1, height: 22).padding(.horizontal, 5)
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Color.primary)
            .frame(width: 36, height: 36)
    }

    private func toggle(_ name: String, _ on: Bool, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 16, weight: on ? .bold : .medium))
                .foregroundStyle(on ? Color(GridColors.accent) : Color.primary)
                .frame(width: 36, height: 36)
                .background(on ? Color(GridColors.headerSelected) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func textButton(_ text: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.system(size: 13, weight: .medium)).frame(minWidth: 36, minHeight: 36)
        }
        .accessibilityLabel(label)
    }

    private func colorButton(_ target: ColorTarget, icon name: String, swatch: String?, label: String) -> some View {
        Button { picking = target } label: {
            VStack(spacing: 2) {
                Image(systemName: name).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.primary)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Palette.color(swatch) ?? Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 1.5).stroke(Color(uiColor: .separator), lineWidth: swatch == nil ? 1 : 0))
                    .frame(width: 18, height: 4)
            }
            .frame(width: 36, height: 36)
        }
        .accessibilityLabel(label)
    }

    private func name(_ f: SigmaStyle.NumberFormat) -> String {
        switch f {
        case .auto: return "Automatic"
        case .number: return "Number  1,234.00"
        case .percent: return "Percent  12%"
        case .currency: return "Currency  ₹1,234.00"
        case .text: return "Plain text"
        }
    }

    private func short(_ f: SigmaStyle.NumberFormat) -> String {
        switch f {
        case .auto: return "123"
        case .number: return "0.00"
        case .percent: return "%"
        case .currency: return "₹"
        case .text: return "Aa"
        }
    }
}

/// Sheet commands in one place, always on the format bar: freeze, rows,
/// columns, fill, sort, paste values and notes.
struct MoreMenu: View {
    @ObservedObject var controller: SigmaGridController

    var body: some View {
        Menu {
            let f = controller.frozen
            Menu {
                Button("1 Row") { controller.freeze(rows: 1, columns: f.columns) }
                Button("2 Rows") { controller.freeze(rows: 2, columns: f.columns) }
                Button("1 Column") { controller.freeze(rows: f.rows, columns: 1) }
                Button("Up to \(controller.selection.active.description)") {
                    controller.freeze(rows: controller.selection.active.row + 1, columns: controller.selection.active.column + 1)
                }
                if f.rows > 0 || f.columns > 0 {
                    Button("No Frozen Panes", role: .destructive) { controller.freeze(rows: 0, columns: 0) }
                }
            } label: { Label("Freeze", systemImage: "snowflake") }
            Menu {
                Button { controller.insertRows(above: true) } label: { Label("Insert Above", systemImage: "arrow.up.to.line.compact") }
                Button { controller.insertRows(above: false) } label: { Label("Insert Below", systemImage: "arrow.down.to.line.compact") }
                Button(role: .destructive) { controller.deleteRows() } label: { Label("Delete", systemImage: "trash") }
            } label: { Label("Rows", systemImage: "rectangle.split.1x2") }
            Menu {
                Button { controller.insertColumns(left: true) } label: { Label("Insert Left", systemImage: "arrow.left.to.line.compact") }
                Button { controller.insertColumns(left: false) } label: { Label("Insert Right", systemImage: "arrow.right.to.line.compact") }
                Button(role: .destructive) { controller.deleteColumns() } label: { Label("Delete", systemImage: "trash") }
            } label: { Label("Columns", systemImage: "rectangle.split.2x1") }
            Menu {
                Button { controller.startFill() } label: { Label("Drag to Fill…", systemImage: "square.and.arrow.down.on.square") }
                Button { controller.fillDown() } label: { Label("Fill Down", systemImage: "arrow.down.to.line") }
                Button { controller.fillRight() } label: { Label("Fill Right", systemImage: "arrow.right.to.line") }
            } label: { Label("Fill", systemImage: "square.and.pencil") }
            Menu {
                Button { controller.sort(ascending: true) } label: { Label("Sort A → Z", systemImage: "arrow.up") }
                Button { controller.sort(ascending: false) } label: { Label("Sort Z → A", systemImage: "arrow.down") }
            } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
            Divider()
            Button { controller.pasteValues() } label: { Label("Paste Values Only", systemImage: "doc.on.clipboard") }
                .disabled(!controller.canPasteValues)
            Button { controller.panel = .note } label: { Label(controller.activeNote.isEmpty ? "Add Note" : "Edit Note", systemImage: "note.text") }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.primary)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("More")
    }
}

/// The palette, as a short sheet: one tap picks a colour.
struct ColorSheet: View {
    let title: String
    let current: String?
    let clearTitle: String
    let pick: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            VStack(spacing: 10) {
                ForEach(Palette.rows, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(row, id: \.self) { hex in
                            Button { pick(hex) } label: {
                                Circle()
                                    .fill(Palette.color(hex) ?? .clear)
                                    .overlay(Circle().stroke(Color(uiColor: .separator), lineWidth: hex == "#ffffff" ? 1 : 0))
                                    .overlay(Circle().stroke(Color(GridColors.accent), lineWidth: current?.lowercased() == hex ? 3 : 0).padding(-4))
                                    .frame(width: 34, height: 34)
                            }
                            .accessibilityLabel(hex)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            Button(clearTitle) { pick(nil) }
                .buttonStyle(.bordered)
        }
        .padding(20)
    }
}
#endif
