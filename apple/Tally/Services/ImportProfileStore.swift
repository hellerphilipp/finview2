import Foundation
import SwiftData
import ImportKit

/// Creates and installs `ImportProfile`s from YAML/CEL import specs — the
/// mechanism behind both the seeded built-in banks and user-added community
/// specs (drag-drop, file, or URL). Validation and fetching live here (pure,
/// testable) so the Preferences UI stays thin.
enum ImportProfileStore {

    /// A human-readable failure surfaced to the user when a spec can't be added.
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Validate YAML (structure *and* that every CEL mapping compiles) and build
    /// an unsaved `ImportProfile`, taking `name`/`version` from the spec itself.
    static func makeProfile(fromYAML yaml: String) throws -> ImportProfile {
        let trimmed = yaml.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Failure(message: "The file is empty.")
        }
        let spec: ImportSpec
        do {
            // StatementImporter parses the spec and compiles all five CEL
            // mapping expressions, so bad specs are rejected up front.
            spec = try StatementImporter(yaml: yaml).spec
        } catch {
            throw Failure(message: "Not a valid import spec: \(error.localizedDescription)")
        }
        let name = spec.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw Failure(message: "The spec is missing a `name`.")
        }
        return ImportProfile(name: name, specYAML: yaml, version: spec.version)
    }

    /// Validate and persist a spec. If a profile with the same name already
    /// exists it is updated in place (a "replace"), so re-adding a newer version
    /// of a community spec doesn't create duplicates. Returns the saved profile.
    @MainActor
    @discardableResult
    static func install(yaml: String, into context: ModelContext) throws -> ImportProfile {
        let candidate = try makeProfile(fromYAML: yaml)

        let existing = (try? context.fetch(FetchDescriptor<ImportProfile>())) ?? []
        if let match = existing.first(where: { $0.name == candidate.name }) {
            match.specYAML = candidate.specYAML
            match.version = candidate.version
            try context.save()
            return match
        }

        context.insert(candidate)
        try context.save()
        return candidate
    }

    /// Fetch spec YAML from a local file or remote URL (a one-time snapshot).
    /// Handles the security-scoped-resource dance for sandboxed file access,
    /// mirroring `ImportView.handleFile`.
    static func fetchYAML(from url: URL) throws -> String {
        if url.isFileURL {
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            return try String(contentsOf: url, encoding: .utf8)
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw Failure(message: "Couldn't download the spec: \(error.localizedDescription)")
        }
    }
}
