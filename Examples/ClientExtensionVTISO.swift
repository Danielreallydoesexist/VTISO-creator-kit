import Foundation
import VTISOCreatorKit

// Import a client.json produced by VideoThing's visual editor and package
// its declared values + files into the correct client bucket.
func makeClientExtensionVTISO(outputURL: URL,
                              video: URL,
                              clientJSON: URL,
                              anyUpload: URL) throws -> URL {
    let creator = VTISOCreator(title: "Ext Demo", creatorDisplayName: "tester")
    _ = try creator.addVideo(title: "v1", fileURL: video)

    try creator.addClientExtension(definitionURL: clientJSON)

    creator.setClientOptionCheckbox(id: "shuffle-on-open", value: true)
    creator.setClientOptionText(id: "greeting", value: "hi")
    creator.setClientOptionSelect(id: "theme", value: "dark")

    creator.setCustomListItems(listID: "faq", items: [
        .object(["q": .string("Why?"), "a": .string("Because.")])
    ])

    try creator.addClientUpload(uploadID: "resource-pack", fileURL: anyUpload)

    return try creator.build(to: outputURL)
}
