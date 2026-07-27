import Foundation

/// High-level VTISO builder that mirrors VideoThing's exporter exactly.
/// Assemble a package in memory + a private temp dir, then `build(to:)` to
/// write a valid `.vtiso` archive.
public final class VTISOCreator {

    // MARK: - Public configuration mirroring the manifest

    public var title: String
    public var subtitle: String?
    public var description: String?
    public var creator: VTISOCreatorInfo
    public var menu: VTISOMenu
    public var background: VTISOBackground = .none
    public var playlist: VTISOPlaylistOptions
    public var permissions: VTISOPermissions
    public var compatibility: VTISOCompatibility
    public var extras: [VTISOExtra] = []

    // MARK: - Internal state

    private struct AddedVideo {
        let id: String
        let title: String
        let description: String?
        let tags: [String]?
        let sourceURL: URL
        let source: String            // "videos/video_<id>.<ext>"
        let thumbnailURL: URL?
        let thumbnailPath: String?    // "assets/thumbnails/video_<id>.<ext>"
    }

    private var videos: [AddedVideo] = []
    private var coverURL: URL?
    private var coverPath: String?    // e.g. "assets/cover.<ext>"

    // Client extension state
    private var extensionSpec: ClientExtensionSpec?
    private var optionCheckboxValues: [String: Bool] = [:]           // key = id or "<vid>::<id>"
    private var optionTextValues: [String: String] = [:]
    private var optionSelectValues: [String: String] = [:]
    private var listItems: [String: [VTISOJSON]] = [:]                // "<listId>" or "<vid>::<listId>"
    private var uploads: [String: [URL]] = [:]                         // "<uploadId>" or "<vid>::<uploadId>"

    // MARK: - Init

    public init(title: String,
                creatorDisplayName: String,
                menu: VTISOMenu = VTISOMenu(),
                playlist: VTISOPlaylistOptions = VTISOPlaylistOptions(),
                permissions: VTISOPermissions = VTISOPermissions(),
                compatibility: VTISOCompatibility = VTISOCompatibility()) {
        self.title = title
        self.creator = VTISOCreatorInfo(displayName: creatorDisplayName)
        self.menu = menu
        self.playlist = playlist
        self.permissions = permissions
        self.compatibility = compatibility
    }

    // MARK: - Videos

    @discardableResult
    public func addVideo(id: String? = nil,
                         title: String,
                         description: String? = nil,
                         fileURL: URL,
                         thumbnailURL: URL? = nil,
                         tags: [String]? = nil) throws -> String {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { throw VTISOError.sourceFileMissing(fileURL) }
        if let t = thumbnailURL, !fm.fileExists(atPath: t.path) { throw VTISOError.sourceFileMissing(t) }

        let vid = id ?? UUID().uuidString.lowercased()
        if videos.contains(where: { $0.id == vid }) { throw VTISOError.duplicateVideoID(vid) }

        let ext = fileURL.pathExtension.isEmpty ? "mp4" : fileURL.pathExtension.lowercased()
        let sourcePath = "videos/video_\(vid).\(ext)"
        try VTISOPathValidator.validate(sourcePath)

        var thumbPath: String? = nil
        if let t = thumbnailURL {
            let tExt = t.pathExtension.isEmpty ? "jpg" : t.pathExtension.lowercased()
            let p = "assets/thumbnails/video_\(vid).\(tExt)"
            try VTISOPathValidator.validate(p)
            thumbPath = p
        }

        videos.append(AddedVideo(id: vid, title: title, description: description, tags: tags,
                                 sourceURL: fileURL, source: sourcePath,
                                 thumbnailURL: thumbnailURL, thumbnailPath: thumbPath))
        return vid
    }

    public func setCover(fileURL: URL) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { throw VTISOError.sourceFileMissing(fileURL) }
        let ext = fileURL.pathExtension.isEmpty ? "png" : fileURL.pathExtension.lowercased()
        let p = "assets/cover.\(ext)"
        try VTISOPathValidator.validate(p)
        coverURL = fileURL
        coverPath = p
    }

    // MARK: - Extras

    public func addExtra(title: String, body: String) {
        extras.append(VTISOExtra(title: title, body: body))
    }

    // MARK: - Client extension

    /// Import a `client.json` produced by VideoThing's visual editor.
    public func addClientExtension(definitionURL: URL) throws {
        guard FileManager.default.fileExists(atPath: definitionURL.path) else {
            throw VTISOError.sourceFileMissing(definitionURL)
        }
        let data: Data
        do { data = try Data(contentsOf: definitionURL) }
        catch { throw VTISOError.sourceFileUnreadable(definitionURL, underlying: error) }
        let dec = JSONDecoder()
        do {
            let spec = try dec.decode(ClientExtensionSpec.self, from: data)
            try setClientExtension(spec)
        } catch {
            throw VTISOError.invalidClientDefinition("\(error)")
        }
    }

    public func setClientExtension(_ spec: ClientExtensionSpec) throws {
        if spec.clientId.isEmpty { throw VTISOError.invalidClientDefinition("clientId empty") }
        try VTISOPathValidator.validate("client-buckets/\(spec.clientId)/client.json")
        // Validate each declared bucketFile / destination path.
        for f in spec.exportFeatures.customLists   { try VTISOPathValidator.validate(f.bucketFile) }
        for f in spec.exportFeatures.checkboxes    { try VTISOPathValidator.validate(f.bucketFile) }
        for f in spec.exportFeatures.textFields    { try VTISOPathValidator.validate(f.bucketFile) }
        for f in spec.exportFeatures.selectFields  { try VTISOPathValidator.validate(f.bucketFile) }
        for f in spec.exportFeatures.fileUploads   {
            let d = f.destination.hasSuffix("/") ? String(f.destination.dropLast()) : f.destination
            try VTISOPathValidator.validate(d)
        }
        self.extensionSpec = spec
    }

    public func setClientOptionCheckbox(id: String, value: Bool, videoID: String? = nil) {
        optionCheckboxValues[key(id, videoID)] = value
    }
    public func setClientOptionText(id: String, value: String, videoID: String? = nil) {
        optionTextValues[key(id, videoID)] = value
    }
    public func setClientOptionSelect(id: String, value: String, videoID: String? = nil) {
        optionSelectValues[key(id, videoID)] = value
    }
    public func setCustomListItems(listID: String, items: [VTISOJSON], videoID: String? = nil) {
        listItems[key(listID, videoID)] = items
    }
    public func setPerVideoCustomListItems(videoID: String, listID: String, items: [VTISOJSON]) {
        listItems[key(listID, videoID)] = items
    }
    public func addClientUpload(uploadID: String, fileURL: URL, videoID: String? = nil) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { throw VTISOError.sourceFileMissing(fileURL) }
        uploads[key(uploadID, videoID), default: []].append(fileURL)
    }

    private func key(_ id: String, _ videoID: String?) -> String {
        if let v = videoID { return "\(v)::\(id)" } else { return id }
    }

    // MARK: - Build

    @discardableResult
    public func build(to outputURL: URL) throws -> URL {
        if videos.isEmpty { throw VTISOError.invalidManifestValue("no videos added") }

        let fm = FileManager.default
        let tempDir: URL
        do {
            tempDir = try fm.url(for: .itemReplacementDirectory,
                                 in: .userDomainMask,
                                 appropriateFor: outputURL,
                                 create: true)
        } catch {
            throw VTISOError.temporaryDirectoryFailed(underlying: error)
        }
        let staging = tempDir.appendingPathComponent("vtiso-staging", isDirectory: true)

        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            try assemble(into: staging)
            try VTISOPackageWriter.writeArchive(stagingDir: staging, to: outputURL)
            try? fm.removeItem(at: tempDir)
            return outputURL
        } catch {
            try? fm.removeItem(at: tempDir)
            throw error
        }
    }

    // MARK: - Assembly

    private func assemble(into staging: URL) throws {
        var writtenPaths = Set<String>()
        let fm = FileManager.default

        func write(_ data: Data, to relPath: String) throws {
            try VTISOPathValidator.validate(relPath)
            if !writtenPaths.insert(relPath).inserted {
                throw VTISOError.duplicatePackageDestination(relPath)
            }
            let dst = staging.appendingPathComponent(relPath)
            try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            do { try data.write(to: dst) }
            catch { throw VTISOError.outputWriteFailed(dst, underlying: error) }
        }
        func copy(_ src: URL, to relPath: String) throws {
            try VTISOPathValidator.validate(relPath)
            if !writtenPaths.insert(relPath).inserted {
                throw VTISOError.duplicatePackageDestination(relPath)
            }
            let dst = staging.appendingPathComponent(relPath)
            try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            do { try fm.copyItem(at: src, to: dst) }
            catch { throw VTISOError.outputWriteFailed(dst, underlying: error) }
        }

        // ---- videos + thumbnails ----
        var manifestVideos: [VTISOVideoEntry] = []
        for v in videos {
            try copy(v.sourceURL, to: v.source)
            if let t = v.thumbnailURL, let p = v.thumbnailPath { try copy(t, to: p) }
            manifestVideos.append(VTISOVideoEntry(
                id: v.id, title: v.title, description: v.description,
                sourceType: "local-file", source: v.source,
                thumbnail: v.thumbnailPath, durationSeconds: nil, tags: v.tags
            ))
        }

        // ---- cover ----
        if let curl = coverURL, let cpath = coverPath {
            try copy(curl, to: cpath)
            menu.cover = cpath
        }

        // ---- background ----
        switch background {
        case .none:
            break
        case .hexColor(let hex):
            guard VTISOBackground.isValidHex(hex) else { throw VTISOError.invalidHexColor(hex) }
            menu.background = hex
        case .imageFile(let url):
            guard fm.fileExists(atPath: url.path) else { throw VTISOError.sourceFileMissing(url) }
            let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
            let p = "assets/menu/background.\(ext)"
            try copy(url, to: p)
            menu.background = p
        }

        // ---- client extension bucket ----
        var belongingClient = "default"
        var clientBucketRefs: [VTISOClientBucketRef]? = nil

        if let spec = extensionSpec {
            belongingClient = spec.clientId
            let base = "client-buckets/\(spec.clientId)/"

            // client.json
            let clientData = try encodeJSON(spec)
            try write(clientData, to: "\(base)client.json")

            // Merge simple option values into grouped bucket files.
            var grouped: [String: [String: VTISOJSON]] = [:]
            func put(_ relPath: String, _ id: String, _ value: VTISOJSON) {
                let key = relPath.isEmpty ? "client-options.json" : relPath
                grouped[key, default: [:]][id] = value
            }

            let videoIDs = videos.map { $0.id }

            for c in spec.exportFeatures.checkboxes {
                if c.perVideo == true {
                    for vid in videoIDs {
                        let v = optionCheckboxValues["\(vid)::\(c.id)"] ?? c.defaultValue
                        put("per-video/\(vid)/\(c.bucketFile)", c.id, .bool(v))
                    }
                } else {
                    let v = optionCheckboxValues[c.id] ?? c.defaultValue
                    put(c.bucketFile, c.id, .bool(v))
                }
                if c.required && optionCheckboxValues[c.id] == nil && c.perVideo != true {
                    // required boolean always has default; no throw.
                }
            }
            for t in spec.exportFeatures.textFields {
                if t.perVideo == true {
                    for vid in videoIDs {
                        let v = optionTextValues["\(vid)::\(t.id)"] ?? t.defaultValue ?? ""
                        if t.required && v.isEmpty {
                            throw VTISOError.missingRequiredExtensionValue("text \(t.id) for video \(vid)")
                        }
                        put("per-video/\(vid)/\(t.bucketFile)", t.id, .string(v))
                    }
                } else {
                    let v = optionTextValues[t.id] ?? t.defaultValue ?? ""
                    if t.required && v.isEmpty {
                        throw VTISOError.missingRequiredExtensionValue("text \(t.id)")
                    }
                    put(t.bucketFile, t.id, .string(v))
                }
            }
            for s in spec.exportFeatures.selectFields {
                let fallback = s.defaultValue ?? s.options.first ?? ""
                if s.perVideo == true {
                    for vid in videoIDs {
                        let v = optionSelectValues["\(vid)::\(s.id)"] ?? fallback
                        put("per-video/\(vid)/\(s.bucketFile)", s.id, .string(v))
                    }
                } else {
                    let v = optionSelectValues[s.id] ?? fallback
                    put(s.bucketFile, s.id, .string(v))
                }
            }
            for (relPath, dict) in grouped {
                try write(try encodeJSON(dict), to: "\(base)\(relPath)")
            }

            // Custom lists
            for list in spec.exportFeatures.customLists {
                if list.perVideo == true {
                    for vid in videoIDs {
                        let items = listItems["\(vid)::\(list.id)"] ?? []
                        try validateListCount(items, field: list, videoID: vid)
                        try write(try encodeJSON(items), to: "\(base)per-video/\(vid)/\(list.bucketFile)")
                    }
                } else {
                    let items = listItems[list.id] ?? []
                    try validateListCount(items, field: list, videoID: nil)
                    try write(try encodeJSON(items), to: "\(base)\(list.bucketFile)")
                }
            }

            // File uploads
            for f in spec.exportFeatures.fileUploads {
                let destRaw = f.destination.hasSuffix("/") ? f.destination : f.destination + "/"
                if f.perVideo == true {
                    for vid in videoIDs {
                        let arr = uploads["\(vid)::\(f.id)"] ?? []
                        if f.required && arr.isEmpty {
                            throw VTISOError.missingRequiredExtensionValue("upload \(f.id) for video \(vid)")
                        }
                        for u in arr {
                            let name = VTISOPathValidator.sanitizeFilename(u.lastPathComponent)
                            try copy(u, to: "\(base)per-video/\(vid)/\(destRaw)\(name)")
                        }
                    }
                } else {
                    let arr = uploads[f.id] ?? []
                    if f.required && arr.isEmpty {
                        throw VTISOError.missingRequiredExtensionValue("upload \(f.id)")
                    }
                    for u in arr {
                        let name = VTISOPathValidator.sanitizeFilename(u.lastPathComponent)
                        try copy(u, to: "\(base)\(destRaw)\(name)")
                    }
                }
            }

            clientBucketRefs = [VTISOClientBucketRef(clientId: spec.clientId, path: base, optionalForOtherClients: true)]
        }

        // ---- manifest ----
        let manifest = VTISOManifest(
            vtisoVersion: "1.0",
            discId: UUID().uuidString.lowercased(),
            belongingClient: belongingClient,
            title: title,
            subtitle: subtitle,
            description: description,
            creator: creator,
            createdAt: isoTimestamp(),
            menu: menu,
            playlist: playlist,
            videos: manifestVideos,
            extras: extras.isEmpty ? nil : extras,
            assets: nil,
            permissions: permissions,
            compatibility: compatibility,
            clientBuckets: clientBucketRefs
        )
        try write(try encodeJSON(manifest), to: "manifest.json")
    }

    private func validateListCount(_ items: [VTISOJSON], field: CxCustomListField, videoID: String?) throws {
        if field.required && items.isEmpty {
            throw VTISOError.missingRequiredExtensionValue("list \(field.id)" + (videoID.map { " video \($0)" } ?? ""))
        }
        if let mn = field.minItems, items.count < mn {
            throw VTISOError.missingRequiredExtensionValue("list \(field.id) requires \(mn) items")
        }
        if let mx = field.maxItems, items.count > mx {
            throw VTISOError.invalidManifestValue("list \(field.id) exceeds max \(mx)")
        }
    }

    private func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        do { return try enc.encode(value) }
        catch { throw VTISOError.jsonEncodingFailed(underlying: error) }
    }

    private func isoTimestamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }
}
