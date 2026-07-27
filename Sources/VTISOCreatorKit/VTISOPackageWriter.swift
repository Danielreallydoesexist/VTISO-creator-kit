import Foundation
import ZIPFoundation

/// Writes an assembled staging directory to a `.vtiso` (ZIP) archive.
/// The archive contains no wrapping folder — `manifest.json` sits at the root.
public enum VTISOPackageWriter {
    public static func writeArchive(stagingDir: URL, to output: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: output.path) {
            try fm.removeItem(at: output)
        }
        do {
            let archive = try Archive(url: output, accessMode: .create)
            let baseLen = stagingDir.path.hasSuffix("/") ? stagingDir.path.count : stagingDir.path.count + 1

            let enumerator = fm.enumerator(at: stagingDir,
                                           includingPropertiesForKeys: [.isRegularFileKey],
                                           options: [.skipsHiddenFiles])
            while let obj = enumerator?.nextObject() as? URL {
                let values = try obj.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { continue }
                let full = obj.path
                let rel = String(full.dropFirst(baseLen))
                try archive.addEntry(with: rel, relativeTo: stagingDir, compressionMethod: .deflate)
            }
        } catch {
            throw VTISOError.zipCreationFailed(underlying: error)
        }
    }
}
