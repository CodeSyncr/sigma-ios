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
                toggle("bold", s.bold == true, "Bold") { controller.toggleBold() }
                toggle("italic", s.italic == true, "Italic") { controller.toggleItalic() }
                toggle("underline", s.underline == true, "Underline") { controller.toggleUnderline() }
                toggle("strikethrough", s.strikethrough == true, "Strikethrough") { controller.toggleStrikethrough() }
                divider
                colorButton(.text, icon: "character", swatch: s.textColor ?? "#1f2328", label: "Text colour")
                colorButton(.fill, icon: "drop", swatch: s.fill, label: "Fill colour")
                divider
                MenuButton(controller: controller, items: {
                    let options: [(String, SigmaIcon?, SigmaStyle.Align?)] = [
                        ("Left", .alignLeft, .left), ("Centre", .alignCenter, .center), ("Right", .alignRight, .right), ("Automatic", nil, nil),
                    ]
                    return options.map { title, glyph, a in
                        SigmaMenuItem(title: title, icon: glyph, checked: s.align == a) { controller.setAlign(a) }
                    }
                }) {
                    icon(s.align == .center ? "text.aligncenter" : s.align == .right ? "text.alignright" : "text.alignleft")
                }
                .accessibilityLabel("Alignment")
                MenuButton(controller: controller, items: {
                    [SigmaStyle.NumberFormat.auto, .number, .percent, .currency, .text].map { f in
                        SigmaMenuItem(title: name(f), checked: (s.numberFormat ?? .auto) == f) { controller.setNumberFormat(f) }
                    }
                }) {
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
                MenuButton(controller: controller, items: {
                    let options: [(String, SigmaIcon, SigmaWorkbook.Borders)] = [
                        ("All borders", .bordersAll, .all), ("Outer border", .bordersOuter, .outer), ("Top", .bordersTop, .top),
                        ("Bottom", .bordersBottom, .bottom), ("Left", .bordersLeft, .left), ("Right", .bordersRight, .right),
                        ("No borders", .bordersClear, .clear),
                    ]
                    return options.map { title, glyph, b in SigmaMenuItem(title: title, icon: glyph) { controller.setBorders(b) } }
                }) { icon("squareshape.split.2x2") }
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
                MenuButton(controller: controller, items: {
                    [SigmaMenuItem(title: "Sort A → Z", icon: .sortAscending) { controller.sort(ascending: true) },
                     SigmaMenuItem(title: "Sort Z → A", icon: .sortDescending) { controller.sort(ascending: false) }]
                }) { icon("arrow.up.arrow.down") }
                .accessibilityLabel("Sort")
                Button { controller.insertChart() } label: { icon("chart.bar") }
                    .accessibilityLabel("Insert chart")
                Button { controller.panel = .find } label: { icon("magnifyingglass") }
                    .accessibilityLabel("Find and replace")
                Button { controller.panel = .conditionalFormatting } label: { icon("paintpalette") }
                    .accessibilityLabel("Conditional formatting")
                Button { controller.panel = .note } label: { icon(controller.activeNote.isEmpty ? "note.text.badge.plus" : "note.text") }
                    .accessibilityLabel(controller.activeNote.isEmpty ? "Add note" : "Edit note")
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
        MenuButton(controller: controller, items: { controller.grid?.moreMenu() ?? [] }) {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.primary)
                .rotationEffect(.degrees(90))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
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
