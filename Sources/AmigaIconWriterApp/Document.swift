#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// The project document type. When you wrap this in an Xcode app target,
    /// declare this identifier under "Exported Type Identifiers" with the
    /// `.amigaicons` filename extension (see README).
    static let amigaIconProject = UTType(exportedAs: "com.nyteshade.amigaiconwriter.project")
}

/// A single-file project document. Originals are stored inside the JSON as
/// base64 PNG, so a project is fully self-contained and portable.
struct IconProjectDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.amigaIconProject] }
    static var writableContentTypes: [UTType] { [.amigaIconProject] }

    var project: IconProject

    init() { project = IconProject() }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        project = try JSONDecoder().decode(IconProject.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(project)
        return FileWrapper(regularFileWithContents: data)
    }
}
#endif
