#if canImport(SwiftUI)
import SwiftUI
import VTISOCreatorKit

// SwiftUI is not part of the core framework. This example lives outside the
// library target so the core stays UI-free and Playground-friendly.

@available(iOS 15, macOS 12, *)
struct ExportButtonExample: View {
    let videoURL: URL
    let destination: URL

    var body: some View {
        Button("Export .vtiso") {
            do {
                let creator = VTISOCreator(title: "SwiftUI Demo", creatorDisplayName: "you")
                creator.background = .hexColor("#0a0a1f")
                _ = try creator.addVideo(title: "Sample", fileURL: videoURL)
                _ = try creator.build(to: destination)
                print("Wrote", destination.path)
            } catch {
                print("Build failed:", error)
            }
        }
    }
}
#endif
