import Foundation
import ZIPFoundation

/// Writes an assembled staging directory to a `.vtiso` (ZIP) archive.
/// The archive contains no wrapping folder — `manifest.json` sits at the root.
///
/// The archive is first created at a hidden temporary sibling of the
/// destination (same directory, same volume); the destination is only
/// replaced once the new archive is complete, so a failed build never
/// destroys an existing output file and never leaves a partial archive
/// behind.
public enum VTISOPackageWriter {
    public static func writeArchive(stagingDir: URL, to output: URL) throws {
        let fm = FileManager.default

        guard let stagingValues = try? stagingDir.resourceValues(forKeys: [.isDirectoryKey]),
              stagingValues.isDirectory == true else {
            throw VTISOError.sourceFileMissing(stagingDir)
        }
        let manifestURL = stagingDir.appendingPathComponent("manifest.json")
        guard fm.fileExists(atPath: manifestURL.path) else {
            throw VTISOError.sourceFileMissing(manifestURL)
        }

        // Stage the new archive as a hidden sibling of the destination so it
        // lives on the same filesystem volume, keeping the final move or
        // replacement as atomic as possible.
        let tempArchive = output
            .deletingLastPathComponent()
            .appendingPathComponent(".\(output.lastPathComponent).new-\(UUID().uuidString.lowercased())")
        try? fm.removeItem(at: tempArchive)
        defer {
            try? fm.removeItem(at: tempArchive)
        }

        do {
            // `subpathsOfDirectory` throws on enumeration failure instead of
            // silently skipping entries, and returns package-relative paths
            // that already use `/` separators. Hidden files are included.
            let subpaths = try fm.subpathsOfDirectory(atPath: stagingDir.path).sorted()
            let archive = try Archive(url: tempArchive, accessMode: .create)
            for relPath in subpaths {
                let itemURL = stagingDir.appendingPathComponent(relPath)
                let values = try itemURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                guard values.isRegularFile == true else { continue }
                try archive.addEntry(with: relPath, relativeTo: stagingDir, compressionMethod: .deflate)
            }
        } catch {
            // The deferred cleanup removes the partial archive; the existing
            // destination (if any) is untouched.
            throw VTISOError.zipCreationFailed(underlying: error)
        }

        // The new archive is complete; replace the destination as late (and
        // as atomically) as possible.
        do {
            if fm.fileExists(atPath: output.path) {
#if canImport(Darwin)
                _ = try fm.replaceItemAt(output, withItemAt: tempArchive)
#else
                // swift-corelibs-foundation's replaceItemAt is unreliable, so
                // move the old file aside, move the new one in, and restore
                // the original if that fails.
                let backup = output.deletingLastPathComponent()
                    .appendingPathComponent(".\(output.lastPathComponent).backup-\(UUID().uuidString)")
                try fm.moveItem(at: output, to: backup)
                do {
                    try fm.moveItem(at: tempArchive, to: output)
                    try? fm.removeItem(at: backup)
                } catch {
                    try? fm.moveItem(at: backup, to: output)
                    throw error
                }
#endif
            } else {
                try fm.moveItem(at: tempArchive, to: output)
            }
        } catch {
            throw VTISOError.outputWriteFailed(output, underlying: error)
        }
        // The move consumes the temporary archive on success; the deferred
        // cleanup removes any stray copy in every other case.
    }
}
