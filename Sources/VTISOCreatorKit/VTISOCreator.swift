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

    /// Menu configuration for the manifest.
    ///
    /// `menu.background` and `menu.cover` are treated as *generated output*:
    /// they are overwritten during `build(to:)` from `background` and
    /// `setCover(fileURL:)` respectively. Set `creator.background` (not
    /// `menu.background`) to choose the disc background.
    public var menu: VTISOMenu

    /// The single source of truth for the disc background.
    /// During `build(to:)` the manifest's `menu.background` is derived from
    /// this value: `.none` clears it, `.hexColor` writes the hex string, and
    /// `.imageFile` copies the image into `assets/menu/` and writes its
    /// package-relative path.
    public var background: VTISOBackground = .none

    public var playlist: VTISOPlaylistOptions
    public var permissions: VTISOPermissions
    public var compatibility: VTISOCompatibility
    public var extras: [VTISOExtra] = []

    /// Stable disc identifier written to `manifest.json` on every build.
    /// Initialized once per creator instance; assign a new value only if you
    /// intentionally want subsequent builds to describe a different disc.
    public var discId: String = UUID().uuidString.lowercased()

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

    /// Key for a client-extension value: shared values have a nil videoID.
    private struct ValueKey: Hashable {
        let videoID: String?
        let id: String
    }

    private var videos: [AddedVideo] = []
    private var coverURL: URL?
    private var coverPath: String?    // e.g. "assets/cover.<ext>"

    // Client extension state
    private var extensionSpec: ClientExtensionSpec?
    /// Raw bytes of an imported client.json, written back verbatim so that
    /// the packaged definition preserves the exact imported schema.
    private var extensionRawData: Data?
    private var optionCheckboxValues: [ValueKey: Bool] = [:]
    private var optionTextValues: [ValueKey: String] = [:]
    private var optionSelectValues: [ValueKey: String] = [:]
    private var listItems: [ValueKey: [VTISOJSON]] = [:]
    private var uploads: [ValueKey: [URL]] = [:]

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

    /// Adds an extra. IDs must be unique within the disc; omitting `id`
    /// generates a fresh lowercase UUID.
    public func addExtra(id: String = UUID().uuidString.lowercased(),
                         title: String,
                         body: String) throws {
        if extras.contains(where: { $0.id == id }) { throw VTISOError.duplicateExtraID(id) }
        extras.append(VTISOExtra(id: id, title: title, body: body))
    }

    // MARK: - Client extension

    /// Import a `client.json` produced by VideoThing's visual editor.
    /// The imported bytes are written back verbatim into the package so the
    /// definition's schema and values are preserved exactly.
    public func addClientExtension(definitionURL: URL) throws {
        guard FileManager.default.fileExists(atPath: definitionURL.path) else {
            throw VTISOError.sourceFileMissing(definitionURL)
        }
        let data: Data
        do { data = try Data(contentsOf: definitionURL) }
        catch { throw VTISOError.sourceFileUnreadable(definitionURL, underlying: error) }
        let dec = JSONDecoder()
        let spec: ClientExtensionSpec
        do {
            spec = try dec.decode(ClientExtensionSpec.self, from: data)
        } catch {
            throw VTISOError.invalidClientDefinition("\(error)")
        }
        try setClientExtension(spec)
        // Keep the original bytes so build() writes back the same document.
        extensionRawData = data
    }

    public func setClientExtension(_ spec: ClientExtensionSpec) throws {
        if spec.clientId.isEmpty { throw VTISOError.invalidClientDefinition("clientId empty") }
        try VTISOPathValidator.validate("client-buckets/\(spec.clientId)/client.json")

        // Validate declared buckets: package-relative paths, no duplicates.
        var seenBucketIDs = Set<String>()
        var seenBucketPaths = Set<String>()
        for b in spec.bucketDefinitions {
            if b.bucketId.isEmpty {
                throw VTISOError.invalidClientDefinition("bucketDefinitions contains an empty bucketId")
            }
            let normalized = Self.normalizedDirectoryPath(b.path)
            try VTISOPathValidator.validate(String(normalized.dropLast()))
            if !seenBucketIDs.insert(b.bucketId).inserted {
                throw VTISOError.invalidClientDefinition("duplicate bucket ID '\(b.bucketId)'")
            }
            if !seenBucketPaths.insert(normalized).inserted {
                throw VTISOError.invalidClientDefinition("duplicate bucket path '\(b.path)'")
            }
        }

        // Validate each declared bucketFile / destination path.
        for f in spec.exportFeatures.customLists   { try VTISOPathValidator.validate(f.bucketFile) }
        for f in spec.exportFeatures.checkboxes    { try VTISOPathValidator.validate(f.bucketFile) }
        for f in spec.exportFeatures.textFields    { try VTISOPathValidator.validate(f.bucketFile) }
        for f in spec.exportFeatures.selectFields  { try VTISOPathValidator.validate(f.bucketFile) }
        for f in spec.exportFeatures.fileUploads   {
            let d = f.destination.hasSuffix("/") ? String(f.destination.dropLast()) : f.destination
            try VTISOPathValidator.validate(d)
        }

        // Reject unsupported item-schema primitive names up front.
        for list in spec.exportFeatures.customLists {
            for (name, type) in list.itemSchema {
                try Self.validateSchemaDeclaration(type, listID: list.id, path: name)
            }
        }

        self.extensionSpec = spec
        self.extensionRawData = nil
    }

    public func setClientOptionCheckbox(id: String, value: Bool, videoID: String? = nil) {
        optionCheckboxValues[ValueKey(videoID: videoID, id: id)] = value
    }
    public func setClientOptionText(id: String, value: String, videoID: String? = nil) {
        optionTextValues[ValueKey(videoID: videoID, id: id)] = value
    }
    public func setClientOptionSelect(id: String, value: String, videoID: String? = nil) {
        optionSelectValues[ValueKey(videoID: videoID, id: id)] = value
    }
    public func setCustomListItems(listID: String, items: [VTISOJSON], videoID: String? = nil) {
        listItems[ValueKey(videoID: videoID, id: listID)] = items
    }
    public func setPerVideoCustomListItems(videoID: String, listID: String, items: [VTISOJSON]) {
        listItems[ValueKey(videoID: videoID, id: listID)] = items
    }
    public func addClientUpload(uploadID: String, fileURL: URL, videoID: String? = nil) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { throw VTISOError.sourceFileMissing(fileURL) }
        uploads[ValueKey(videoID: videoID, id: uploadID), default: []].append(fileURL)
    }

    // MARK: - Build

    @discardableResult
    public func build(to outputURL: URL) throws -> URL {
        guard outputURL.pathExtension.lowercased() == "vtiso" else {
            throw VTISOError.invalidOutputExtension(outputURL.lastPathComponent)
        }
        try validateManifestBasics()
        try validateClientValueKeys()

        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("vtiso-build-\(UUID().uuidString.lowercased())", isDirectory: true)
        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            throw VTISOError.temporaryDirectoryFailed(underlying: error)
        }
        defer { try? fm.removeItem(at: tempDir) }

        let staging = tempDir.appendingPathComponent("staging", isDirectory: true)
        let tempArchive = tempDir.appendingPathComponent("package.vtiso")

        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        try assemble(into: staging)
        try VTISOPackageWriter.writeArchive(stagingDir: staging, to: tempArchive)

        // The archive is complete; move it into place, replacing any
        // existing destination as late (and as atomically) as possible.
        do {
            if fm.fileExists(atPath: outputURL.path) {
#if canImport(Darwin)
                _ = try fm.replaceItemAt(outputURL, withItemAt: tempArchive)
#else
                // swift-corelibs-foundation's replaceItemAt is unreliable, so
                // move the old file aside, move the new one in, and restore
                // the original if that fails.
                let backup = outputURL.deletingLastPathComponent()
                    .appendingPathComponent(".\(outputURL.lastPathComponent).backup-\(UUID().uuidString)")
                try fm.moveItem(at: outputURL, to: backup)
                do {
                    try fm.moveItem(at: tempArchive, to: outputURL)
                    try? fm.removeItem(at: backup)
                } catch {
                    try? fm.moveItem(at: backup, to: outputURL)
                    throw error
                }
#endif
            } else {
                try fm.moveItem(at: tempArchive, to: outputURL)
            }
        } catch {
            throw VTISOError.outputWriteFailed(outputURL, underlying: error)
        }
        return outputURL
    }

    // MARK: - Pre-build validation

    private func validateManifestBasics() throws {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw VTISOError.invalidManifestValue("title must not be empty")
        }
        if creator.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw VTISOError.invalidManifestValue("creator display name must not be empty")
        }
        if videos.isEmpty { throw VTISOError.invalidManifestValue("no videos added") }

        var seenVideoIDs = Set<String>()
        for v in videos {
            guard seenVideoIDs.insert(v.id).inserted else { throw VTISOError.duplicateVideoID(v.id) }
            guard v.source.hasPrefix("videos/") else {
                throw VTISOError.invalidManifestValue("video source '\(v.source)' must be under videos/")
            }
            if let t = v.thumbnailPath, !t.hasPrefix("assets/thumbnails/") {
                throw VTISOError.invalidManifestValue("thumbnail '\(t)' must be under assets/thumbnails/")
            }
        }
        if let c = coverPath, !c.hasPrefix("assets/") {
            throw VTISOError.invalidManifestValue("cover '\(c)' must be under assets/")
        }
        if compatibility.minRuntime != "1.0" {
            throw VTISOError.unsupportedVTISOVersion(compatibility.minRuntime)
        }
        var seenExtraIDs = Set<String>()
        for e in extras where !seenExtraIDs.insert(e.id).inserted {
            throw VTISOError.duplicateExtraID(e.id)
        }
    }

    /// Checks every supplied client value against the client definition:
    /// unknown field IDs, unknown video IDs, and per-video/shared misuse
    /// are all rejected before any file is written.
    private func validateClientValueKeys() throws {
        let anyValues = !optionCheckboxValues.isEmpty || !optionTextValues.isEmpty
            || !optionSelectValues.isEmpty || !listItems.isEmpty || !uploads.isEmpty
        guard let spec = extensionSpec else {
            if anyValues {
                throw VTISOError.unknownExtensionFieldID("client values were supplied but no client extension was set")
            }
            return
        }

        let videoIDSet = Set(videos.map { $0.id })

        func perVideoByID(_ pairs: [(String, Bool?)]) -> [String: Bool] {
            var m: [String: Bool] = [:]
            for (id, pv) in pairs { m[id] = (pv == true) }
            return m
        }
        func check(_ keys: [ValueKey], kind: String, defs: [String: Bool]) throws {
            for k in keys {
                guard let isPerVideo = defs[k.id] else {
                    throw VTISOError.unknownExtensionFieldID("\(kind) '\(k.id)'")
                }
                if isPerVideo {
                    guard let vid = k.videoID else {
                        throw VTISOError.invalidExtensionValue("\(kind) '\(k.id)' is per-video and requires a video ID")
                    }
                    guard videoIDSet.contains(vid) else {
                        throw VTISOError.unknownReferencedVideoID(vid)
                    }
                } else if k.videoID != nil {
                    throw VTISOError.invalidExtensionValue("\(kind) '\(k.id)' is shared; do not supply a video ID")
                }
            }
        }

        try check(Array(optionCheckboxValues.keys), kind: "checkbox",
                  defs: perVideoByID(spec.exportFeatures.checkboxes.map { ($0.id, $0.perVideo) }))
        try check(Array(optionTextValues.keys), kind: "text",
                  defs: perVideoByID(spec.exportFeatures.textFields.map { ($0.id, $0.perVideo) }))
        try check(Array(optionSelectValues.keys), kind: "select",
                  defs: perVideoByID(spec.exportFeatures.selectFields.map { ($0.id, $0.perVideo) }))
        try check(Array(listItems.keys), kind: "custom list",
                  defs: perVideoByID(spec.exportFeatures.customLists.map { ($0.id, $0.perVideo) }))
        try check(Array(uploads.keys), kind: "upload",
                  defs: perVideoByID(spec.exportFeatures.fileUploads.map { ($0.id, $0.perVideo) }))
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

        // The manifest menu is derived from builder inputs on every build so
        // that repeated builds never accumulate stale generated values.
        var menuOut = menu

        // ---- cover ----
        if let curl = coverURL, let cpath = coverPath {
            try copy(curl, to: cpath)
            menuOut.cover = cpath
        }

        // ---- background (menu.background is generated from `background`) ----
        switch background {
        case .none:
            menuOut.background = nil
        case .hexColor(let hex):
            guard VTISOBackground.isValidHex(hex) else { throw VTISOError.invalidHexColor(hex) }
            menuOut.background = hex
        case .imageFile(let url):
            guard fm.fileExists(atPath: url.path) else { throw VTISOError.sourceFileMissing(url) }
            let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
            let p = "assets/menu/background.\(ext)"
            try copy(url, to: p)
            menuOut.background = p
        }

        // ---- client extension bucket ----
        var belongingClient = "default"
        var clientBucketRefs: [VTISOClientBucketRef]? = nil

        if let spec = extensionSpec {
            belongingClient = spec.clientId
            let base = try resolvedBucketBasePath(for: spec)

            // client.json — write the imported bytes back verbatim when the
            // definition came from a file, so its schema is preserved exactly.
            let clientData = try extensionRawData ?? encodeJSON(spec)
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
                        let v = optionCheckboxValues[ValueKey(videoID: vid, id: c.id)] ?? c.defaultValue
                        put("per-video/\(vid)/\(c.bucketFile)", c.id, .bool(v))
                    }
                } else {
                    let v = optionCheckboxValues[ValueKey(videoID: nil, id: c.id)] ?? c.defaultValue
                    put(c.bucketFile, c.id, .bool(v))
                }
            }
            for t in spec.exportFeatures.textFields {
                func resolvedText(videoID: String?) throws -> String {
                    let ctx = "text \(t.id)" + (videoID.map { " for video \($0)" } ?? "")
                    let v = optionTextValues[ValueKey(videoID: videoID, id: t.id)] ?? t.defaultValue ?? ""
                    if t.required && v.isEmpty {
                        throw VTISOError.missingRequiredExtensionValue(ctx)
                    }
                    if let mx = t.maxLength, v.count > mx {
                        throw VTISOError.invalidExtensionValue("\(ctx) exceeds maxLength \(mx) (got \(v.count))")
                    }
                    return v
                }
                if t.perVideo == true {
                    for vid in videoIDs {
                        put("per-video/\(vid)/\(t.bucketFile)", t.id, .string(try resolvedText(videoID: vid)))
                    }
                } else {
                    put(t.bucketFile, t.id, .string(try resolvedText(videoID: nil)))
                }
            }
            for s in spec.exportFeatures.selectFields {
                func resolvedSelect(videoID: String?) throws -> String {
                    let ctx = "select '\(s.id)'" + (videoID.map { " for video \($0)" } ?? "")
                    let v = optionSelectValues[ValueKey(videoID: videoID, id: s.id)]
                        ?? s.defaultValue ?? s.options.first ?? ""
                    guard s.options.contains(v) else {
                        throw VTISOError.invalidExtensionValue("\(ctx): value '\(v)' is not one of the declared options \(s.options)")
                    }
                    return v
                }
                if s.perVideo == true {
                    for vid in videoIDs {
                        put("per-video/\(vid)/\(s.bucketFile)", s.id, .string(try resolvedSelect(videoID: vid)))
                    }
                } else {
                    put(s.bucketFile, s.id, .string(try resolvedSelect(videoID: nil)))
                }
            }
            for (relPath, dict) in grouped {
                try write(try encodeJSON(dict), to: "\(base)\(relPath)")
            }

            // Custom lists. Note: a declared list is always written, even
            // when optional and empty — an empty JSON array is produced so
            // that clients can rely on the declared bucketFile existing.
            for list in spec.exportFeatures.customLists {
                if list.perVideo == true {
                    for vid in videoIDs {
                        let items = listItems[ValueKey(videoID: vid, id: list.id)] ?? []
                        try validateListCount(items, field: list, videoID: vid)
                        try validateListItems(items, field: list, videoID: vid)
                        try write(try encodeJSON(items), to: "\(base)per-video/\(vid)/\(list.bucketFile)")
                    }
                } else {
                    let items = listItems[ValueKey(videoID: nil, id: list.id)] ?? []
                    try validateListCount(items, field: list, videoID: nil)
                    try validateListItems(items, field: list, videoID: nil)
                    try write(try encodeJSON(items), to: "\(base)\(list.bucketFile)")
                }
            }

            // File uploads
            for f in spec.exportFeatures.fileUploads {
                let destRaw = f.destination.hasSuffix("/") ? f.destination : f.destination + "/"
                if f.perVideo == true {
                    for vid in videoIDs {
                        let arr = uploads[ValueKey(videoID: vid, id: f.id)] ?? []
                        try validateUploads(arr, field: f, videoID: vid)
                        for u in arr {
                            let name = VTISOPathValidator.sanitizeFilename(u.lastPathComponent)
                            try copy(u, to: "\(base)per-video/\(vid)/\(destRaw)\(name)")
                        }
                    }
                } else {
                    let arr = uploads[ValueKey(videoID: nil, id: f.id)] ?? []
                    try validateUploads(arr, field: f, videoID: nil)
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
            discId: discId,
            belongingClient: belongingClient,
            title: title,
            subtitle: subtitle,
            description: description,
            creator: creator,
            createdAt: isoTimestamp(),
            menu: menuOut,
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

    // MARK: - Bucket path resolution

    /// Returns the package-relative directory (with trailing `/`) that all
    /// client data is written under. Uses the bucket definition whose
    /// `bucketId` matches the client ID when one is declared; otherwise
    /// falls back to `client-buckets/<clientId>/`.
    private func resolvedBucketBasePath(for spec: ClientExtensionSpec) throws -> String {
        if let def = spec.bucketDefinitions.first(where: { $0.bucketId == spec.clientId }) {
            let normalized = Self.normalizedDirectoryPath(def.path)
            try VTISOPathValidator.validate(String(normalized.dropLast()))
            return normalized
        }
        return "client-buckets/\(spec.clientId)/"
    }

    private static func normalizedDirectoryPath(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }

    // MARK: - Custom-list validation

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

    private func validateListItems(_ items: [VTISOJSON], field: CxCustomListField, videoID: String?) throws {
        let listCtx = field.id + (videoID.map { " (video \($0))" } ?? "")
        for (i, item) in items.enumerated() {
            try Self.validateValue(item, against: .object(fields: field.itemSchema),
                                   listID: listCtx, path: "item[\(i)]")
        }
    }

    /// Supported primitive schema names. `file` / `file[]` cannot carry
    /// binary data in `VTISOJSON`; they are validated as package-relative
    /// path strings (the shape VideoThing writes) — the referenced files are
    /// not resolved or verified by this kit.
    private static let supportedSchemaPrimitives: Set<String> = [
        "string", "string[]", "number", "number[]", "boolean", "boolean[]", "file", "file[]"
    ]

    private static func validateSchemaDeclaration(_ type: CxItemSchemaFieldType, listID: String, path: String) throws {
        switch type {
        case .primitive(let p):
            guard supportedSchemaPrimitives.contains(p) else {
                throw VTISOError.invalidClientDefinition("list '\(listID)' field '\(path)': unsupported schema type '\(p)'")
            }
        case .object(let fields):
            for (k, v) in fields { try validateSchemaDeclaration(v, listID: listID, path: "\(path).\(k)") }
        case .array(let items):
            try validateSchemaDeclaration(items, listID: listID, path: "\(path)[]")
        }
    }

    private static func validateValue(_ value: VTISOJSON,
                                      against schema: CxItemSchemaFieldType,
                                      listID: String,
                                      path: String) throws {
        func mismatch(_ expected: String) -> VTISOError {
            .invalidExtensionValue("list '\(listID)' \(path): expected \(expected)")
        }
        switch schema {
        case .primitive(let p):
            switch p {
            case "string", "file":
                guard case .string = value else { throw mismatch(p) }
            case "number":
                guard case .number = value else { throw mismatch("number") }
            case "boolean":
                guard case .bool = value else { throw mismatch("boolean") }
            case "string[]", "file[]", "number[]", "boolean[]":
                guard case .array(let arr) = value else { throw mismatch(p) }
                let element = String(p.dropLast(2))
                for (i, el) in arr.enumerated() {
                    try validateValue(el, against: .primitive(element), listID: listID, path: "\(path)[\(i)]")
                }
            default:
                throw VTISOError.invalidClientDefinition("list '\(listID)' \(path): unsupported schema type '\(p)'")
            }
        case .object(let fields):
            guard case .object(let obj) = value else { throw mismatch("object") }
            for (name, fieldType) in fields {
                guard let fieldValue = obj[name] else {
                    throw VTISOError.invalidExtensionValue("list '\(listID)' \(path).\(name): missing declared field")
                }
                try validateValue(fieldValue, against: fieldType, listID: listID, path: "\(path).\(name)")
            }
        case .array(let items):
            guard case .array(let arr) = value else { throw mismatch("array") }
            for (i, el) in arr.enumerated() {
                try validateValue(el, against: items, listID: listID, path: "\(path)[\(i)]")
            }
        }
    }

    // MARK: - Upload validation

    private func validateUploads(_ files: [URL], field: CxFileUploadField, videoID: String?) throws {
        let ctx = "upload \(field.id)" + (videoID.map { " for video \($0)" } ?? "")
        if field.required && files.isEmpty {
            throw VTISOError.missingRequiredExtensionValue(ctx)
        }
        if !field.multiple && files.count > 1 {
            throw VTISOError.invalidExtensionValue("\(ctx): accepts a single file but \(files.count) were supplied")
        }
        let fm = FileManager.default
        for f in files {
            if let mx = field.maxSizeBytes {
                let size: Int64
                do {
                    let attrs = try fm.attributesOfItem(atPath: f.path)
                    size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                } catch {
                    throw VTISOError.sourceFileUnreadable(f, underlying: error)
                }
                if size > Int64(mx) {
                    throw VTISOError.invalidExtensionValue("\(ctx): '\(f.lastPathComponent)' is \(size) bytes, exceeds maxSizeBytes \(mx)")
                }
            }
            if !field.allowedTypes.isEmpty && !Self.fileMatchesAllowedTypes(f, allowed: field.allowedTypes) {
                throw VTISOError.invalidExtensionValue("\(ctx): '\(f.lastPathComponent)' does not match allowedTypes \(field.allowedTypes)")
            }
        }
    }

    /// Minimal extension → MIME map used for `allowedTypes` matching.
    /// Local metadata only; no external dependency, no content sniffing.
    private static let mimeByExtension: [String: String] = [
        "mp4": "video/mp4", "m4v": "video/x-m4v", "mov": "video/quicktime",
        "mkv": "video/x-matroska", "webm": "video/webm", "avi": "video/x-msvideo",
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
        "gif": "image/gif", "webp": "image/webp", "heic": "image/heic",
        "svg": "image/svg+xml", "bmp": "image/bmp", "tif": "image/tiff", "tiff": "image/tiff",
        "mp3": "audio/mpeg", "m4a": "audio/mp4", "wav": "audio/wav",
        "aac": "audio/aac", "flac": "audio/flac", "ogg": "audio/ogg",
        "json": "application/json", "txt": "text/plain", "md": "text/markdown",
        "html": "text/html", "css": "text/css", "js": "text/javascript",
        "pdf": "application/pdf", "zip": "application/zip",
        "srt": "application/x-subrip", "vtt": "text/vtt"
    ]

    /// Matches a file against `allowedTypes` entries:
    /// - `.ext` entries match the file extension (case-insensitive)
    /// - exact MIME entries (`image/png`) match the MIME detected from the extension
    /// - wildcard MIME groups (`image/*`) match the detected MIME's group
    /// When the MIME type cannot be detected (unknown extension), only
    /// extension-style entries can allow the file.
    private static func fileMatchesAllowedTypes(_ url: URL, allowed: [String]) -> Bool {
        let ext = url.pathExtension.lowercased()
        let detectedMIME = ext.isEmpty ? nil : mimeByExtension[ext]
        for entry in allowed {
            let e = entry.lowercased()
            if e.hasPrefix(".") {
                if !ext.isEmpty && e == ".\(ext)" { return true }
            } else if e.hasSuffix("/*") {
                if let m = detectedMIME, m.hasPrefix(String(e.dropLast())) { return true }
            } else if e.contains("/") {
                if let m = detectedMIME, m == e { return true }
            } else {
                if !ext.isEmpty && e == ext { return true }
            }
        }
        return false
    }

    // MARK: - Helpers

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
