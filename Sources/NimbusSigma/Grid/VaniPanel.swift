#if canImport(UIKit)
import SwiftUI

/// Vani AI in the sheet, drawn as Website Studio's Vani panel: Nimbo and
/// "Vani" in the header, his greeting when the chat is empty, cream and ink
/// bubbles, Nimbo waiting while an answer comes, and the composer. Ask, read
/// the answer, apply the change it proposes (as one undo step).
struct VaniPanel: View {
    @ObservedObject var session: SigmaSession
    @ObservedObject var controller: SigmaGridController
    @State private var prompt = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    static let suggestions = [
        "Add a total row and format it",
        "Chart this data",
        "Highlight values above average",
        "Build a monthly budget for a family of four",
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if controller.aiMessages.isEmpty && !controller.aiWorking {
                            VaniGreeting { s in prompt = s; send() }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 28)
                        }
                        ForEach($controller.aiMessages) { $m in
                            VaniTurn(message: $m) { apply(&$0) }.id(m.id)
                        }
                        if controller.aiWorking {
                            // Studio's DOTS: Nimbo waits for the answer to arrive.
                            VStack(alignment: .leading, spacing: 2) {
                                Nimbo(mood: .loading, width: 64)
                                Text("Thinking").font(.system(size: 11.5)).foregroundStyle(VaniStyle.mute).padding(.leading, 4)
                            }
                            .id("working")
                        }
                        if let failure = controller.aiFailure {
                            VaniBubble(text: failure, kind: .failed).id("failed")
                        }
                    }
                    .padding(EdgeInsets(top: 14, leading: 16, bottom: 10, trailing: 16))
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: controller.aiMessages.count) { _ in
                    withAnimation { scroller.scrollTo(controller.aiMessages.last?.id, anchor: .bottom) }
                }
                .onChange(of: controller.aiWorking) { on in
                    if on { withAnimation { scroller.scrollTo("working", anchor: .bottom) } }
                }
            }
            composer
        }
        .background(VaniStyle.paper.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Header (Studio's .vai-head)

    private var header: some View {
        HStack(spacing: 10) {
            Nimbo(mood: controller.aiWorking ? .thinking : .hello, width: 42)
                .padding(.top, -4).padding(.bottom, -6)
            VStack(alignment: .leading, spacing: 2) {
                Text("Vani").font(.system(size: 16, weight: .semibold)).foregroundStyle(NimboArt.ink)
                Text("Editing " + (session.document?.title ?? "this sheet"))
                    .font(.system(size: 12)).foregroundStyle(VaniStyle.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                VaniHeadButton(symbol: "plus", label: "New chat") {
                    controller.aiMessages = []
                    controller.aiFailure = nil
                }
                .disabled(controller.aiMessages.isEmpty || controller.aiWorking)
                VaniHeadButton(symbol: "xmark", label: "Close") { dismiss() }
            }
        }
        .padding(EdgeInsets(top: 18, leading: 14, bottom: 12, trailing: 12))
        .overlay(alignment: .bottom) { Rectangle().fill(VaniStyle.line).frame(height: 1) }
    }

    // MARK: Composer (Studio's .vai-inputbox)

    private var composer: some View {
        let empty = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            TextField("Ask about this sheet, or describe a change", text: $prompt, axis: .vertical)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(NimboArt.ink)
                .lineLimit(1...5)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(send)
                .padding(.horizontal, 8).padding(.vertical, 4)
            HStack {
                Spacer()
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NimboArt.cream)
                        .frame(width: 40, height: 40)
                        .background(NimboArt.ink, in: Circle())
                        .shadow(color: Color(red: 217 / 255, green: 83 / 255, blue: 42 / 255).opacity(0.3), radius: 5, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(empty || controller.aiWorking)
                .opacity(empty || controller.aiWorking ? 0.45 : 1)
                .accessibilityLabel("Send")
            }
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 8, trailing: 10))
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(focused ? VaniStyle.ember.opacity(0.4) : VaniStyle.line2, lineWidth: 1))
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(VaniStyle.ember.opacity(focused ? 0.07 : 0)).padding(-4))
        .shadow(color: (focused ? VaniStyle.ember : VaniStyle.shadow).opacity(0.14), radius: 16, y: 12)
        .padding(EdgeInsets(top: 4, leading: 12, bottom: 12, trailing: 12))
        .animation(.easeOut(duration: 0.2), value: focused)
    }

    // MARK: Asking

    private func send() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !controller.aiWorking else { return }
        let history = controller.aiMessages
        controller.aiMessages.append(SigmaAIMessage(role: .user, text: text))
        prompt = ""
        controller.aiFailure = nil
        controller.aiWorking = true
        let session = session, controller = controller
        Task {
            do {
                let answer = try await session.ask(text, history: history, selection: controller.selection)
                controller.aiMessages.append(answer)
            } catch {
                controller.aiFailure = (error as? SigmaError)?.errorDescription ?? error.localizedDescription
            }
            controller.aiWorking = false
        }
    }

    private func apply(_ message: inout SigmaAIMessage) {
        guard let patch = message.patch, message.applied == nil, let book = session.workbook else { return }
        do {
            message.applied = try book.applyPatch(patch).summary
        } catch {
            controller.aiFailure = (error as? SigmaError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Studio's colours for Vani (vani-ai.css with studio-sky.css over it).
enum VaniStyle {
    static let paper = Color(red: 0xfb / 255, green: 0xf7 / 255, blue: 0xf1 / 255)
    static let hairline = Color(red: 0xed / 255, green: 0xe6 / 255, blue: 0xdf / 255)
    static let line = Color(red: 38 / 255, green: 30 / 255, blue: 22 / 255).opacity(0.08)
    static let line2 = Color(red: 38 / 255, green: 30 / 255, blue: 22 / 255).opacity(0.16)
    static let shadow = Color(red: 58 / 255, green: 44 / 255, blue: 30 / 255)
    static let botText = Color(red: 0x46 / 255, green: 0x3f / 255, blue: 0x37 / 255)
    static let muted = Color(red: 0x9b / 255, green: 0x91 / 255, blue: 0x86 / 255)
    static let mute = Color(red: 0x9c / 255, green: 0x98 / 255, blue: 0x93 / 255)
    static let sub = Color(red: 0x6b / 255, green: 0x69 / 255, blue: 0x66 / 255)
    static let ember = Color(red: 0xf0 / 255, green: 0x4e / 255, blue: 0x28 / 255)
    static let orangeLight = Color(red: 1, green: 0xf1 / 255, blue: 0xea / 255)
    static let done = Color(red: 0x1f / 255, green: 0x7a / 255, blue: 0x55 / 255)
    static let failText = Color(red: 0xa4 / 255, green: 0x33 / 255, blue: 0x1a / 255)
    /// The ember-to-amber gradient Studio writes "Vani." and the invites in.
    static let gradient = LinearGradient(colors: [ember, Color(red: 1, green: 0x7a / 255, blue: 0x2f / 255), Color(red: 0xe8 / 255, green: 0x94 / 255, blue: 0x1a / 255)], startPoint: .leading, endPoint: .trailing)
}

/// Round header buttons (.vai-new, .vai-exit).
private struct VaniHeadButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(VaniStyle.sub)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }
}

/// The empty chat: Nimbo waves, "Hi, I'm Vani.", a line that changes every
/// few seconds, and a few ways to start.
private struct VaniGreeting: View {
    let start: (String) -> Void
    @State private var invite = 0
    @State private var shown = true

    private static let invites = [
        "What should this sheet work out?",
        "Describe a table and I build it: columns, formulas and formats",
        "Ask me to total, chart or tidy your data",
        "Select some cells first, and I work on those",
    ]
    private let timer = Timer.publish(every: 3.8, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Nimbo(mood: .hello, width: 120).padding(.bottom, 14)
            (Text("Hi, I'm ").foregroundColor(NimboArt.ink) + Text("Vani.").foregroundColor(VaniStyle.ember))
                .font(.system(size: 25.6, weight: .semibold))
                .tracking(-0.7)
                .overlay {
                    // "Vani." in Studio's gradient: the gradient shows through the word only.
                    VaniStyle.gradient.mask(
                        (Text("Hi, I'm ").foregroundColor(.clear) + Text("Vani.").foregroundColor(.black))
                            .font(.system(size: 25.6, weight: .semibold)).tracking(-0.7)
                    )
                    .allowsHitTesting(false)
                }
            Text(Self.invites[invite])
                .font(.system(size: 16, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(VaniStyle.gradient)
                .frame(maxWidth: 270, minHeight: 46, alignment: .top)
                .padding(.top, 10)
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : -7)
                .onReceive(timer) { _ in
                    withAnimation(.easeOut(duration: 0.35)) { shown = false }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                        invite = (invite + 1) % Self.invites.count
                        withAnimation(.easeOut(duration: 0.35)) { shown = true }
                    }
                }
            // Studio's .vai-chip: ways to start.
            VaniChips(items: VaniPanel.suggestions, pick: start).padding(.top, 14)
        }
        .padding(.horizontal, 10)
    }
}

private struct VaniChips: View {
    let items: [String]
    let pick: (String) -> Void
    var body: some View {
        VStack(spacing: 8) {
            ForEach(items, id: \.self) { s in
                Button { pick(s) } label: {
                    Text(s)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NimboArt.ink)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(VaniStyle.orangeLight, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One message: yours on the right in ink, Vani's on the left on white, with
/// the change it proposes under it.
private struct VaniTurn: View {
    @Binding var message: SigmaAIMessage
    let apply: (inout SigmaAIMessage) -> Void

    var body: some View {
        if message.role == .user {
            VaniBubble(text: message.text, kind: .user)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                VaniBubble(text: message.text, kind: .bot)
                if message.patch != nil {
                    if let done = message.applied {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(VaniStyle.done)
                            Text("Applied " + done).foregroundStyle(VaniStyle.sub)
                        }
                        .font(.system(size: 12.5, weight: .medium))
                        .padding(.leading, 4)
                    } else {
                        Button { apply(&message) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "wand.and.stars").font(.system(size: 13, weight: .semibold))
                                Text("Apply" + (message.patchSummary.map { " · \($0)" } ?? ""))
                                    .font(.system(size: 13, weight: .semibold))
                                    .multilineTextAlignment(.leading)
                            }
                            .foregroundStyle(NimboArt.cream)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(NimboArt.ink, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Studio's .vai-msg: 14 pt, rounded 16 with the corner nearest the speaker tucked in.
struct VaniBubble: View {
    enum Kind { case user, bot, failed }
    let text: String
    let kind: Kind

    var body: some View {
        let shape = BubbleShape(radius: 16, tucked: 5, right: kind == .user)
        let body = Text(Self.rich(text))
            .font(.system(size: 14))
            .lineSpacing(3.5)
            .foregroundStyle(kind == .user ? NimboArt.cream : kind == .bot ? VaniStyle.botText : VaniStyle.failText)
            .textSelection(.enabled)
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(kind == .user ? NimboArt.ink : kind == .bot ? Color.white : VaniStyle.ember.opacity(0.06), in: shape)
            .overlay(shape.stroke(kind == .user ? Color.clear : kind == .bot ? VaniStyle.hairline : VaniStyle.ember.opacity(0.3), lineWidth: 1))
            .shadow(color: kind == .bot ? Color(red: 38 / 255, green: 30 / 255, blue: 22 / 255).opacity(0.1) : .clear, radius: 8, y: 6)
        // On the speaker's side, leaving the other side clear (Studio: at most 84% wide).
        return HStack(spacing: 0) {
            if kind == .user { Spacer(minLength: 48) }
            body.fixedSize(horizontal: false, vertical: true)
            if kind != .user { Spacer(minLength: 48) }
        }
    }

    /// Bold, italics and code inline; "- " lines as bullets.
    static func rich(_ s: String) -> AttributedString {
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("- ") || t.hasPrefix("* ") { return "•  " + t.dropFirst(2) }
            return String(line)
        }
        let joined = lines.joined(separator: "\n")
        return (try? AttributedString(markdown: joined, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(joined)
    }
}

/// A rounded rectangle with one bottom corner tucked in.
struct BubbleShape: Shape {
    let radius: CGFloat
    let tucked: CGFloat
    let right: Bool

    func path(in r: CGRect) -> Path {
        let bl = right ? radius : tucked, br = right ? tucked : radius
        var p = Path()
        p.move(to: CGPoint(x: r.minX + radius, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addArc(center: CGPoint(x: r.maxX - radius, y: r.minY + radius), radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
        p.addArc(center: CGPoint(x: r.maxX - br, y: r.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX + bl, y: r.maxY))
        p.addArc(center: CGPoint(x: r.minX + bl, y: r.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addArc(center: CGPoint(x: r.minX + radius, y: r.minY + radius), radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}
#endif
