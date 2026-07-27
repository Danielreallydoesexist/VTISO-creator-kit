import Foundation

public enum VTISOPathValidator {
    public static func validate(_ path: String) throws {
        if path.isEmpty { throw VTISOError.invalidPackagePath(path) }
        if path.hasPrefix("/") { throw VTISOError.invalidPackagePath(path) }
        if path.contains("://") { throw VTISOError.invalidPackagePath(path) }
        let comps = path.split(separator: "/", omittingEmptySubsequences: false)
        for c in comps {
            if c.isEmpty { throw VTISOError.invalidPackagePath(path) }
            if c == ".." || c == "." { throw VTISOError.invalidPackagePath(path) }
        }
    }

    public static func sanitizeFilename(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let cleaned = String(scalars)
        return cleaned.isEmpty ? "file" : cleaned
    }
}
