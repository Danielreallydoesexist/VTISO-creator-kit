import Foundation
import ZIPFoundation

/// Writes an assembled staging directory to a `.vtiso` (ZIP) archive.
/// The archive contains no wrapping folder — `manifest.json` sits at the root.
public enum VTISOPackageWriter {
    public static func writeArchive(stagingDir: URL, to output: URL) throws {
        let fm = FileManager.default

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: stagingDir.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw VTISOError.sourceFileMissing(stagingDir)
        }
        let manifestURL = stagingDir.appendingPathComponent("manifest.json")
        guard fm.fileExists(atPath: manifestURL.path) else {
            throw VTISOError.sourceFileMissing(manifestURL)
        }
        if fm.fileExists(atPath: output.path) {
            do { try fm.removeItem(at: output) }
            catch { throw VTISOError.outputWriteFailed(output, underlying: error) }
        }

        do {
            // `subpathsOfDirectory` throws on enumeration failure instead of
            // silently skipping entries, and returns package-relative paths
            // that already use `/` separators. Hidden files are included.
            let subpaths = try fm.subpathsOfDirectory(atPath: stagingDir.path).sorted()
            let archive = try Archive(url: output, accessMode: .create)
            for relPath in subpaths {
                var isSubDirectory: ObjCBool = false
                guard fm.fileExists(atPath: stagingDir.appendingPathComponent(relPath).path,
                                    isDirectory: &isSubDirectory),
                      !isSubDirectory.boolValue else { continue }
                try archive.addEntry(with: relPath, relativeTo: stagingDir, compressionMethod: .deflate)
            }
        } catch {
            // Never leave a partial archive behind.
            try? fm.removeItem(at: output)
            throw VTISOError.zipCreationFailed(underlying: error)
        }
    }
}
