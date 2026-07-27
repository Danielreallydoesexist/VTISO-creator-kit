import Foundation

/// Only the two background forms supported by VideoThing's current exporter:
/// a hex color, or a local image copied into the package. No gradients.
public enum VTISOBackground: Sendable {
    case none
    case hexColor(String)
    case imageFile(URL)

    static let hexRegex = try! NSRegularExpression(
        pattern: "^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"
    )

    public static func isValidHex(_ s: String) -> Bool {
        let r = NSRange(s.startIndex..., in: s)
        return hexRegex.firstMatch(in: s, range: r) != nil
    }
}
