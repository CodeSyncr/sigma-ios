#if canImport(UIKit)
import SwiftUI

/// Vani AI's launcher over the grid, as Website Studio draws it: a frosted
/// pill with Nimbo saying hello and "Ask Vani"; on a phone, Nimbo alone.
/// While Vani works Nimbo thinks, the line says so and a ring pulses, even
/// with the panel closed. Tap opens the Vani panel; drag it anywhere and it
/// snaps to the nearer side. Its spot is remembered for the app. Hidden
/// while a cell is being edited.
struct VaniBall: View {
    @ObservedObject var controller: SigmaGridController

    private static let margin: CGFloat = 12
    private static let sideKey = "NimbusSigma.vaniBall.right"
    private static let heightKey = "NimbusSigma.vaniBall.height"

    /// Which side it rests on, and how far down (0 top … 1 bottom) of the room it has.
    @State private var right = UserDefaults.standard.object(forKey: VaniBall.sideKey) as? Bool ?? true
    @State private var height = UserDefaults.standard.object(forKey: VaniBall.heightKey) as? Double ?? 1
    @State private var drag: CGPoint?
    @State private var size = CGSize(width: 60, height: 44)

    var body: some View {
        GeometryReader { geo in
            // Studio drops the words below 640 points, as here.
            let full = geo.size.width > 640
            VaniLauncher(working: controller.aiWorking, full: full) { controller.panel = .ai }
                .background(GeometryReader { g in Color.clear.preference(key: LauncherSize.self, value: g.size) })
                .onPreferenceChange(LauncherSize.self) { size = $0 }
                .position(drag ?? restingPoint(in: geo.size))
                .gesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .local)
                        .onChanged { drag = clamp($0.location, in: geo.size) }
                        .onEnded { end in
                            let p = clamp(end.predictedEndLocation, in: geo.size)
                            let room = max(1, geo.size.height - size.height - Self.margin * 2)
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                right = p.x > geo.size.width / 2
                                height = min(1, max(0, (p.y - size.height / 2 - Self.margin) / room))
                                drag = nil
                            }
                            UserDefaults.standard.set(right, forKey: Self.sideKey)
                            UserDefaults.standard.set(height, forKey: Self.heightKey)
                        }
                )
        }
        .opacity(controller.isEditing ? 0 : 1)
        .allowsHitTesting(!controller.isEditing)
        .animation(.easeOut(duration: 0.15), value: controller.isEditing)
    }

    private func restingPoint(in area: CGSize) -> CGPoint {
        let rx = size.width / 2 + Self.margin, ry = size.height / 2 + Self.margin
        let room = max(0, area.height - ry * 2)
        return CGPoint(x: right ? area.width - rx : rx, y: ry + room * height)
    }

    private func clamp(_ p: CGPoint, in area: CGSize) -> CGPoint {
        let rx = size.width / 2 + Self.margin, ry = size.height / 2 + Self.margin
        return CGPoint(x: min(max(p.x, rx), max(rx, area.width - rx)), y: min(max(p.y, ry), max(ry, area.height - ry)))
    }
}

private struct LauncherSize: PreferenceKey {
    static var defaultValue = CGSize(width: 60, height: 44)
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// The pill itself (Studio's .st-orb in studio-sky.css).
struct VaniLauncher: View {
    var working: Bool
    var full: Bool
    var action: () -> Void

    private static let cream = Color(red: 1, green: 252 / 255, blue: 247 / 255)
    private static let edge = Color(red: 38 / 255, green: 30 / 255, blue: 22 / 255)
    private static let shadow = Color(red: 58 / 255, green: 44 / 255, blue: 30 / 255)
    private static let muted = Color(red: 0x9b / 255, green: 0x91 / 255, blue: 0x86 / 255)
    private static let purple = Color(red: 122 / 255, green: 95 / 255, blue: 214 / 255)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Nimbo spills over the pill's edges, as in Studio.
                Nimbo(mood: working ? .thinking : .hello, width: 56)
                    .padding(EdgeInsets(top: -12, leading: -4, bottom: -8, trailing: -2))
                if full {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ask Vani")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(NimboArt.ink)
                        Text(working ? "Vani is working…" : "Describe a change")
                            .font(.system(size: 12))
                            .foregroundStyle(working ? Self.purple : Self.muted)
                            .lineLimit(1)
                    }
                }
            }
            .padding(full ? EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 18) : EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            .background(Capsule().fill(.ultraThinMaterial))
            .background(Capsule().fill(Self.cream.opacity(0.9)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 1).padding(1))
            .overlay(Capsule().strokeBorder(working ? Self.purple.opacity(0.35) : Self.edge.opacity(0.1), lineWidth: 1))
            .shadow(color: Self.shadow.opacity(0.3), radius: 14, y: 10)
            .overlay {
                if working && !reduceMotion {
                    // stOrbPulse: a ring 4 points out, swelling and fading every 1.8 s.
                    TimelineView(.animation) { tl in
                        let p = NimboArt.phase(tl.date.timeIntervalSinceReferenceDate, 1.8)
                        let e = 1 - pow(1 - p, 2.2)
                        Capsule().stroke(Self.purple.opacity(0.35), lineWidth: 1.5)
                            .padding(-4)
                            .scaleEffect(0.97 + 0.11 * e)
                            .opacity(1 - e)
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(LauncherPress())
        .accessibilityLabel(working ? "Vani AI, working" : "Ask Vani")
    }
}

private struct LauncherPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
#endif
