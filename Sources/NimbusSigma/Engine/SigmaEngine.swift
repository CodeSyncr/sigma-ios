import Foundation
import JavaScriptCore

/// Sigma's own spreadsheet engine — the same code the web editor runs —
/// hosted in JavaScriptCore. The package does not contain it: a session
/// downloads it from Sigma for a sheet opened through the API, and it lives
/// in memory only. There is no web view: Swift draws everything,
/// and this answers what each cell shows and applies every change.
///
/// Not thread-safe; ``SigmaWorkbook`` keeps it on the main actor.
@MainActor
final class SigmaEngine {
    private let context: JSContext
    private let core: JSValue
    private var lastException: String?

    /// - Parameter source: Sigma's engine, as the server handed it to a session.
    ///   The package does not ship it; see ``SigmaSession``.
    init(source: String) throws {
        guard let context = JSContext() else { throw SigmaError.engine("JavaScriptCore is unavailable.") }
        self.context = context
        context.name = "Sigma"
        var thrown: String?
        context.exceptionHandler = { _, exception in
            thrown = exception?.toString() ?? "unknown error"
        }
        context.evaluateScript(source)
        if let thrown { throw SigmaError.engine("The Sigma engine could not start: \(thrown)") }
        guard let core = context.objectForKeyedSubscript("SigmaCore"), !core.isUndefined else {
            throw SigmaError.engine("The Sigma engine did not start.")
        }
        self.core = core
        context.exceptionHandler = { [weak self] _, exception in
            MainActor.assumeIsolated { self?.lastException = exception?.toString() ?? "unknown error" }
        }
    }

    var version: String { core.objectForKeyedSubscript("version")?.toString() ?? "" }

    /// Calls SigmaCore.<name>(args…).
    @discardableResult
    func call(_ name: String, _ args: [Any] = []) throws -> JSValue {
        lastException = nil
        let out = core.invokeMethod(name, withArguments: args)
        if let e = lastException { throw SigmaError.engine(e.replacingOccurrences(of: "Error: ", with: "")) }
        guard let out else { throw SigmaError.engine("\(name) returned nothing") }
        return out
    }

    /// Calls a SigmaCore method and decodes its result as JSON.
    func decode<T: Decodable>(_ type: T.Type, _ name: String, _ args: [Any] = []) throws -> T {
        let value = try call(name, args)
        guard let json = context.objectForKeyedSubscript("JSON")?.invokeMethod("stringify", withArguments: [value])?.toString(),
              let data = json.data(using: .utf8) else {
            throw SigmaError.engine("\(name) returned something unreadable")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SigmaError.engine("\(name): \(error.localizedDescription)")
        }
    }

    /// Calls a SigmaCore method that returns a promise and waits for it.
    func callAsync(_ name: String, _ args: [Any] = []) async throws -> JSValue {
        let promise = try call(name, args)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<JSValue, Error>) in
            var done = false
            let ok: @convention(block) (JSValue) -> Void = { value in
                guard !done else { return }
                done = true
                cont.resume(returning: value)
            }
            let fail: @convention(block) (JSValue) -> Void = { reason in
                guard !done else { return }
                done = true
                let message = reason.objectForKeyedSubscript("message")?.toString() ?? reason.toString() ?? "failed"
                cont.resume(throwing: SigmaError.engine(message))
            }
            promise.invokeMethod("then", withArguments: [
                JSValue(object: ok, in: context) as Any,
                JSValue(object: fail, in: context) as Any,
            ])
        }
    }
}
