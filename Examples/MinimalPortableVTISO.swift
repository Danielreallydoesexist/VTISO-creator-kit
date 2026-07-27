import Foundation
import VTISOCreatorKit

// Simplest portable VTISO — no client extension, no cover, just videos.
func makeMinimalPortableVTISO(outputURL: URL, video: URL, thumb: URL) throws -> URL {
    let creator = VTISOCreator(title: "Windows videos", creatorDisplayName: "glowy videos")
    creator.description = "A collection of Windows videos"
    creator.menu.layout = .grid
    creator.background = .hexColor("#0a0a1f")

    _ = try creator.addVideo(
        title: "Funny Windows 7 crashing video",
        description: "Yay :3",
        fileURL: video,
        thumbnailURL: thumb,
        tags: ["exciting", "windows", "windows 7"]
    )

    return try creator.build(to: outputURL)
}
