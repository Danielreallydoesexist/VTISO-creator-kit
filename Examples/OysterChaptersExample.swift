import Foundation
import VTISOCreatorKit

// Oyster is a third-party VTISO client that reads a per-video "chapters"
// custom list. This framework has no Oyster-specific code — the same generic
// custom-list API is used. The bucket structure produced is:
//
//   client-buckets/oyster/
//     client.json
//     per-video/<video-id>/custom-lists/chapters.json
//
// where chapters.json is:
//
//   [
//     { "name": "When 4 and 5 added becomes nine", "time": "0:03" },
//     { "name": "Final title", "time": "0:16" }
//   ]

func makeOysterChaptersExample(outputURL: URL,
                               video: URL,
                               oysterClientJSON: URL) throws -> URL {
    let creator = VTISOCreator(title: "Math Show", creatorDisplayName: "mathperson")
    let vid = try creator.addVideo(title: "Episode 1", fileURL: video)
    try creator.addClientExtension(definitionURL: oysterClientJSON)

    creator.setPerVideoCustomListItems(
        videoID: vid,
        listID: "chapters",
        items: [
            .object(["name": .string("When 4 and 5 added becomes nine"), "time": .string("0:03")]),
            .object(["name": .string("Final title"), "time": .string("0:16")])
        ]
    )
    return try creator.build(to: outputURL)
}
