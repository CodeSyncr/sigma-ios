#if canImport(UIKit)
import SwiftUI

/// Vani AI as a floating ball over the grid: tap opens the Vani panel; drag
/// it anywhere and it snaps to the nearer side. Its spot is remembered for
/// the app. Hidden while a cell is being edited.
struct VaniBall: View {
    @ObservedObject var controller: SigmaGridController

    static let size: CGFloat = 52
    private static let margin: CGFloat = 12
    private static let sideKey = "NimbusSigma.vaniBall.right"
    private static let heightKey = "NimbusSigma.vaniBall.height"

    /// Which side it rests on, and how far down (0 top … 1 bottom) of the room it has.
    @State private var right = UserDefaults.standard.object(forKey: VaniBall.sideKey) as? Bool ?? true
    @State private var height = UserDefaults.standard.object(forKey: VaniBall.heightKey) as? Double ?? 1
    @State private var drag: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let rest = restingPoint(in: geo.size)
            ball
                .position(drag ?? rest)
                .gesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .local)
                        .onChanged { drag = clamp($0.location, in: geo.size) }
                        .onEnded { end in
                            let p = clamp(end.predictedEndLocation, in: geo.size)
                            let room = max(1, geo.size.height - Self.size - Self.margin * 2)
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                right = p.x > geo.size.width / 2
                                height = min(1, max(0, (p.y - Self.size / 2 - Self.margin) / room))
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

    private var ball: some View {
        Button { controller.panel = .ai } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Self.size, height: Self.size)
                .background(
                    LinearGradient(colors: [Color(red: 0.91, green: 0.3, blue: 0.24), Color(red: 0.98, green: 0.45, blue: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Circle()
                )
                .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Vani AI")
    }

    private func restingPoint(in size: CGSize) -> CGPoint {
        let r = Self.size / 2 + Self.margin
        let room = max(0, size.height - r * 2)
        return CGPoint(x: right ? size.width - r : r, y: r + room * height)
    }

    private func clamp(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let r = Self.size / 2 + Self.margin
        return CGPoint(x: min(max(p.x, r), max(r, size.width - r)), y: min(max(p.y, r), max(r, size.height - r)))
    }
}
#endif
