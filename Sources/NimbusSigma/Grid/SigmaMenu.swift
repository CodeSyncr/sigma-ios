#if canImport(UIKit)
import SwiftUI
import UIKit

/// One row of the editor's menu: an action, or a submenu when it has children.
struct SigmaMenuItem: Identifiable {
    let id = UUID()
    var title: String
    var icon: SigmaIcon?
    var checked = false
    var destructive = false
    var enabled = true
    var children: [SigmaMenuItem] = []
    var action: (() -> Void)?
}

/// A button in the strip across the top of the cell menu (cut, copy, paste, clear).
struct SigmaMenuQuick: Identifiable {
    let id = UUID()
    var icon: SigmaIcon
    var label: String
    var enabled = true
    var action: () -> Void
}

/// A menu to show, and where: a point a finger pressed (an empty rect) or a
/// button's frame, in window coordinates.
struct SigmaMenuRequest: Identifiable {
    let id = UUID()
    var items: [SigmaMenuItem]
    var quick: [SigmaMenuQuick] = []
    var anchor: CGRect
}

extension SigmaGridController {
    /// Opens the editor's menu; one is shown at a time.
    func showMenu(_ items: [SigmaMenuItem], quick: [SigmaMenuQuick] = [], at anchor: CGRect) {
        menu = SigmaMenuRequest(items: items, quick: quick, anchor: anchor)
    }
}

/// The editor's menu, drawn by the SDK rather than UIKit, so it looks the same
/// as on Android: a rounded card by the finger or under its button, with
/// submenus that slide in place of the list. Lies over the whole sheet view.
struct SigmaMenuLayer: View {
    @ObservedObject var controller: SigmaGridController

    var body: some View {
        GeometryReader { geo in
            if let request = controller.menu {
                ZStack(alignment: .topLeading) {
                    // A touch anywhere else closes the menu, and goes no further.
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onEnded { _ in controller.menu = nil })
                    MenuCard(request: request, area: geo.frame(in: .global), insets: geo.safeAreaInsets) {
                        controller.menu = nil
                    }
                    .id(request.id)
                }
                .ignoresSafeArea()
            }
        }
    }
}

private struct MenuCard: View {
    let request: SigmaMenuRequest
    /// The layer's frame in window coordinates; anchors are converted into it.
    let area: CGRect
    let insets: EdgeInsets
    let dismiss: () -> Void

    @State private var stack: [SigmaMenuItem] = []
    @State private var forward = true
    @State private var shown = false

    private static let width: CGFloat = 232
    private static let margin: CGFloat = 8
    /// Every row is this tall (one line), so the card's height is known without measuring it.
    private static let rowHeight: CGFloat = 40
    private static let listPadding: CGFloat = 6
    /// The cut, copy, paste and clear strip, with its rule.
    private static let quickHeight: CGFloat = 4 + 58 + 4 + 1
    private static let gap: CGFloat = 4
    private static let ease = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.12)
    private static let slide = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.16)

    private var items: [SigmaMenuItem] { stack.last?.children ?? request.items }
    private var showsQuick: Bool { stack.isEmpty && !request.quick.isEmpty }

    var body: some View {
        let place = placement()
        VStack(spacing: 0) {
            if showsQuick {
                HStack(spacing: 0) {
                    ForEach(request.quick) { q in quickButton(q) }
                }
                .padding(.horizontal, 6)
                .padding(.top, 4)
                Rectangle().fill(Color(GridColors.gridline)).frame(height: 1).padding(.top, 4)
            }
            if listHeight > maxListHeight {
                ScrollView(showsIndicators: false) { list }.frame(height: maxListHeight)
            } else {
                list
            }
        }
        .frame(width: Self.width)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.black.opacity(0.086), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        // Two layers, as on Android: a tight contact shadow and a wide soft one.
        .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
        .scaleEffect(shown ? 1 : 0.96, anchor: place.below ? .top : .bottom)
        .opacity(shown ? 1 : 0)
        .offset(x: place.x, y: place.y)
        .onAppear { withAnimation(Self.ease) { shown = true } }
        .environment(\.colorScheme, .light)
    }

    private var list: some View {
        VStack(spacing: 0) {
            if let parent = stack.last {
                Button {
                    forward = false
                    withAnimation(Self.slide) { _ = stack.popLast() }
                } label: {
                    HStack(spacing: 12) {
                        SigmaGlyph(icon: .back, color: Color(GridColors.ink))
                        Text(parent.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(GridColors.ink))
                        Spacer(minLength: 0)
                    }
                    .row()
                }
                .buttonStyle(RowStyle())
                .accessibilityLabel("Back")
            }
            let icons = items.contains { $0.icon != nil }
            ForEach(items) { item in row(item, icons: icons) }
        }
        .padding(Self.listPadding)
        .id(stack.count)
        .transition(.asymmetric(
            insertion: .offset(x: forward ? 40 : -40).combined(with: .opacity),
            removal: .opacity
        ))
    }

    private func row(_ item: SigmaMenuItem, icons: Bool) -> some View {
        let ink = item.destructive ? Color(GridColors.error) : Color(GridColors.ink)
        return Button {
            if !item.children.isEmpty {
                forward = true
                withAnimation(Self.slide) { stack.append(item) }
            } else {
                dismiss()
                // After the menu has gone, so the action can present a sheet of its own.
                if let action = item.action { DispatchQueue.main.async(execute: action) }
            }
        } label: {
            HStack(spacing: 12) {
                if icons {
                    if let icon = item.icon {
                        SigmaGlyph(icon: icon, color: item.destructive ? Color(GridColors.error) : Color(GridColors.secondary))
                    } else {
                        Color.clear.frame(width: 18, height: 18)
                    }
                }
                Text(item.title)
                    .font(.system(size: 14))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if !item.children.isEmpty {
                    SigmaGlyph(icon: .chevron, color: Color(GridColors.secondary))
                } else if item.checked {
                    SigmaGlyph(icon: .check, color: Color(GridColors.accent))
                }
            }
            .row()
        }
        .buttonStyle(RowStyle())
        .disabled(!item.enabled)
        .opacity(item.enabled ? 1 : 0.4)
        .accessibilityAddTraits(item.checked ? .isSelected : [])
    }

    private func quickButton(_ q: SigmaMenuQuick) -> some View {
        Button {
            dismiss()
            DispatchQueue.main.async(execute: q.action)
        } label: {
            VStack(spacing: 4) {
                SigmaGlyph(icon: q.icon, size: 20, color: Color(GridColors.ink))
                Text(q.label).font(.system(size: 11)).foregroundStyle(Color(GridColors.secondary))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowStyle())
        .disabled(!q.enabled)
        .opacity(q.enabled ? 1 : 0.4)
        .accessibilityLabel(q.label)
    }

    private var bounds: CGRect {
        CGRect(x: insets.leading + Self.margin, y: insets.top + Self.margin,
               width: area.width - insets.leading - insets.trailing - 2 * Self.margin,
               height: area.height - insets.top - insets.bottom - 2 * Self.margin)
    }

    private var maxListHeight: CGFloat {
        area.height * 0.7 - (showsQuick ? Self.quickHeight : 0)
    }

    private var listHeight: CGFloat {
        2 * Self.listPadding + Self.rowHeight * CGFloat(items.count + (stack.isEmpty ? 0 : 1))
    }

    private var cardHeight: CGFloat {
        (showsQuick ? Self.quickHeight : 0) + min(listHeight, maxListHeight)
    }

    /// Where the card goes: by its anchor, flipped above when below would not fit, always on screen.
    private func placement() -> (x: CGFloat, y: CGFloat, below: Bool) {
        let a = request.anchor.offsetBy(dx: -area.minX, dy: -area.minY)
        let b = bounds
        let w = Self.width
        let h = cardHeight
        let point = a.width == 0
        var x = point ? a.minX : (a.midX > b.midX ? a.maxX - w : a.minX)
        x = min(max(x, b.minX), max(b.minX, b.maxX - w))
        let below = a.maxY + Self.gap + h <= b.maxY || a.minY - Self.gap - h < b.minY
        var y = below ? a.maxY + Self.gap : a.minY - Self.gap - h
        y = min(max(y, b.minY), max(b.minY, b.maxY - h))
        return (x, y, below)
    }
}

/// A row's press: a soft rounded wash, as Android's ripple settles to.
private struct RowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(configuration.isPressed ? 0.08 : 0)))
    }
}

private extension View {
    func row() -> some View {
        padding(.horizontal, 10)
            .frame(height: 40)
            .contentShape(Rectangle())
    }
}

/// A button that opens the editor's menu under itself.
struct MenuButton<Label: View>: View {
    @ObservedObject var controller: SigmaGridController
    let items: () -> [SigmaMenuItem]
    @ViewBuilder let label: () -> Label
    @State private var frame: CGRect = .zero

    var body: some View {
        Button { controller.showMenu(items(), at: frame) } label: { label() }
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { frame = g.frame(in: .global) }
                    .onChange(of: g.frame(in: .global)) { frame = $0 }
            })
    }
}

/// A choice among a few options that opens the editor's menu: its own
/// dropdown. With a title it is a form row ("Condition   Greater than ⌄").
struct SigmaPicker: View {
    @ObservedObject var controller: SigmaGridController
    var title: String?
    let options: [String]
    @Binding var selection: Int

    var body: some View {
        MenuButton(controller: controller, items: {
            options.enumerated().map { i, option in
                SigmaMenuItem(title: option, checked: i == selection) { selection = i }
            }
        }) {
            HStack(spacing: 8) {
                if let title {
                    Text(title).foregroundStyle(Color(GridColors.ink))
                    Spacer(minLength: 8)
                    Text(current).foregroundStyle(Color(GridColors.secondary)).lineLimit(1)
                } else {
                    Text(current).font(.system(size: 15)).foregroundStyle(Color(GridColors.ink)).lineLimit(1)
                    Spacer(minLength: 8)
                }
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(GridColors.secondary))
            }
            .padding(.horizontal, title == nil ? 12 : 0)
            .frame(minHeight: title == nil ? 42 : 0)
            .background(title == nil ? Color(GridColors.surface) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title.map { "\($0), \(current)" } ?? current)
    }

    private var current: String { options.indices.contains(selection) ? options[selection] : "" }
}
#endif
