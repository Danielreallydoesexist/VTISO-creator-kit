import Foundation

public enum VTISOError: Error, LocalizedError, CustomStringConvertible {
    case sourceFileMissing(URL)
    case sourceFileUnreadable(URL, underlying: Error)
    case invalidPackagePath(String)
    case duplicateVideoID(String)
    case duplicatePackageDestination(String)
    case unsupportedVTISOVersion(String)
    case invalidManifestValue(String)
    case invalidClientDefinition(String)
    case missingRequiredExtensionValue(String)
    case unknownReferencedVideoID(String)
    case jsonEncodingFailed(underlying: Error)
    case temporaryDirectoryFailed(underlying: Error)
    case zipCreationFailed(underlying: Error)
    case outputWriteFailed(URL, underlying: Error)
    case invalidHexColor(String)
    case invalidOutputExtension(String)
    case unknownExtensionFieldID(String)
    case invalidExtensionValue(String)
    case duplicateExtraID(String)

    /// `LocalizedError` conformance so SwiftUI alerts and
    /// `error.localizedDescription` show the real message.
    public var errorDescription: String? {
        description
    }

    public var description: String {
        switch self {
        case .sourceFileMissing(let u):                return "Source file missing: \(u.path)"
        case .sourceFileUnreadable(let u, let e):      return "Source unreadable \(u.path): \(e)"
        case .invalidPackagePath(let p):               return "Invalid package path: \(p)"
        case .duplicateVideoID(let id):                return "Duplicate video ID: \(id)"
        case .duplicatePackageDestination(let p):      return "Duplicate destination path: \(p)"
        case .unsupportedVTISOVersion(let v):          return "Unsupported VTISO version: \(v)"
        case .invalidManifestValue(let s):             return "Invalid manifest value: \(s)"
        case .invalidClientDefinition(let s):          return "Invalid client definition: \(s)"
        case .missingRequiredExtensionValue(let s):    return "Missing required extension value: \(s)"
        case .unknownReferencedVideoID(let id):        return "Unknown video ID referenced: \(id)"
        case .jsonEncodingFailed(let e):               return "JSON encoding failed: \(e)"
        case .temporaryDirectoryFailed(let e):         return "Temporary directory error: \(e)"
        case .zipCreationFailed(let e):                return "ZIP creation failed: \(e)"
        case .outputWriteFailed(let u, let e):         return "Output write failed \(u.path): \(e)"
        case .invalidHexColor(let s):                  return "Invalid hex color: \(s)"
        case .invalidOutputExtension(let p):           return "Output must end in .vtiso: \(p)"
        case .unknownExtensionFieldID(let s):          return "Unknown client-extension field ID: \(s)"
        case .invalidExtensionValue(let s):            return "Invalid client-extension value: \(s)"
        case .duplicateExtraID(let id):                return "Duplicate extra ID: \(id)"
        }
    }
}
