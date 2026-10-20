#if canImport(UIKit)
import SwiftUI

/// Nimbo, Vani's mascot, as Website Studio draws him (public/js/nimbo.js and
/// public/css/nimbo.css in Nimbus Cloud): the same shapes, colours and
/// motion, in the same 170 × 160 box. The moods Vani's launcher and panel use.
struct Nimbo: View {
    enum Mood { case hello, thinking, loading }
    var mood: Mood
    var width: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                ctx.scaleBy(x: size.width / 170, y: size.height / 160)
                NimboArt.draw(in: &ctx, mood: mood, time: t)
            }
        }
        .frame(width: width, height: width * 160 / 170)
        .accessibilityHidden(true)
    }
}

enum NimboArt {
    static let ink = Color(red: 0x1f / 255, green: 0x1a / 255, blue: 0x15 / 255)
    static let cream = Color(red: 1, green: 0xf8 / 255, blue: 0xef / 255)
    static let ember = Color(red: 0xf0 / 255, green: 0x4e / 255, blue: 0x28 / 255)
    static let amber = Color(red: 0xf5 / 255, green: 0xa6 / 255, blue: 0x23 / 255)
    static let sky = Color(red: 0xbc / 255, green: 0xd9 / 255, blue: 0xf5 / 255)
    static let socket = Color(red: 0xe9 / 255, green: 0xdf / 255, blue: 0xd2 / 255)

    // MARK: Timing, as CSS keyframes with ease-in-out between them

    static func ease(_ x: Double) -> Double { let s = min(max(x, 0), 1); return s * s * (3 - 2 * s) }
    static func phase(_ t: Double, _ period: Double, delay: Double = 0) -> Double { let p = (t - delay) / period; return p - p.rounded(.down) }
    /// 0 → 1 at the middle → 0: every "50% { … }" keyframe.
    static func swing(_ p: Double) -> Double { ease(p < 0.5 ? p * 2 : (1 - p) * 2) }
    /// A value through keyframes (offset 0…1, value), eased between each pair.
    static func keyframes(_ p: Double, _ frames: [(Double, Double)]) -> Double {
        guard let first = frames.first else { return 0 }
        if p <= first.0 { return first.1 }
        for (a, b) in zip(frames, frames.dropFirst()) where p <= b.0 {
            return a.1 + (b.1 - a.1) * ease((p - a.0) / max(b.0 - a.0, 0.0001))
        }
        return frames.last!.1
    }

    // MARK: Shapes

    static func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)) }
    static func line(_ build: (inout Path) -> Void) -> Path { var p = Path(); build(&p); return p }
    static func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    static let shape: Path = {
        var p = Path()
        p.addPath(circle(46, 96, 24)); p.addPath(circle(66, 72, 26)); p.addPath(circle(96, 62, 30)); p.addPath(circle(124, 86, 24))
        p.addRoundedRect(in: CGRect(x: 30, y: 92, width: 112, height: 34), cornerSize: CGSize(width: 17, height: 17))
        return p
    }()

    /// Turns `ctx` about `o`: the CSS transform-origin.
    static func about(_ ctx: inout GraphicsContext, _ o: CGPoint, _ apply: (inout GraphicsContext) -> Void) {
        ctx.translateBy(x: o.x, y: o.y); apply(&ctx); ctx.translateBy(x: -o.x, y: -o.y)
    }

    static func hand(_ c: inout GraphicsContext, _ x: CGFloat, _ y: CGFloat) {
        c.fill(circle(x, y, 9), with: .color(cream))
        c.stroke(circle(x, y, 9), with: .color(ink), lineWidth: 4.5)
    }

    static func pupils(_ c: inout GraphicsContext) {
        for x in [76.0, 100.0] { c.fill(Path(ellipseIn: CGRect(x: x - 5, y: 89 - 6.5, width: 10, height: 13)), with: .color(ink)) }
        for x in [78.0, 102.0] { c.fill(circle(x, 86.5, 1.8), with: .color(.white)) }
    }

    // MARK: Drawing

    static func draw(in ctx: inout GraphicsContext, mood: Nimbo.Mood, time t: Double) {
        let round = StrokeStyle(lineWidth: 4, lineCap: .round)
        ctx.drawLayer { outer in
            if mood == .loading {
                // nb-wait: he looks one way, the other, then up, leaning as he looks.
                let p = phase(t, 3.6)
                let rot = keyframes(p, [(0, 0), (0.06, 0), (0.16, -5), (0.30, -5), (0.42, 5), (0.58, 5), (0.70, -1), (0.86, -1), (1, 0)])
                let dx = keyframes(p, [(0, 0), (0.06, 0), (0.16, -4), (0.30, -4), (0.42, 4), (0.58, 4), (0.70, 0), (0.86, 0), (1, 0)])
                let dy = keyframes(p, [(0, 0), (0.58, 0), (0.70, -4), (0.86, -4), (1, 0)])
                about(&outer, pt(89, 85)) { $0.rotate(by: .degrees(rot)); $0.translateBy(x: dx, y: dy) }
            } else {
                // nb-bob: 5 up and back every 2.8 s.
                outer.translateBy(x: 0, y: -5 * swing(phase(t, 2.8)))
            }
            outer.drawLayer { b in
                // nb-breathe, about the middle of him.
                let br = swing(phase(t, 3.6))
                about(&b, pt(mood == .thinking ? 85 : 89, 79)) { $0.scaleBy(x: 1 + 0.025 * br, y: 1 - 0.025 * br) }

                // Body: an ink outline, cream inside, an ember band clipped to it.
                b.stroke(shape, with: .color(ink), lineWidth: 10)
                b.fill(shape, with: .color(ink))
                b.fill(shape, with: .color(cream))
                b.drawLayer { band in
                    band.clip(to: shape)
                    band.fill(line { $0.move(to: pt(0, 104)); $0.addQuadCurve(to: pt(172, 104), control: pt(86, 122)); $0.addLine(to: pt(172, 115)); $0.addQuadCurve(to: pt(0, 115), control: pt(86, 133)); $0.closeSubpath() }, with: .color(ember))
                    band.stroke(line { $0.move(to: pt(0, 104)); $0.addQuadCurve(to: pt(172, 104), control: pt(86, 122)); $0.move(to: pt(0, 115)); $0.addQuadCurve(to: pt(172, 115), control: pt(86, 133)) }, with: .color(ink), lineWidth: 4)
                }

                // Goggles, up on his head; nb-glint dims them at 80% of 2.6 s.
                b.stroke(line { $0.move(to: pt(50, 58)); $0.addQuadCurve(to: pt(126, 58), control: pt(88, 42)) }, with: .color(ink), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                for (x, y) in [(76.0, 52.0), (102.0, 50.0)] {
                    b.fill(circle(x, y, 12), with: .color(sky))
                    b.stroke(circle(x, y, 12), with: .color(ink), lineWidth: 5)
                }
                b.drawLayer { g in
                    g.opacity = keyframes(phase(t, 2.6), [(0, 0.9), (0.7, 0.9), (0.8, 0.2), (1, 0.9)])
                    // The SVG arcs "M70 47 A7 7 0 0 1 77 43" and "M96 45 A7 7 0 0 1 103 41".
                    g.stroke(line {
                        $0.move(to: pt(70, 47)); $0.addArc(center: pt(76.34, 49.97), radius: 7, startAngle: .degrees(205.1), endAngle: .degrees(275.4), clockwise: false)
                        $0.move(to: pt(96, 45)); $0.addArc(center: pt(102.34, 47.97), radius: 7, startAngle: .degrees(205.1), endAngle: .degrees(275.4), clockwise: false)
                    }, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }

                // Eyes.
                b.drawLayer { e in
                    switch mood {
                    case .loading:
                        // nb-look: off to one side, the other, then up; nb-lids blink at 38% and 90%.
                        let p = phase(t, 3.6)
                        let lx = keyframes(p, [(0, 0), (0.06, 0), (0.14, -8), (0.30, -8), (0.40, 9), (0.58, 9), (0.68, 3), (0.86, 3), (1, 0)])
                        let ly = keyframes(p, [(0, 0), (0.06, 0), (0.14, 1), (0.30, 1), (0.40, 0), (0.58, 0), (0.68, -7), (0.86, -7), (1, 0)])
                        e.translateBy(x: lx, y: ly)
                        let lid = keyframes(p, [(0, 1), (0.36, 1), (0.38, 0.1), (0.40, 1), (0.88, 1), (0.90, 0.1), (0.92, 1), (1, 1)])
                        about(&e, pt(88, 89)) { $0.scaleBy(x: 1, y: lid) }
                    default:
                        if mood == .thinking { e.translateBy(x: 2, y: -4) }
                        // nb-blink: shut at 47% of 4.2 s.
                        let sy = keyframes(phase(t, 4.2), [(0, 1), (0.44, 1), (0.47, 0.08), (0.50, 1), (1, 1)])
                        about(&e, pt(88, 89)) { $0.scaleBy(x: 1, y: sy) }
                    }
                    pupils(&e)
                }
                // Brows: raised; while loading they lift as each dot lands.
                b.drawLayer { br in
                    if mood == .loading {
                        br.translateBy(x: 0, y: keyframes(phase(t, 1.2), [(0, 0), (0.7, 0), (0.8, -3), (1, 0)]))
                        br.stroke(line {
                            $0.move(to: pt(69, 75)); $0.addQuadCurve(to: pt(81, 75), control: pt(75, 72))
                            $0.move(to: pt(95, 75)); $0.addQuadCurve(to: pt(107, 75), control: pt(101, 72))
                        }, with: .color(ink), style: round)
                    } else {
                        br.stroke(line {
                            $0.move(to: pt(69, 74)); $0.addQuadCurve(to: pt(81, 73), control: pt(75, 70))
                            $0.move(to: pt(95, 73)); $0.addQuadCurve(to: pt(107, 74), control: pt(101, 70))
                        }, with: .color(ink), style: round)
                    }
                }
                // Mouth.
                switch mood {
                case .hello:
                    let grin = line { $0.move(to: pt(78, 99)); $0.addQuadCurve(to: pt(100, 98), control: pt(89, 114)); $0.addQuadCurve(to: pt(78, 99), control: pt(89, 104)); $0.closeSubpath() }
                    b.fill(grin, with: .color(ink))
                    b.stroke(grin, with: .color(ink), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                    b.stroke(line { $0.move(to: pt(84, 106)); $0.addQuadCurve(to: pt(94, 105), control: pt(89, 109)) }, with: .color(ember), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                case .thinking:
                    b.fill(Path(ellipseIn: CGRect(x: 85, y: 98, width: 8, height: 10)), with: .color(ink))
                case .loading:
                    b.stroke(line { $0.move(to: pt(84, 102)); $0.addQuadCurve(to: pt(94, 102), control: pt(89, 100)) }, with: .color(ink), style: round)
                }
                // Cheeks.
                for x in [64.0, 112.0] { b.fill(circle(x, 100, 5), with: .color(amber.opacity(0.55))) }

                // Hands.
                switch mood {
                case .hello:
                    b.drawLayer { w in
                        // nb-wave: -8° → 26° → -8° every 1.1 s, about 20% 90% of the hand.
                        about(&w, pt(141 + 18 * 0.2, 61 + 18 * 0.9)) { $0.rotate(by: .degrees(-8 + 34 * swing(phase(t, 1.1)))) }
                        hand(&w, 150, 70)
                    }
                    hand(&b, 28, 112)
                case .thinking:
                    hand(&b, 96, 116)
                case .loading:
                    // nb-tap: a hand taps; nb-shade: the other comes up to shade his eyes.
                    b.drawLayer { h in
                        h.translateBy(x: 0, y: 5 * swing(phase(t, 0.6)))
                        hand(&h, 142, 112)
                    }
                    b.drawLayer { h in
                        let p = phase(t, 3.6)
                        let k = keyframes(p, [(0, 0), (0.34, 0), (0.42, 1), (0.58, 1), (0.64, 0), (1, 0)])
                        h.opacity = k
                        h.translateBy(x: -12 * k, y: -42 * k)
                        hand(&h, 128, 120)
                    }
                }
            }
        }
        switch mood {
        case .thinking:
            // Three dots rise beside him.
            for (x, y, r, color, delay) in [(140.0, 40.0, 5.0, amber, 0.0), (153.0, 28.0, 6.5, amber, 0.2), (166.0, 14.0, 8.0, ember, 0.4)] {
                let s = swing(phase(t, 1.2, delay: delay))
                ctx.drawLayer { d in
                    d.opacity = 0.25 + 0.75 * s
                    d.translateBy(x: x, y: y); d.scaleBy(x: 0.8 + 0.35 * s, y: 0.8 + 0.35 * s)
                    d.fill(circle(0, 0, r), with: .color(color))
                }
            }
        case .loading:
            // nb-fill: three dots below him fill in turn.
            for (x, delay) in [(66.0, 0.0), (86.0, 0.4), (106.0, 0.8)] {
                let k = keyframes(phase(t, 1.2, delay: delay), [(0, 0), (0.4, 1), (0.6, 1), (1, 0)])
                ctx.drawLayer { d in
                    d.translateBy(x: x, y: 138); d.scaleBy(x: 0.85 + 0.3 * k, y: 0.85 + 0.3 * k)
                    d.fill(circle(0, 0, 6), with: .color(socket))
                    d.opacity = k
                    d.fill(circle(0, 0, 6), with: .color(amber))
                }
            }
        case .hello:
            break
        }
    }
}
#endif
