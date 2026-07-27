import Foundation

public enum VTISOPathValidator {

    public static func validate(_ path: String) throws {

        guard !path.isEmpty else {
            throw VTISOError.invalidPackagePath(path)
        }

        guard !path.contains("\0") else {
            throw VTISOError.invalidPackagePath(path)
        }

        guard !path.contains("\\") else {
            throw VTISOError.invalidPackagePath(path)
        }

        guard !path.hasPrefix("/") else {
            throw VTISOError.invalidPackagePath(path)
        }

        guard !path.contains("://") else {
            throw VTISOError.invalidPackagePath(path)
        }

        if path.range(
            of: #"^[A-Za-z]:"#,
            options: .regularExpression
        ) != nil {
            throw VTISOError.invalidPackagePath(path)
        }

        let components = path.split(
            separator: "/",
            omittingEmptySubsequences: false
        )

        guard !components.contains(where: {
            $0.isEmpty ||
            $0 == "." ||
            $0 == ".."
        }) else {
            throw VTISOError.invalidPackagePath(path)
        }
    }

    public static func sanitizeFilename(
        _ raw: String
    ) -> String {

        let allowed =
            CharacterSet.alphanumerics
            .union(
                CharacterSet(
                    charactersIn: "._-"
                )
            )

        let cleaned = String(
            raw.unicodeScalars.map {
                allowed.contains($0)
                ? Character($0)
                : "_"
            }
        )

        return cleaned.isEmpty
            ? "file"
            : cleaned
    }
}
