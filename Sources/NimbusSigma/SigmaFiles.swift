import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension SigmaFile {
    /// Writes the file to a temporary location under its own name, for a share
    /// sheet, `ShareLink`, or a document picker in export mode.
    public func temporaryURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("NimbusSigma", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }
}

/// The spreadsheet types Sigma opens, for `.fileImporter(allowedContentTypes:)`.
public enum SigmaContentTypes {
    public static let xlsx = UTType("org.openxmlformats.spreadsheetml.sheet") ?? UTType(filenameExtension: "xlsx") ?? .data
    public static let all: [UTType] = [xlsx, .commaSeparatedText]

    /// Reads a file the person picked (security-scoped URLs included), for
    /// your server to upload.
    public static func read(_ url: URL) throws -> (data: Data, filename: String) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return (try Data(contentsOf: url), url.lastPathComponent)
    }
}

#if os(iOS)
import UIKit

/// The system share sheet for an exported sheet: AirDrop, Mail, Save to Files.
public struct SigmaShareSheet: UIViewControllerRepresentable {
    private let items: [Any]

    public init(file: SigmaFile) throws {
        items = [try file.temporaryURL()]
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    public func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
