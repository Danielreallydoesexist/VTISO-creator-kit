import Foundation
import VTISOCreatorKit

// Package-relative image background copied into the disc.
func makeImageBackgroundVTISO(outputURL: URL, video: URL, bgImage: URL, cover: URL) throws -> URL {
    let creator = VTISOCreator(title: "Home Movies", creatorDisplayName: "family")
    creator.menu.layout = .theater
    creator.background = .imageFile(bgImage)
    try creator.setCover(fileURL: cover)
    _ = try creator.addVideo(title: "Trip 1", fileURL: video)
    return try creator.build(to: outputURL)
}
