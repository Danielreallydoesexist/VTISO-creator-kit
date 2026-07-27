import XCTest
import ZIPFoundation
@testable import VTISOCreatorKit

final class VTISOCreatorKitTests: XCTestCase {

    // MARK: - Helpers

    func makeTempFile(name: String, bytes: [UInt8] = [0, 1, 2, 3]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vtiso-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    /// A fresh directory so the output file itself never pre-exists.
    func newOutputURL(_ name: String = "out.vtiso") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vtiso-out-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    func makeSpec(clientId: String = "oyster",
                  bucketDefinitions: [CxBucketDefinition] = [],
                  fileUploads: [CxFileUploadField] = [],
                  customLists: [CxCustomListField] = [],
                  checkboxes: [CxCheckboxField] = [],
                  textFields: [CxTextField] = [],
                  selectFields: [CxSelectField] = []) -> ClientExtensionSpec {
        ClientExtensionSpec(
            clientId: clientId,
            clientName: "Test Client",
            description: nil,
            extensionVersion: "1.0",
            minimumRuntimeVersion: "1.0",
            authorName: nil,
            websiteUrl: nil,
            supportedPlatforms: ["any"],
            exportFeatures: CxExportFeatures(fileUploads: fileUploads,
                                             customLists: customLists,
                                             checkboxes: checkboxes,
                                             textFields: textFields,
                                             selectFields: selectFields,
                                             menuAdditions: []),
            bucketDefinitions: bucketDefinitions
        )
    }

    func makeCreatorWithVideo(videoID: String = "v1") throws -> VTISOCreator {
        let creator = VTISOCreator(title: "Test", creatorDisplayName: "tester")
        let video = try makeTempFile(name: "clip.mp4")
        _ = try creator.addVideo(id: videoID, title: "Episode 1", fileURL: video)
        return creator
    }

    func archiveEntryNames(_ url: URL) throws -> [String] {
        let archive = try Archive(url: url, accessMode: .read)
        return archive.map { $0.path }
    }

    func extractEntry(_ url: URL, path: String) throws -> Data {
        let archive = try Archive(url: url, accessMode: .read)
        guard let entry = archive[path] else {
            throw VTISOError.sourceFileMissing(url.appendingPathComponent(path))
        }
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        return data
    }

    func extractManifest(_ url: URL) throws -> VTISOManifest {
        try JSONDecoder().decode(VTISOManifest.self, from: try extractEntry(url, path: "manifest.json"))
    }

    /// Asserts that the destination's parent directory contains no leftover
    /// hidden temporary archives (".<name>.new-…" / ".<name>.backup-…").
    func assertNoTempSiblings(around output: URL,
                              file: StaticString = #filePath, line: UInt = #line) throws {
        let parent = output.deletingLastPathComponent()
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: parent.path)
            .filter { $0.hasPrefix(".\(output.lastPathComponent).") }
        XCTAssertTrue(leftovers.isEmpty, "temporary sibling archives left behind: \(leftovers)",
                      file: file, line: line)
    }

    // MARK: - Basic building

    func testBuildsMinimalPortableVTISO() throws {
        let video = try makeTempFile(name: "clip.mp4")
        let thumb = try makeTempFile(name: "thumb.jpg")
        let creator = VTISOCreator(title: "Test", creatorDisplayName: "tester")
        creator.background = .hexColor("#0a0a1f")
        _ = try creator.addVideo(title: "Episode 1", fileURL: video, thumbnailURL: thumb, tags: ["ok"])
        let out = try newOutputURL("test.vtiso")
        _ = try creator.build(to: out)
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
    }

    func testBuildsToOutputURLThatDoesNotExistYet() throws {
        let creator = try makeCreatorWithVideo()
        let out = try newOutputURL("fresh.vtiso")
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
        _ = try creator.build(to: out)
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
        XCTAssertEqual(try extractManifest(out).title, "Test")
        try assertNoTempSiblings(around: out)
    }

    func testRejectsNonVTISOOutputExtension() throws {
        let creator = try makeCreatorWithVideo()
        let out = try newOutputURL("wrong.zip")
        XCTAssertThrowsError(try creator.build(to: out)) { error in
            guard case VTISOError.invalidOutputExtension = error as! VTISOError else {
                return XCTFail("expected invalidOutputExtension, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
    }

    func testStableDiscIdAcrossRepeatedBuilds() throws {
        let creator = try makeCreatorWithVideo()
        let out1 = try newOutputURL("a.vtiso")
        let out2 = try newOutputURL("b.vtiso")
        _ = try creator.build(to: out1)
        _ = try creator.build(to: out2)
        let m1 = try extractManifest(out1)
        let m2 = try extractManifest(out2)
        XCTAssertEqual(m1.discId, m2.discId)
        XCTAssertEqual(m1.discId, creator.discId)
    }

    func testExistingOutputIsReplaced() throws {
        let creator = try makeCreatorWithVideo()
        let out = try newOutputURL("replace.vtiso")
        try Data("not a zip".utf8).write(to: out)
        _ = try creator.build(to: out)
        let manifest = try extractManifest(out)
        XCTAssertEqual(manifest.title, "Test")
        try assertNoTempSiblings(around: out)
    }

    func testManifestAtArchiveRootWithNoWrappingFolder() throws {
        let creator = try makeCreatorWithVideo(videoID: "v1")
        let out = try newOutputURL()
        _ = try creator.build(to: out)
        let names = try archiveEntryNames(out)
        XCTAssertTrue(names.contains("manifest.json"))
        XCTAssertTrue(names.contains("videos/video_v1.mp4"))
        for n in names {
            XCTAssertFalse(n.hasPrefix("/"), "absolute entry path: \(n)")
            XCTAssertFalse(n.hasPrefix("staging/"), "wrapping folder leaked: \(n)")
            XCTAssertFalse(n.contains(".."), "traversal in entry path: \(n)")
        }
    }

    private func tempBuildArtifacts() throws -> Set<String> {
        let fm = FileManager.default
        return Set(try fm.contentsOfDirectory(atPath: fm.temporaryDirectory.path)
            .filter { $0.hasPrefix("vtiso-build-") || $0.hasPrefix("vtiso-archive-") })
    }

    func testTempArtifactsCleanedUpAfterSuccessfulBuild() throws {
        let before = try tempBuildArtifacts()
        let creator = try makeCreatorWithVideo()
        _ = try creator.build(to: try newOutputURL())
        XCTAssertEqual(try tempBuildArtifacts(), before, "temporary artifacts were left behind after success")
    }

    func testTempDirectoriesCleanedUpAfterFailedBuild() throws {
        let fm = FileManager.default
        func buildTempDirs() throws -> Set<String> {
            try tempBuildArtifacts()
        }
        let before = try buildTempDirs()

        // Force a failure during assembly (after the temp dir is created):
        // a required text field with no value.
        let creator = try makeCreatorWithVideo()
        let spec = makeSpec(textFields: [
            CxTextField(id: "greeting", label: "Greeting", description: nil,
                        defaultValue: nil, required: true, maxLength: nil,
                        bucketFile: "options.json", group: nil, perVideo: nil)
        ])
        try creator.setClientExtension(spec)
        let out = try newOutputURL("fail.vtiso")
        XCTAssertThrowsError(try creator.build(to: out))
        XCTAssertFalse(fm.fileExists(atPath: out.path))
        XCTAssertEqual(try buildTempDirs(), before, "temporary build directories were left behind")
    }

    // MARK: - Manifest validation

    func testRejectsInvalidHexColor() throws {
        let creator = try makeCreatorWithVideo()
        creator.background = .hexColor("not-a-color")
        XCTAssertThrowsError(try creator.build(to: try newOutputURL("bad.vtiso")))
    }

    func testRejectsDuplicateVideoID() throws {
        let video = try makeTempFile(name: "clip.mp4")
        let creator = VTISOCreator(title: "Dup", creatorDisplayName: "x")
        _ = try creator.addVideo(id: "same", title: "a", fileURL: video)
        XCTAssertThrowsError(try creator.addVideo(id: "same", title: "b", fileURL: video))
    }

    func testRejectsEmptyTitleAndCreatorName() throws {
        let creator = try makeCreatorWithVideo()
        creator.title = "   "
        XCTAssertThrowsError(try creator.build(to: try newOutputURL()))
        creator.title = "ok"
        creator.creator.displayName = ""
        XCTAssertThrowsError(try creator.build(to: try newOutputURL()))
    }

    func testRejectsUnsupportedMinRuntime() throws {
        let creator = try makeCreatorWithVideo()
        creator.compatibility.minRuntime = "2.0"
        XCTAssertThrowsError(try creator.build(to: try newOutputURL())) { error in
            guard case VTISOError.unsupportedVTISOVersion = error as! VTISOError else {
                return XCTFail("expected unsupportedVTISOVersion, got \(error)")
            }
        }
    }

    func testBackgroundIsSourceOfTruthForMenuBackground() throws {
        let creator = try makeCreatorWithVideo()
        creator.menu.background = "stale-value"
        creator.background = .hexColor("#0a0a1f")
        let out = try newOutputURL()
        _ = try creator.build(to: out)
        XCTAssertEqual(try extractManifest(out).menu.background, "#0a0a1f")

        creator.background = .none
        let out2 = try newOutputURL()
        _ = try creator.build(to: out2)
        XCTAssertNil(try extractManifest(out2).menu.background)
    }

    // MARK: - Extras

    func testAddExtraRejectsDuplicateIDs() throws {
        let creator = try makeCreatorWithVideo()
        try creator.addExtra(id: "bonus", title: "Bonus", body: "b")
        XCTAssertThrowsError(try creator.addExtra(id: "bonus", title: "Again", body: "b")) { error in
            guard case VTISOError.duplicateExtraID("bonus") = error as! VTISOError else {
                return XCTFail("expected duplicateExtraID, got \(error)")
            }
        }
        // Default parameter keeps the old call shape working.
        try creator.addExtra(title: "No explicit ID", body: "b")
        let out = try newOutputURL()
        _ = try creator.build(to: out)
        XCTAssertEqual(try extractManifest(out).extras?.count, 2)
    }

    // MARK: - Bucket paths

    func testDeclaredBucketPathIsUsed() throws {
        let creator = try makeCreatorWithVideo()
        let spec = makeSpec(clientId: "oyster",
                            bucketDefinitions: [CxBucketDefinition(bucketId: "oyster", path: "oyster-data")])
        try creator.setClientExtension(spec)
        let out = try newOutputURL()
        _ = try creator.build(to: out)
        let names = try archiveEntryNames(out)
        XCTAssertTrue(names.contains("oyster-data/client.json"), "entries: \(names)")
        XCTAssertFalse(names.contains("client-buckets/oyster/client.json"))
        let manifest = try extractManifest(out)
        XCTAssertEqual(manifest.clientBuckets?.first?.path, "oyster-data/")
    }

    func testFallbackBucketPathWhenNoMatchingDefinition() throws {
        let creator = try makeCreatorWithVideo()
        let spec = makeSpec(clientId: "oyster",
                            bucketDefinitions: [CxBucketDefinition(bucketId: "someone-else", path: "other-data/")])
        try creator.setClientExtension(spec)
        let out = try newOutputURL()
        _ = try creator.build(to: out)
        let names = try archiveEntryNames(out)
        XCTAssertTrue(names.contains("client-buckets/oyster/client.json"), "entries: \(names)")
        XCTAssertEqual(try extractManifest(out).clientBuckets?.first?.path, "client-buckets/oyster/")
    }

    func testRejectsUnsafeBucketPaths() throws {
        for bad in ["../escape", "/absolute", "http://example.com/x", "a//b"] {
            let creator = try makeCreatorWithVideo()
            let spec = makeSpec(bucketDefinitions: [CxBucketDefinition(bucketId: "oyster", path: bad)])
            XCTAssertThrowsError(try creator.setClientExtension(spec), "path '\(bad)' should be rejected")
        }
    }

    func testRejectsDuplicateBucketIDsAndPaths() throws {
        let creator = try makeCreatorWithVideo()
        let dupIDs = makeSpec(bucketDefinitions: [
            CxBucketDefinition(bucketId: "oyster", path: "a"),
            CxBucketDefinition(bucketId: "oyster", path: "b")
        ])
        XCTAssertThrowsError(try creator.setClientExtension(dupIDs))

        let dupPaths = makeSpec(bucketDefinitions: [
            CxBucketDefinition(bucketId: "one", path: "shared/"),
            CxBucketDefinition(bucketId: "two", path: "shared")
        ])
        XCTAssertThrowsError(try creator.setClientExtension(dupPaths))
    }

    func testRejectsEmptyClientId() throws {
        let creator = try makeCreatorWithVideo()
        XCTAssertThrowsError(try creator.setClientExtension(makeSpec(clientId: "")))
    }

    // MARK: - Client value validation

    func testRejectsUnknownVideoIDInPerVideoValues() throws {
        let creator = try makeCreatorWithVideo(videoID: "v1")
        let spec = makeSpec(customLists: [
            CxCustomListField(id: "chapters", label: "Chapters", description: nil,
                              required: false, minItems: nil, maxItems: nil,
                              bucketFile: "custom-lists/chapters.json",
                              itemSchema: ["name": .primitive("string")], perVideo: true)
        ])
        try creator.setClientExtension(spec)
        creator.setPerVideoCustomListItems(videoID: "nope", listID: "chapters",
                                           items: [.object(["name": .string("x")])])
        XCTAssertThrowsError(try creator.build(to: try newOutputURL())) { error in
            guard case VTISOError.unknownReferencedVideoID("nope") = error as! VTISOError else {
                return XCTFail("expected unknownReferencedVideoID, got \(error)")
            }
        }
    }

    func testRejectsUnknownFieldIDs() throws {
        let creator = try makeCreatorWithVideo()
        try creator.setClientExtension(makeSpec())
        creator.setClientOptionText(id: "does-not-exist", value: "hi")
        XCTAssertThrowsError(try creator.build(to: try newOutputURL())) { error in
            guard case VTISOError.unknownExtensionFieldID = error as! VTISOError else {
                return XCTFail("expected unknownExtensionFieldID, got \(error)")
            }
        }
    }

    func testRejectsClientValuesWithoutExtension() throws {
        let creator = try makeCreatorWithVideo()
        creator.setClientOptionCheckbox(id: "x", value: true)
        XCTAssertThrowsError(try creator.build(to: try newOutputURL()))
    }

    func testRejectsPerVideoSharedMisuse() throws {
        let spec = makeSpec(textFields: [
            CxTextField(id: "shared-note", label: "n", description: nil, defaultValue: "d",
                        required: false, maxLength: nil, bucketFile: "options.json",
                        group: nil, perVideo: nil),
            CxTextField(id: "video-note", label: "n", description: nil, defaultValue: "d",
                        required: false, maxLength: nil, bucketFile: "options.json",
                        group: nil, perVideo: true)
        ])

        // Shared field given a video ID -> rejected.
        let c1 = try makeCreatorWithVideo(videoID: "v1")
        try c1.setClientExtension(spec)
        c1.setClientOptionText(id: "shared-note", value: "x", videoID: "v1")
        XCTAssertThrowsError(try c1.build(to: try newOutputURL())) { error in
            guard case VTISOError.invalidExtensionValue = error as! VTISOError else {
                return XCTFail("expected invalidExtensionValue, got \(error)")
            }
        }

        // Per-video field given no video ID -> rejected.
        let c2 = try makeCreatorWithVideo(videoID: "v1")
        try c2.setClientExtension(spec)
        c2.setClientOptionText(id: "video-note", value: "x")
        XCTAssertThrowsError(try c2.build(to: try newOutputURL())) { error in
            guard case VTISOError.invalidExtensionValue = error as! VTISOError else {
                return XCTFail("expected invalidExtensionValue, got \(error)")
            }
        }
    }

    func testRejectsInvalidSelectOption() throws {
        let spec = makeSpec(selectFields: [
            CxSelectField(id: "theme", label: "Theme", description: nil,
                          options: ["light", "dark"], defaultValue: "light",
                          required: false, bucketFile: "options.json", group: nil, perVideo: nil)
        ])
        let creator = try makeCreatorWithVideo()
        try creator.setClientExtension(spec)
        creator.setClientOptionSelect(id: "theme", value: "neon")
        XCTAssertThrowsError(try creator.build(to: try newOutputURL())) { error in
            guard case VTISOError.invalidExtensionValue = error as! VTISOError else {
                return XCTFail("expected invalidExtensionValue, got \(error)")
            }
        }
    }

    func testRejectsInvalidSelectDefault() throws {
        let spec = makeSpec(selectFields: [
            CxSelectField(id: "theme", label: "Theme", description: nil,
                          options: ["light", "dark"], defaultValue: "purple",
                          required: false, bucketFile: "options.json", group: nil, perVideo: nil)
        ])
        let creator = try makeCreatorWithVideo()
        try creator.setClientExtension(spec)
        XCTAssertThrowsError(try creator.build(to: try newOutputURL()))
    }

    func testEnforcesTextMaxLength() throws {
        let spec = makeSpec(textFields: [
            CxTextField(id: "greeting", label: "g", description: nil, defaultValue: nil,
                        required: false, maxLength: 3, bucketFile: "options.json",
                        group: nil, perVideo: nil)
        ])
        let creator = try makeCreatorWithVideo()
        try creator.setClientExtension(spec)
        creator.setClientOptionText(id: "greeting", value: "too long")
        XCTAssertThrowsError(try creator.build(to: try newOutputURL())) { error in
            let description = "\(error)"
            XCTAssertTrue(description.contains("greeting"), "error should name the field: \(description)")
        }
    }

    func testRequiredPerVideoTextValidatedPerVideo() throws {
        let creator = VTISOCreator(title: "T", creatorDisplayName: "x")
        let video = try makeTempFile(name: "clip.mp4")
        _ = try creator.addVideo(id: "v1", title: "a", fileURL: video)
        _ = try creator.addVideo(id: "v2", title: "b", fileURL: video)
        let spec = makeSpec(textFields: [
            CxTextField(id: "note", label: "n", description: nil, defaultValue: nil,
                        required: true, maxLength: nil, bucketFile: "options.json",
                        group: nil, perVideo: true)
        ])
        try creator.setClientExtension(spec)
        creator.setClientOptionText(id: "note", value: "present", videoID: "v1")
        // v2 has no value -> must fail even though v1 (and no shared key) is set.
        XCTAssertThrowsError(try creator.build(to: try newOutputURL())) { error in
            XCTAssertTrue("\(error)".contains("v2"), "error should name the missing video: \(error)")
        }
        creator.setClientOptionText(id: "note", value: "also present", videoID: "v2")
        XCTAssertNoThrow(try creator.build(to: try newOutputURL()))
    }

    // MARK: - Uploads

    private func uploadSpec(allowedTypes: [String] = [],
                            multiple: Bool = true,
                            required: Bool = false,
                            maxSizeBytes: Int? = nil,
                            perVideo: Bool? = nil) -> ClientExtensionSpec {
        makeSpec(fileUploads: [
            CxFileUploadField(id: "res", label: "Resource", description: nil,
                              allowedTypes: allowedTypes, multiple: multiple,
                              required: required, destination: "uploads",
                              maxSizeBytes: maxSizeBytes, perVideo: perVideo)
        ])
    }

    func testUploadRejectsMultipleWhenSingleOnly() throws {
        let creator = try makeCreatorWithVideo()
        try creator.setClientExtension(uploadSpec(multiple: false))
        try creator.addClientUpload(uploadID: "res", fileURL: try makeTempFile(name: "a.txt"))
        try creator.addClientUpload(uploadID: "res", fileURL: try makeTempFile(name: "b.txt"))
        XCTAssertThrowsError(try creator.build(to: try newOutputURL()))
    }

    func testUploadRejectsOversizedFile() throws {
        let creator = try makeCreatorWithVideo()
        try creator.setClientExtension(uploadSpec(maxSizeBytes: 2))
        try creator.addClientUpload(uploadID: "res", fileURL: try makeTempFile(name: "big.bin", bytes: [1, 2, 3, 4, 5]))
        XCTAssertThrowsError(try creator.build(to: try newOutputURL()))
    }

    func testUploadValidatesAllowedTypes() throws {
        // Extension-style entry.
        let c1 = try makeCreatorWithVideo()
        try c1.setClientExtension(uploadSpec(allowedTypes: [".png"]))
        try c1.addClientUpload(uploadID: "res", fileURL: try makeTempFile(name: "notes.txt"))
        XCTAssertThrowsError(try c1.build(to: try newOutputURL()))

        let c2 = try makeCreatorWithVideo()
        try c2.setClientExtension(uploadSpec(allowedTypes: [".png"]))
        try c2.addClientUpload(uploadID: "res", fileURL: try makeTempFile(name: "pic.PNG"))
        XCTAssertNoThrow(try c2.build(to: try newOutputURL()))

        // Wildcard MIME group.
        let c3 = try makeCreatorWithVideo()
        try c3.setClientExtension(uploadSpec(allowedTypes: ["image/*"]))
        try c3.addClientUpload(uploadID: "res", fileURL: try makeTempFile(name: "pic.jpg"))
        XCTAssertNoThrow(try c3.build(to: try newOutputURL()))

        let c4 = try makeCreatorWithVideo()
        try c4.setClientExtension(uploadSpec(allowedTypes: ["image/*"]))
        try c4.addClientUpload(uploadID: "res", fileURL: try makeTempFile(name: "notes.txt"))
        XCTAssertThrowsError(try c4.build(to: try newOutputURL()))

        // Exact MIME entry.
        let c5 = try makeCreatorWithVideo()
        try c5.setClientExtension(uploadSpec(allowedTypes: ["application/json"]))
        try c5.addClientUpload(uploadID: "res", fileURL: try makeTempFile(name: "data.json"))
        XCTAssertNoThrow(try c5.build(to: try newOutputURL()))
    }

    func testRequiredPerVideoUpload() throws {
        let creator = VTISOCreator(title: "T", creatorDisplayName: "x")
        let video = try makeTempFile(name: "clip.mp4")
        _ = try creator.addVideo(id: "v1", title: "a", fileURL: video)
        _ = try creator.addVideo(id: "v2", title: "b", fileURL: video)
        try creator.setClientExtension(uploadSpec(required: true, perVideo: true))
        try creator.addClientUpload(uploadID: "res", fileURL: try makeTempFile(name: "a.txt"), videoID: "v1")
        XCTAssertThrowsError(try creator.build(to: try newOutputURL())) { error in
            XCTAssertTrue("\(error)".contains("v2"), "error should name the missing video: \(error)")
        }
        try creator.addClientUpload(uploadID: "res", fileURL: try makeTempFile(name: "b.txt"), videoID: "v2")
        XCTAssertNoThrow(try creator.build(to: try newOutputURL()))
    }

    // MARK: - Custom lists

    func testCustomListMinMaxItems() throws {
        let spec = makeSpec(customLists: [
            CxCustomListField(id: "faq", label: "FAQ", description: nil,
                              required: false, minItems: 2, maxItems: 3,
                              bucketFile: "custom-lists/faq.json",
                              itemSchema: ["q": .primitive("string")], perVideo: nil)
        ])
        let item: VTISOJSON = .object(["q": .string("?")])

        let c1 = try makeCreatorWithVideo()
        try c1.setClientExtension(spec)
        c1.setCustomListItems(listID: "faq", items: [item])
        XCTAssertThrowsError(try c1.build(to: try newOutputURL()))

        let c2 = try makeCreatorWithVideo()
        try c2.setClientExtension(spec)
        c2.setCustomListItems(listID: "faq", items: [item, item, item, item])
        XCTAssertThrowsError(try c2.build(to: try newOutputURL()))

        let c3 = try makeCreatorWithVideo()
        try c3.setClientExtension(spec)
        c3.setCustomListItems(listID: "faq", items: [item, item])
        XCTAssertNoThrow(try c3.build(to: try newOutputURL()))
    }

    func testRecursiveItemSchemaValidation() throws {
        let schema: [String: CxItemSchemaFieldType] = [
            "name": .primitive("string"),
            "tags": .primitive("string[]"),
            "meta": .object(fields: ["count": .primitive("number")]),
            "rows": .array(items: .object(fields: ["ok": .primitive("boolean")]))
        ]
        let spec = makeSpec(customLists: [
            CxCustomListField(id: "deep", label: "Deep", description: nil,
                              required: false, minItems: nil, maxItems: nil,
                              bucketFile: "custom-lists/deep.json",
                              itemSchema: schema, perVideo: nil)
        ])

        let valid: VTISOJSON = .object([
            "name": .string("a"),
            "tags": .array([.string("x"), .string("y")]),
            "meta": .object(["count": .number(2)]),
            "rows": .array([.object(["ok": .bool(true)])])
        ])
        let c1 = try makeCreatorWithVideo()
        try c1.setClientExtension(spec)
        c1.setCustomListItems(listID: "deep", items: [valid])
        XCTAssertNoThrow(try c1.build(to: try newOutputURL()))

        // Wrong primitive type deep inside a nested array of objects.
        let invalid: VTISOJSON = .object([
            "name": .string("a"),
            "tags": .array([.string("x")]),
            "meta": .object(["count": .number(2)]),
            "rows": .array([.object(["ok": .string("not-a-bool")])])
        ])
        let c2 = try makeCreatorWithVideo()
        try c2.setClientExtension(spec)
        c2.setCustomListItems(listID: "deep", items: [invalid])
        XCTAssertThrowsError(try c2.build(to: try newOutputURL())) { error in
            let d = "\(error)"
            XCTAssertTrue(d.contains("deep"), "error should name the list: \(d)")
            XCTAssertTrue(d.contains("rows"), "error should name the field path: \(d)")
        }

        // Missing declared field.
        let missing: VTISOJSON = .object(["name": .string("a")])
        let c3 = try makeCreatorWithVideo()
        try c3.setClientExtension(spec)
        c3.setCustomListItems(listID: "deep", items: [missing])
        XCTAssertThrowsError(try c3.build(to: try newOutputURL()))
    }

    func testRejectsUnsupportedSchemaPrimitive() throws {
        let creator = try makeCreatorWithVideo()
        let spec = makeSpec(customLists: [
            CxCustomListField(id: "bad", label: "Bad", description: nil,
                              required: false, minItems: nil, maxItems: nil,
                              bucketFile: "custom-lists/bad.json",
                              itemSchema: ["when": .primitive("datetime")], perVideo: nil)
        ])
        XCTAssertThrowsError(try creator.setClientExtension(spec)) { error in
            guard case VTISOError.invalidClientDefinition = error as! VTISOError else {
                return XCTFail("expected invalidClientDefinition, got \(error)")
            }
        }
    }

    func testFileSchemaValidatedAsPathString() throws {
        let spec = makeSpec(customLists: [
            CxCustomListField(id: "gallery", label: "G", description: nil,
                              required: false, minItems: nil, maxItems: nil,
                              bucketFile: "custom-lists/gallery.json",
                              itemSchema: ["image": .primitive("file")], perVideo: nil)
        ])
        let c1 = try makeCreatorWithVideo()
        try c1.setClientExtension(spec)
        c1.setCustomListItems(listID: "gallery", items: [.object(["image": .string("uploads/pic.png")])])
        XCTAssertNoThrow(try c1.build(to: try newOutputURL()))

        let c2 = try makeCreatorWithVideo()
        try c2.setClientExtension(spec)
        c2.setCustomListItems(listID: "gallery", items: [.object(["image": .number(7)])])
        XCTAssertThrowsError(try c2.build(to: try newOutputURL()))
    }

    // MARK: - client.json round trip

    func testImportedClientJSONWrittenBackVerbatim() throws {
        let json = """
        {
          "clientId": "oyster",
          "clientName": "Oyster",
          "extensionVersion": "2.3",
          "minimumRuntimeVersion": "1.0",
          "supportedPlatforms": ["web", "tv"],
          "exportFeatures": {
            "fileUploads": [],
            "customLists": [
              {
                "id": "chapters",
                "label": "Chapters",
                "required": false,
                "bucketFile": "custom-lists/chapters.json",
                "itemSchema": { "name": "string", "time": "string" },
                "perVideo": true
              }
            ],
            "checkboxes": [],
            "textFields": [],
            "selectFields": [],
            "menuAdditions": []
          },
          "bucketDefinitions": [
            { "bucketId": "oyster", "path": "client-buckets/oyster/" }
          ]
        }
        """
        let file = try makeTempFile(name: "client.json", bytes: [])
        try Data(json.utf8).write(to: file)

        let creator = try makeCreatorWithVideo(videoID: "v1")
        try creator.addClientExtension(definitionURL: file)
        creator.setPerVideoCustomListItems(videoID: "v1", listID: "chapters",
                                           items: [.object(["name": .string("Intro"), "time": .string("0:00")])])
        let out = try newOutputURL()
        _ = try creator.build(to: out)

        let packaged = try extractEntry(out, path: "client-buckets/oyster/client.json")
        XCTAssertEqual(packaged, Data(json.utf8), "imported client.json must be preserved byte-for-byte")
        XCTAssertTrue(try archiveEntryNames(out)
            .contains("client-buckets/oyster/per-video/v1/custom-lists/chapters.json"))
    }

    // MARK: - Public model initializers

    func testPublicModelInitializersWithDefaults() throws {
        let spec = ClientExtensionSpec(clientId: "example-client", clientName: "Example Client")
        XCTAssertEqual(spec.extensionVersion, "1.0")
        XCTAssertEqual(spec.minimumRuntimeVersion, "1.0")
        XCTAssertEqual(spec.supportedPlatforms, [])
        XCTAssertTrue(spec.exportFeatures.fileUploads.isEmpty)
        XCTAssertEqual(spec.bucketDefinitions.count, 1)
        XCTAssertEqual(spec.bucketDefinitions.first?.bucketId, "example-client")
        XCTAssertEqual(spec.bucketDefinitions.first?.path, "client-buckets/example-client/")

        // Explicit definitions (even empty) are used as-is, no fallback.
        let explicit = ClientExtensionSpec(clientId: "x", clientName: "X", bucketDefinitions: [])
        XCTAssertTrue(explicit.bucketDefinitions.isEmpty)

        _ = CxFileUploadField(id: "u", label: "U", destination: "uploads")
        _ = CxCustomListField(id: "l", label: "L", bucketFile: "l.json", itemSchema: [:])
        _ = CxCheckboxField(id: "c", label: "C", bucketFile: "o.json")
        _ = CxTextField(id: "t", label: "T", bucketFile: "o.json")
        _ = CxSelectField(id: "s", label: "S", options: ["a"], bucketFile: "o.json")
        _ = CxMenuAddition(id: "m", label: "M")
    }

    // MARK: - Definition-level validation

    func testRejectsEmptyClientName() throws {
        let creator = try makeCreatorWithVideo()
        var spec = makeSpec()
        spec.clientName = "  "
        XCTAssertThrowsError(try creator.setClientExtension(spec)) { error in
            guard case VTISOError.invalidClientDefinition = error as! VTISOError else {
                return XCTFail("expected invalidClientDefinition, got \(error)")
            }
        }
    }

    func testRejectsDuplicateAndEmptyExportFeatureIDs() throws {
        let creator = try makeCreatorWithVideo()

        // Duplicate within a category.
        let sameCategory = makeSpec(checkboxes: [
            CxCheckboxField(id: "dup", label: "a", bucketFile: "o.json"),
            CxCheckboxField(id: "dup", label: "b", bucketFile: "o.json")
        ])
        XCTAssertThrowsError(try creator.setClientExtension(sameCategory))

        // Duplicate across categories (IDs are globally unique).
        let crossCategory = makeSpec(checkboxes: [CxCheckboxField(id: "dup", label: "a", bucketFile: "o.json")],
                                     textFields: [CxTextField(id: "dup", label: "b", bucketFile: "o.json")])
        XCTAssertThrowsError(try creator.setClientExtension(crossCategory))

        // Empty ID.
        let emptyID = makeSpec(selectFields: [CxSelectField(id: "", label: "s", options: ["a"], bucketFile: "o.json")])
        XCTAssertThrowsError(try creator.setClientExtension(emptyID))
    }

    func testCategoryMismatchProducesClearError() throws {
        let creator = try makeCreatorWithVideo()
        try creator.setClientExtension(makeSpec(textFields: [
            CxTextField(id: "note", label: "N", bucketFile: "o.json")
        ]))
        // "note" exists, but as a text field — using it as a checkbox must fail.
        creator.setClientOptionCheckbox(id: "note", value: true)
        XCTAssertThrowsError(try creator.build(to: try newOutputURL())) { error in
            let d = "\(error)"
            XCTAssertTrue(d.contains("note"), "error should name the ID: \(d)")
            XCTAssertTrue(d.contains("text field"), "error should name the actual category: \(d)")
        }
    }

    // MARK: - Destination handling

    func testRejectsDirectoryDestination() throws {
        let creator = try makeCreatorWithVideo()
        let dir = try newOutputURL("folder.vtiso")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertThrowsError(try creator.build(to: dir)) { error in
            guard case VTISOError.outputWriteFailed = error as! VTISOError else {
                return XCTFail("expected outputWriteFailed, got \(error)")
            }
        }
    }

    func testCreatesMissingDestinationParentDirectory() throws {
        let creator = try makeCreatorWithVideo()
        let out = try newOutputURL().deletingLastPathComponent()
            .appendingPathComponent("nested/deeper/out.vtiso")
        _ = try creator.build(to: out)
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
    }

    func testOldOutputPreservedWhenNewBuildFails() throws {
        let out = try newOutputURL("keep.vtiso")
        let good = try makeCreatorWithVideo()
        _ = try good.build(to: out)
        let originalData = try Data(contentsOf: out)

        // Second build fails during assembly (required text missing).
        let bad = try makeCreatorWithVideo()
        try bad.setClientExtension(makeSpec(textFields: [
            CxTextField(id: "req", label: "R", required: true, bucketFile: "o.json")
        ]))
        XCTAssertThrowsError(try bad.build(to: out))

        XCTAssertEqual(try Data(contentsOf: out), originalData, "failed build must not touch the existing output")
        XCTAssertEqual(try extractManifest(out).title, "Test")
        try assertNoTempSiblings(around: out)
    }

    func testTempArchiveIsCreatedInDestinationParentDirectory() throws {
        let fm = FileManager.default
        let creator = try makeCreatorWithVideo()
        let out = try newOutputURL("blocked.vtiso")
        let parent = out.deletingLastPathComponent()

        // Make the destination parent read-only: if the temporary archive is
        // staged there (same volume as the destination), archive *creation*
        // fails with zipCreationFailed. If it were staged in the global temp
        // directory instead, creation would succeed and the failure would
        // surface later as outputWriteFailed.
        try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: parent.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path) }
        try XCTSkipIf(fm.isWritableFile(atPath: parent.path),
                      "filesystem permissions are not enforced (running as root?)")

        XCTAssertThrowsError(try creator.build(to: out)) { error in
            guard case VTISOError.zipCreationFailed = error as! VTISOError else {
                return XCTFail("expected zipCreationFailed from sibling temp archive, got \(error)")
            }
        }
        XCTAssertFalse(fm.fileExists(atPath: out.path))
        try assertNoTempSiblings(around: out)
    }

    func testFailedArchiveCreationPreservesExistingDestination() throws {
        let fm = FileManager.default
        let out = try newOutputURL("keep-on-zip-failure.vtiso")
        let good = try makeCreatorWithVideo()
        _ = try good.build(to: out)
        let originalData = try Data(contentsOf: out)

        // A staging directory containing an unreadable file makes archive
        // creation fail after the writer's up-front checks pass.
        let staging = fm.temporaryDirectory
            .appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: staging.appendingPathComponent("manifest.json"))
        let unreadable = staging.appendingPathComponent("unreadable.bin")
        try Data([1, 2, 3]).write(to: unreadable)
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unreadable.path) }
        try XCTSkipIf(fm.isReadableFile(atPath: unreadable.path),
                      "filesystem permissions are not enforced (running as root?)")

        XCTAssertThrowsError(try VTISOPackageWriter.writeArchive(stagingDir: staging, to: out)) { error in
            guard case VTISOError.zipCreationFailed = error as! VTISOError else {
                return XCTFail("expected zipCreationFailed, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: out), originalData,
                       "existing destination must remain untouched when archive creation fails")
        XCTAssertEqual(try extractManifest(out).title, "Test")
        try assertNoTempSiblings(around: out)
    }

    func testWriterRejectsMissingStagingOrManifest() throws {
        let fm = FileManager.default
        let out = try newOutputURL("w.vtiso")
        let missing = fm.temporaryDirectory.appendingPathComponent("does-not-exist-\(UUID().uuidString)")
        XCTAssertThrowsError(try VTISOPackageWriter.writeArchive(stagingDir: missing, to: out))

        let emptyStaging = fm.temporaryDirectory.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: emptyStaging, withIntermediateDirectories: true)
        XCTAssertThrowsError(try VTISOPackageWriter.writeArchive(stagingDir: emptyStaging, to: out))
        XCTAssertFalse(fm.fileExists(atPath: out.path))
    }

    // MARK: - Video validation

    func testRejectsEmptyVideoTitle() throws {
        let creator = VTISOCreator(title: "T", creatorDisplayName: "x")
        let video = try makeTempFile(name: "clip.mp4")
        _ = try creator.addVideo(id: "v1", title: "  ", fileURL: video)
        XCTAssertThrowsError(try creator.build(to: try newOutputURL()))
    }

    func testRejectsSourceFileRemovedAfterAdding() throws {
        let creator = VTISOCreator(title: "T", creatorDisplayName: "x")
        let video = try makeTempFile(name: "clip.mp4")
        _ = try creator.addVideo(id: "v1", title: "a", fileURL: video)
        try FileManager.default.removeItem(at: video)
        XCTAssertThrowsError(try creator.build(to: try newOutputURL())) { error in
            guard case VTISOError.sourceFileMissing = error as! VTISOError else {
                return XCTFail("expected sourceFileMissing, got \(error)")
            }
        }
    }

    // MARK: - Optional-list file behavior (documented)

    func testDeclaredOptionalEmptyListWritesEmptyArray() throws {
        let creator = try makeCreatorWithVideo()
        try creator.setClientExtension(makeSpec(customLists: [
            CxCustomListField(id: "faq", label: "FAQ", bucketFile: "custom-lists/faq.json",
                              itemSchema: ["q": .primitive("string")])
        ]))
        let out = try newOutputURL()
        _ = try creator.build(to: out)
        let data = try extractEntry(out, path: "client-buckets/oyster/custom-lists/faq.json")
        let decoded = try JSONDecoder().decode([VTISOJSON].self, from: data)
        XCTAssertTrue(decoded.isEmpty, "declared optional lists are written as an empty JSON array")
    }

    // MARK: - Path & misc primitives

    func testPathValidatorRejectsTraversal() {
        XCTAssertThrowsError(try VTISOPathValidator.validate("../etc/passwd"))
        XCTAssertThrowsError(try VTISOPathValidator.validate("/absolute"))
        XCTAssertThrowsError(try VTISOPathValidator.validate("with//empty"))
        XCTAssertThrowsError(try VTISOPathValidator.validate("http://example.com"))
        XCTAssertThrowsError(try VTISOPathValidator.validate("a/./b"))
        XCTAssertNoThrow(try VTISOPathValidator.validate("videos/video_1.mp4"))
    }

    func testPathValidatorRejectsWindowsBackslashAndNulPaths() {
        XCTAssertThrowsError(try VTISOPathValidator.validate("C:/file"))
        XCTAssertThrowsError(try VTISOPathValidator.validate("c:/windows/system32"))
        XCTAssertThrowsError(try VTISOPathValidator.validate("folder\\file.txt"))
        XCTAssertThrowsError(try VTISOPathValidator.validate("a/b\\c"))
        XCTAssertThrowsError(try VTISOPathValidator.validate("bad\u{0}name"))
        XCTAssertThrowsError(try VTISOPathValidator.validate(""))
    }

    func testSanitizeFilenameNeverEmpty() {
        XCTAssertEqual(VTISOPathValidator.sanitizeFilename(""), "file")
        XCTAssertEqual(VTISOPathValidator.sanitizeFilename("a/b:c"), "a_b_c")
        XCTAssertEqual(VTISOPathValidator.sanitizeFilename("ok-name_1.txt"), "ok-name_1.txt")
        // Dots-only names survive sanitization but are rejected as path
        // components by the validator, so they can never enter a package.
        XCTAssertThrowsError(try VTISOPathValidator.validate("uploads/\(VTISOPathValidator.sanitizeFilename(".."))"))
    }

    func testErrorsProvideLocalizedDescriptions() {
        let error: VTISOError = .invalidOutputExtension("out.zip")
        XCTAssertEqual(error.errorDescription, error.description)
        XCTAssertTrue(error.localizedDescription.contains("out.zip"),
                      "localizedDescription should carry the real message: \(error.localizedDescription)")
        let unknown: VTISOError = .unknownExtensionFieldID("x")
        XCTAssertNotNil((unknown as LocalizedError).errorDescription)
    }

    func testHexRegex() {
        XCTAssertTrue(VTISOBackground.isValidHex("#fff"))
        XCTAssertTrue(VTISOBackground.isValidHex("#0a0a1f"))
        XCTAssertTrue(VTISOBackground.isValidHex("#0a0a1fcc"))
        XCTAssertFalse(VTISOBackground.isValidHex("#zzz"))
        XCTAssertFalse(VTISOBackground.isValidHex("blue"))
    }

    func testAllSixLayoutsEncode() throws {
        for layout in VTISOMenuLayout.allCases {
            let menu = VTISOMenu(layout: layout)
            let data = try JSONEncoder().encode(menu)
            XCTAssertFalse(data.isEmpty)
        }
    }
}
