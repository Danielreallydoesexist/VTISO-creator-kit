import XCTest
@testable import VTISOCreatorKit

final class VTISOCreatorKitTests: XCTestCase {

    func makeTempFile(name: String, bytes: [UInt8] = [0, 1, 2, 3]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vtiso-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    func testBuildsMinimalPortableVTISO() throws {
        let video = try makeTempFile(name: "clip.mp4")
        let thumb = try makeTempFile(name: "thumb.jpg")
        let creator = VTISOCreator(title: "Test", creatorDisplayName: "tester")
        creator.background = .hexColor("#0a0a1f")
        _ = try creator.addVideo(title: "Episode 1", fileURL: video, thumbnailURL: thumb, tags: ["ok"])
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("test.vtiso")
        try? FileManager.default.removeItem(at: out)
        _ = try creator.build(to: out)
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
    }

    func testRejectsInvalidHexColor() throws {
        let video = try makeTempFile(name: "clip.mp4")
        let creator = VTISOCreator(title: "Bad", creatorDisplayName: "x")
        _ = try creator.addVideo(title: "v", fileURL: video)
        creator.background = .hexColor("not-a-color")
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("bad.vtiso")
        XCTAssertThrowsError(try creator.build(to: out))
    }

    func testRejectsDuplicateVideoID() throws {
        let video = try makeTempFile(name: "clip.mp4")
        let creator = VTISOCreator(title: "Dup", creatorDisplayName: "x")
        _ = try creator.addVideo(id: "same", title: "a", fileURL: video)
        XCTAssertThrowsError(try creator.addVideo(id: "same", title: "b", fileURL: video))
    }

    func testPathValidatorRejectsTraversal() {
        XCTAssertThrowsError(try VTISOPathValidator.validate("../etc/passwd"))
        XCTAssertThrowsError(try VTISOPathValidator.validate("/absolute"))
        XCTAssertThrowsError(try VTISOPathValidator.validate("with//empty"))
        XCTAssertThrowsError(try VTISOPathValidator.validate("http://example.com"))
        XCTAssertNoThrow(try VTISOPathValidator.validate("videos/video_1.mp4"))
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
