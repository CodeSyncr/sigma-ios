import CoreGraphics
import Foundation

/// SVG path data as a CGPath: enough of the grammar for the editor's icons
/// (M L H V C S Q T Z, absolute and relative, with implicit repeats).
enum SVGPath {
    static func parse(_ d: String) -> CGPath {
        let path = CGMutablePath()
        var scanner = Tokens(d)
        var current = CGPoint.zero
        var start = CGPoint.zero
        // The last control point, for S and T, which reflect it.
        var lastCubic: CGPoint?
        var lastQuad: CGPoint?
        var command: Character = "M"

        while let next = scanner.nextCommand(previous: command) {
            command = next
            let relative = command.isLowercase
            func point() -> CGPoint? {
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }
            var cubic: CGPoint?
            var quad: CGPoint?
            switch command.uppercased() {
            case "M":
                guard let p = point() else { return path }
                path.move(to: p)
                current = p
                start = p
                // Pairs after a moveto are linetos.
                command = relative ? "l" : "L"
            case "L":
                guard let p = point() else { return path }
                path.addLine(to: p)
                current = p
            case "H":
                guard let x = scanner.number() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
            case "V":
                guard let y = scanner.number() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
            case "C":
                guard let c1 = point(), let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                cubic = c2
                current = p
            case "S":
                let c1 = lastCubic.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                guard let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                cubic = c2
                current = p
            case "Q":
                guard let c = point(), let p = point() else { return path }
                path.addQuadCurve(to: p, control: c)
                quad = c
                current = p
            case "T":
                let c = lastQuad.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                guard let p = point() else { return path }
                path.addQuadCurve(to: p, control: c)
                quad = c
                current = p
            case "Z":
                path.closeSubpath()
                current = start
            default:
                return path
            }
            lastCubic = cubic
            lastQuad = quad
        }
        return path
    }

    /// Commands and numbers, in the compact form SVG allows ("M280-200v-80h284q63 0 109.5-40").
    private struct Tokens {
        private let chars: [Character]
        private var i = 0

        init(_ s: String) { chars = Array(s) }

        private mutating func skipSeparators() {
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" || chars[i] == "\t" { i += 1 }
        }

        /// The next command letter, or the previous one again when numbers follow without one.
        mutating func nextCommand(previous: Character) -> Character? {
            skipSeparators()
            guard i < chars.count else { return nil }
            let c = chars[i]
            if c.isLetter, c != "e", c != "E" {
                i += 1
                return c
            }
            // Z takes no numbers, so it cannot repeat.
            return previous.uppercased() == "Z" ? nil : previous
        }

        mutating func number() -> CGFloat? {
            skipSeparators()
            let begin = i
            if i < chars.count, chars[i] == "-" || chars[i] == "+" { i += 1 }
            var dot = false
            while i < chars.count {
                let c = chars[i]
                if c.isNumber { i += 1 }
                else if c == ".", !dot { dot = true; i += 1 }
                else if c == "e" || c == "E" {
                    i += 1
                    if i < chars.count, chars[i] == "-" || chars[i] == "+" { i += 1 }
                }
                else { break }
            }
            guard i > begin, let v = Double(String(chars[begin..<i])) else { return nil }
            return CGFloat(v)
        }
    }
}

extension SigmaIcon {
    // Guarded by lock.
    nonisolated(unsafe) private static var cache: [SigmaIcon: CGPath] = [:]
    private static let lock = NSLock()

    /// The glyph in its own 960-unit box, top at y = -960, parsed once.
    var cgPath: CGPath {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        if let p = Self.cache[self] { return p }
        let p = SVGPath.parse(path)
        Self.cache[self] = p
        return p
    }
}

#if canImport(UIKit)
import SwiftUI

/// One of the editor's icons, the same glyph as on Android.
struct SigmaGlyph: View {
    let icon: SigmaIcon
    var size: CGFloat = 18
    var color: Color = .primary

    var body: some View {
        GlyphShape(icon: icon)
            .fill(color)
            .frame(width: size, height: size)
            .flipsForRightToLeftLayoutDirection(icon.mirrored)
            .accessibilityHidden(true)
    }

    private struct GlyphShape: Shape {
        let icon: SigmaIcon

        func path(in rect: CGRect) -> Path {
            let s = min(rect.width, rect.height) / 960
            var t = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: s, y: s).translatedBy(x: 0, y: 960)
            return Path(icon.cgPath.copy(using: &t) ?? icon.cgPath)
        }
    }
}
#endif
