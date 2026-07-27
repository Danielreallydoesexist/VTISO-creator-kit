import Foundation

public enum VTISOPathValidator {
    /// Validates a package-relative, slash-separated path. Rejects empty
    /// paths, absolute paths, Windows drive paths (`C:/…`), backslashes,
    /// NUL characters, URL-like paths, empty components, and `.` / `..`
    /// components. Unsafe paths are rejected, never normalized.
    public static func validate(_ path: String) throws {
        if path.isEmpty { throw VTISOError.invalidPackagePath(path) }
        if path.hasPrefix("/") { throw VTISOError.invalidPackagePath(path) }
        if path.contains("\\") { throw VTISOError.invalidPackagePath(path) }
        if path.contains("\u{0}") { throw VTISOError.invalidPackagePath(path) }
        // Rejects URL-like paths ("scheme://…") and Windows drive paths ("C:/…").
        if path.contains(":") { throw VTISOError.invalidPackagePath(path) }
        let comps = path.split(separator: "/", omittingEmptySubsequences: false)
        for c in comps {
            if c.isEmpty { throw VTISOError.invalidPackagePath(path) }
            if c == ".." || c == "." { throw VTISOError.invalidPackagePath(path) }
        }
    }

    /// Reduces a raw filename to safe characters (alphanumerics, `.`, `_`,
    /// `-`). Never returns an empty string, and never returns a dots-only
    /// name (which would be `.` or `..`).
    public static func sanitizeFilename(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let cleaned = String(scalars)
        if cleaned.isEmpty || cleaned.allSatisfy({ $0 == "." }) { return "file" }
        return cleaned
    }
}
