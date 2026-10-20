#if canImport(UIKit)
import SwiftUI
import UIKit

/// What the editor's header shows: a back arrow, Sigma's mark, the sheet's
/// title with where its edits are, and sharing. Pass it to ``SigmaSheetView``;
/// use ``hidden`` when your screen has its own bar.
///
/// ```swift
/// SigmaSheetView(session: session, header: SigmaHeader(showsLogo: false))
/// SigmaSheetView(session: session, header: .hidden)
/// SigmaSheetView(session: session, header: SigmaHeader { router.pop() })
/// ```
public struct SigmaHeader {
    /// Show the header at all.
    public var isVisible: Bool
    /// Show the back arrow. It calls ``onBack``, or SwiftUI's dismiss (pop or close) when that is nil.
    public var showsBack: Bool
    /// Show Sigma's mark beside the title.
    public var showsLogo: Bool
    /// What the back arrow does.
    public var onBack: (() -> Void)?

    public init(showsBack: Bool = true, showsLogo: Bool = true, onBack: (() -> Void)? = nil) {
        self.isVisible = true
        self.showsBack = showsBack
        self.showsLogo = showsLogo
        self.onBack = onBack
    }

    /// The default: back arrow, mark, title and sharing.
    public static var standard: SigmaHeader { SigmaHeader() }

    /// No header: the editor starts at the formula bar.
    public static var hidden: SigmaHeader {
        var h = SigmaHeader()
        h.isVisible = false
        return h
    }
}

/// The header itself: ← Σ  Title · Saved  share.
struct HeaderBar: View {
    let header: SigmaHeader
    let title: String
    let status: String
    let canShare: Bool
    let canRename: Bool
    let back: () -> Void
    let rename: () -> Void
    let share: (CGRect) -> Void
    @State private var shareFrame: CGRect = .zero

    var body: some View {
        HStack(spacing: 4) {
            if header.showsBack {
                Button(action: back) { SigmaGlyph(icon: .back, size: 24, color: Color(GridColors.ink)).frame(width: 40, height: 40) }
                    .accessibilityLabel("Back")
            }
            if header.showsLogo { SigmaMark().padding(.horizontal, 4) }
            Button(action: rename) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title.isEmpty ? "Sheet" : title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(GridColors.ink))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !status.isEmpty {
                        Text(status).font(.system(size: 12)).foregroundStyle(Color(GridColors.secondary)).lineLimit(1)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .disabled(!canRename)
            .accessibilityLabel(canRename ? "\(title), rename" : title)
            if canShare {
                Button { share(shareFrame) } label: { SigmaGlyph(icon: .share, size: 24, color: Color(GridColors.ink)).frame(width: 40, height: 40) }
                    .background(GeometryReader { g in
                        Color.clear
                            .onAppear { shareFrame = g.frame(in: .global) }
                            .onChange(of: g.frame(in: .global)) { shareFrame = $0 }
                    })
                    .accessibilityLabel("Share")
            }
        }
        .buttonStyle(.plain)
        // Without the arrow, the mark or the title sits off the edge.
        .padding(.leading, header.showsBack ? 4 : 10)
        .padding(.trailing, 6)
        .frame(height: 52)
        .background(Color.white)
    }
}

/// Sigma's mark: a green tile with Σ, as on the web.
struct SigmaMark: View {
    var body: some View {
        Text("Σ")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(
                LinearGradient(colors: [Color(red: 52 / 255, green: 168 / 255, blue: 83 / 255), Color(red: 24 / 255, green: 128 / 255, blue: 56 / 255)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}
#endif
