import Foundation
import VTISOCreatorKit

// Attach a per-video custom list. The generic API doesn't know about
// "chapters" specifically — it writes whatever items you pass.
func makePerVideoCustomListExample(outputURL: URL,
                                   video: URL,
                                   clientJSON: URL) throws -> URL {
    let creator = VTISOCreator(title: "Per-video demo", creatorDisplayName: "tester")
    let vid = try creator.addVideo(title: "Ep 1", fileURL: video)
    try creator.addClientExtension(definitionURL: clientJSON)

    creator.setPerVideoCustomListItems(
        videoID: vid,
        listID: "chapters",
        items: [
            .object(["name": .string("Intro"), "time": .string("0:00")]),
            .object(["name": .string("Middle"), "time": .string("0:03")])
        ]
    )

    return try creator.build(to: outputURL)
}
