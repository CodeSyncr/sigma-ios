#if canImport(UIKit)
import UIKit

/// Sigma's palette for the grid, matching the web editor.
enum GridColors {
    static let ink = UIColor(red: 0.12, green: 0.14, blue: 0.16, alpha: 1)
    static let error = UIColor(red: 0.85, green: 0.19, blue: 0.15, alpha: 1)
    static let gridline = UIColor(red: 0.886, green: 0.894, blue: 0.906, alpha: 1)
    static let border = UIColor(red: 0.24, green: 0.25, blue: 0.27, alpha: 1)
    static let header = UIColor(red: 0.965, green: 0.969, blue: 0.976, alpha: 1)
    static let headerText = UIColor(red: 0.37, green: 0.39, blue: 0.42, alpha: 1)
    static let accent = UIColor(red: 0.094, green: 0.502, blue: 0.22, alpha: 1)
    static let accentSoft = UIColor(red: 0.094, green: 0.502, blue: 0.22, alpha: 0.10)
    static let headerSelected = UIColor(red: 0.886, green: 0.945, blue: 0.898, alpha: 1)
    static let note = UIColor(red: 0.95, green: 0.6, blue: 0.0, alpha: 1)
    static let frozenLine = UIColor(red: 0.74, green: 0.76, blue: 0.79, alpha: 1)

    static func hex(_ s: String?) -> UIColor? {
        guard var h = s?.trimmingCharacters(in: .whitespaces), h.hasPrefix("#") else { return nil }
        h.removeFirst()
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let n = UInt32(h, radix: 16) else { return nil }
        return UIColor(red: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: 1)
    }
}

/// The default text size of a cell, as on the web (13px there, 13pt here).
let gridFontSize: CGFloat = 13

func gridFont(_ style: SigmaStyle?) -> UIFont {
    let size = CGFloat(style?.fontSize ?? Double(gridFontSize))
    var font = UIFont.systemFont(ofSize: size, weight: style?.bold == true ? .semibold : .regular)
    if style?.italic == true, let d = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitItalic)) {
        font = UIFont(descriptor: d, size: size)
    }
    return font
}

/// One cell, drawn: its fill, text, borders and the gridlines on its right and bottom.
final class GridCellView: UIView {
    struct Content: Equatable {
        var text = ""
        var isNumber = false
        var isError = false
        var style: SigmaStyle?
        var hasNote = false
    }

    var content = Content() {
        didSet { if content != oldValue { setNeedsDisplay() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let b = bounds
        let style = content.style
        (GridColors.hex(style?.fill) ?? .white).setFill()
        ctx.fill(b)

        let hair = 1 / max(1, window?.screen.scale ?? UIScreen.main.scale)
        GridColors.gridline.setFill()
        ctx.fill(CGRect(x: b.maxX - hair, y: 0, width: hair, height: b.height))
        ctx.fill(CGRect(x: 0, y: b.maxY - hair, width: b.width, height: hair))

        if !content.text.isEmpty {
            let font = gridFont(style)
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: content.isError ? GridColors.error : (GridColors.hex(style?.textColor) ?? GridColors.ink),
            ]
            if style?.underline == true { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if style?.strikethrough == true { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            let text = NSAttributedString(string: content.text.replacingOccurrences(of: "\n", with: " "), attributes: attrs)
            let size = text.size()
            let pad: CGFloat = 5
            let align: SigmaStyle.Align = style?.align ?? (content.isNumber ? .right : content.isError ? .center : .left)
            let x: CGFloat
            switch align {
            case .left: x = pad
            case .center: x = (b.width - size.width) / 2
            case .right: x = b.width - pad - size.width
            }
            ctx.saveGState()
            ctx.clip(to: b.insetBy(dx: 1, dy: 0))
            text.draw(at: CGPoint(x: x, y: (b.height - size.height) / 2))
            ctx.restoreGState()
        }

        if let style {
            GridColors.border.setFill()
            if style.borderTop == true { ctx.fill(CGRect(x: 0, y: 0, width: b.width, height: 1)) }
            if style.borderBottom == true { ctx.fill(CGRect(x: 0, y: b.maxY - 1, width: b.width, height: 1)) }
            if style.borderLeft == true { ctx.fill(CGRect(x: 0, y: 0, width: 1, height: b.height)) }
            if style.borderRight == true { ctx.fill(CGRect(x: b.maxX - 1, y: 0, width: 1, height: b.height)) }
        }

        if content.hasNote {
            GridColors.note.setFill()
            let t = UIBezierPath()
            t.move(to: CGPoint(x: b.maxX - 7, y: 0))
            t.addLine(to: CGPoint(x: b.maxX, y: 0))
            t.addLine(to: CGPoint(x: b.maxX, y: 7))
            t.close()
            t.fill()
        }
    }
}

/// A column letter or row number.
final class GridHeaderView: UIView {
    var title = "" { didSet { if title != oldValue { setNeedsDisplay() } } }
    var highlighted = false { didSet { if highlighted != oldValue { setNeedsDisplay() } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let b = bounds
        (highlighted ? GridColors.headerSelected : GridColors.header).setFill()
        ctx.fill(b)
        let hair = 1 / max(1, window?.screen.scale ?? UIScreen.main.scale)
        GridColors.gridline.setFill()
        ctx.fill(CGRect(x: b.maxX - hair, y: 0, width: hair, height: b.height))
        ctx.fill(CGRect(x: 0, y: b.maxY - hair, width: b.width, height: hair))
        let text = NSAttributedString(string: title, attributes: [
            .font: UIFont.systemFont(ofSize: 11, weight: highlighted ? .semibold : .medium),
            .foregroundColor: highlighted ? GridColors.accent : GridColors.headerText,
        ])
        let size = text.size()
        text.draw(at: CGPoint(x: (b.width - size.width) / 2, y: (b.height - size.height) / 2))
    }
}
#endif
