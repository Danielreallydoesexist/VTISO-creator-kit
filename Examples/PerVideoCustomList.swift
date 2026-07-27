import Foundation
import VTISOCreatorKit

// Attach a per-video custom list. The generic API doesn't know about
// "chapters" specifically — it writes whatever items you pass, after
// validating them against the list's declared itemSchema.
//
// Per-video values must reference a video that exists on the creator —
// build(to:) throws for unknown video IDs. Note the video is added first
// and its returned ID is used below.
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
