import Foundation

/// What a formula being typed needs help with: a function name to finish,
/// or the arguments of the call it is in. The same rules as Android's, so
/// both editors suggest the same things.
public enum FormulaHint: Equatable, Sendable {
    case none
    /// Functions a half-typed name could be, shortest first.
    case suggest(prefix: String, matches: [SigmaFunction])
    /// Inside a call: the function, and which argument (from 0) is being typed.
    case arguments(SigmaFunction, argument: Int)

    /// Reads a formula as typed so far (the cursor at its end).
    public static func of(_ text: String, functions: [SigmaFunction]) -> FormulaHint {
        guard text.hasPrefix("="), !functions.isEmpty else { return .none }
        let body = String(text.dropFirst())
        if let prefix = trailingName(body, standalone: true) {
            let matches = functions
                .filter { $0.name.lowercased().hasPrefix(prefix.lowercased()) && $0.name.lowercased() != prefix.lowercased() }
                .sorted { ($0.name.count, $0.name) < ($1.name.count, $1.name) }
            if !matches.isEmpty { return .suggest(prefix: prefix, matches: Array(matches.prefix(12))) }
        }
        var calls: [(name: String, arg: Int)] = []
        var inString = false
        var seen = ""
        for ch in body {
            if ch == "\"" { inString.toggle() }
            else if !inString {
                switch ch {
                case "(": calls.append((trailingName(seen, standalone: false) ?? "", 0))
                case ")": if !calls.isEmpty { calls.removeLast() }
                case ",": if !calls.isEmpty { calls[calls.count - 1].arg += 1 }
                default: break
                }
            }
            seen.append(ch)
        }
        guard let call = calls.last,
              let fn = functions.first(where: { $0.name.lowercased() == call.name.lowercased() }) else { return .none }
        return .arguments(fn, argument: call.arg)
    }

    /// The arguments of a syntax like "SUMIF(range, criterion, [sum_range])";
    /// "[number2, …]" is one argument.
    public static func arguments(_ syntax: String) -> [String] {
        guard let open = syntax.firstIndex(of: "("), let close = syntax.lastIndex(of: ")"), open < close else { return [] }
        let inner = syntax[syntax.index(after: open)..<close]
        var out: [String] = []
        var depth = 0
        var cur = ""
        for ch in inner {
            switch ch {
            case "[": depth += 1; cur.append(ch)
            case "]": depth -= 1; cur.append(ch)
            case "," where depth == 0: out.append(cur.trimmingCharacters(in: .whitespaces)); cur = ""
            default: cur.append(ch)
            }
        }
        if !cur.trimmingCharacters(in: .whitespaces).isEmpty { out.append(cur.trimmingCharacters(in: .whitespaces)) }
        return out
    }

    /// The name at the end of `s` ("SU" in "=A1+SU"). `standalone` requires it
    /// to start a token, so "A1" does not suggest anything for its "1".
    static func trailingName(_ s: String, standalone: Bool) -> String? {
        var name = ""
        for ch in s.reversed() {
            if ch.isLetter || ch.isNumber || ch == "." { name.insert(ch, at: name.startIndex) } else {
                if standalone, ch == "_" || ch == "$" || ch == "!" { return nil }
                break
            }
        }
        guard let first = name.first, first.isLetter, first.isASCII else { return nil }
        return name
    }
}
