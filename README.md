# VTISOCreatorKit

Pure-Swift framework for creating VTISO (`.vtiso`) packages — the offline video
disc format used by VideoThing. Reproduces VideoThing's current exporter
exactly. No new format features are invented.

- Platform-independent Swift + Foundation
- ZIP creation via [ZIPFoundation](https://github.com/weichsel/ZIPFoundation)
- No UIKit, AppKit, SwiftUI, or network in the core target
- Works in Swift Playgrounds, iOS, iPadOS, macOS, tvOS
- Fully offline / on-device

## Install (Swift Package Manager)

```swift
.package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
.package(path: "path/to/VTISOCreatorKit")
```

or drop the folder into a Swift Playgrounds "Modules" folder and add the
ZIPFoundation SPM dependency.

## Basic use

```swift
import VTISOCreatorKit

let creator = VTISOCreator(title: "Windows videos", creatorDisplayName: "glowy videos")
creator.description = "A collection of Windows videos"
creator.menu.layout  = .grid
creator.menu.buttonStyle = .glass
creator.menu.accent  = .fiery
creator.background   = .hexColor("#0a0a1f")

creator.playlist = VTISOPlaylistOptions(autoplay: true, loop: false, shuffle: false)

let videoID = try creator.addVideo(
    title: "Funny Windows 7 crashing video",
    description: "Yay :3",
    fileURL: videoURL,
    thumbnailURL: thumbnailURL,
    tags: ["exciting", "windows", "windows 7"]
)

_ = try creator.build(to: destinationURL) // writes destination.vtiso
```

## What is supported

Only the fields VideoThing currently exports:

- Manifest: `vtisoVersion` `discId` `belongingClient` `title` `subtitle`
  `description` `creator` `createdAt` `menu` `playlist` `videos` `extras`
  `permissions` `compatibility` `clientBuckets`
- Menu layouts: `classic-disc` `grid` `theater` `episode-list`
  `creator-showcase` `minimal-glass`
- Button styles: `pill` `square` `glass` `outline`
- Accents: `fiery` `neon` `gold` `sky` `pink`
- Backgrounds: hex color OR package-relative image (no gradients)
- Playlist: `autoplay` `loop` `shuffle`
- Permissions: `allowDownload` `allowExport`
- Compatibility: `minRuntime` `intendedForm`
- Videos: `id` `title` `description` `sourceType="local-file"` `source`
  `thumbnail` `tags`
- Client extensions: `fileUploads` `customLists` `checkboxes` `textFields`
  `selectFields` `menuAdditions`

## Package layout produced

```
manifest.json
assets/cover.<ext>
assets/menu/background.<ext>
assets/thumbnails/video_<id>.<ext>
videos/video_<id>.<ext>
client-buckets/<clientId>/client.json
client-buckets/<clientId>/<bucketFile>
client-buckets/<clientId>/per-video/<videoId>/<bucketFile>
client-buckets/<clientId>/<uploadDestination>/<file>
```

Folders only appear when the corresponding data was added. No wrapping
folder is inserted inside the archive.

## Client Extensions

Import a `client.json` produced by VideoThing's visual editor and fill in
the values it declares:

```swift
try creator.addClientExtension(definitionURL: clientJSON)
creator.setClientOptionCheckbox(id: "shuffle-on-open", value: true)
creator.setClientOptionText(id: "greeting", value: "hi")
creator.setClientOptionSelect(id: "theme", value: "dark")
creator.setCustomListItems(listID: "faq", items: [...])
creator.setPerVideoCustomListItems(videoID: videoID, listID: "chapters", items: [...])
try creator.addClientUpload(uploadID: "resource-pack", fileURL: someFile)
```

Client extensions describe data, not code. The kit packages the values into
the bucket paths declared by the extension. A conforming client app renders
its own UI from that data.

### Oyster example (third-party)

Oyster is a third-party VTISO client. The kit contains no Oyster-specific
behavior — see `Examples/OysterChaptersExample.swift`.

## Errors

`VTISOError` covers missing files, unreadable sources, invalid paths,
duplicate IDs / destinations, invalid hex colors, invalid client
definitions, missing required extension values, JSON encoding, temp dir,
ZIP creation, and output write failures.

## Tests

```
swift test
```

Runs the included XCTest suite covering minimal builds, layout coverage,
hex validation, path traversal rejection, and duplicate-ID rejection.

## Limitations

- Does not transcode video or generate thumbnails
- No CSS-gradient backgrounds (VideoThing does not export them)
- No physical VTISO disc format — offline `.vtiso` files only
- No DRM
