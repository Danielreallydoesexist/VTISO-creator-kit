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

_ = try creator.build(to: destinationURL) // destinationURL must end in .vtiso
```

Notes:

- The output URL **must end in `.vtiso`** — `build(to:)` throws
  `VTISOError.invalidOutputExtension` otherwise; the extension is never
  appended silently. Destinations pointing at an existing directory are
  rejected; a missing parent directory is created automatically.
- `creator.background` is the builder's background input. The manifest's
  `menu.background` is *generated output*: it is overwritten from
  `creator.background` on every build (`.none` clears it). Set
  `creator.background`, not `creator.menu.background`.
- `creator.discId` is generated once when the creator is constructed and is
  reused for every build, so rebuilding the same creator produces the same
  disc identity. Assign a new value only to describe a different disc.
- If the destination file already exists it is replaced only after the new
  archive has been fully written (staged in a private temporary directory,
  then moved into place).

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

Extensions can also be constructed in code — all client-extension models
have public initializers with sensible defaults:

```swift
let spec = ClientExtensionSpec(
    clientId: "example-client",
    clientName: "Example Client"
)
// Declares one bucket at client-buckets/example-client/ unless explicit
// bucketDefinitions are supplied.
try creator.setClientExtension(spec)
```

Export-feature IDs (`fileUploads`, `customLists`, `checkboxes`,
`textFields`, `selectFields`, `menuAdditions`) must be non-empty and unique
across **all** categories, because multiple field types may write into the
same bucket file.

### Bucket paths

If the imported `client.json` contains a `bucketDefinitions` entry whose
`bucketId` equals the extension's `clientId`, that declared `path` (normalized
to end in `/`) is used for `client.json`, option files, custom-list files,
uploads, and per-video files — and the same path is written into the
manifest's `clientBuckets`. Only when no matching bucket definition exists
does the kit fall back to `client-buckets/<clientId>/`.

Bucket definitions are validated on import: empty client IDs, absolute
paths, `..` components, URL-like paths, duplicate bucket IDs, and duplicate
bucket paths are all rejected.

An imported `client.json` is written back into the package byte-for-byte,
so the packaged definition always matches what the visual editor produced.

### Validation performed by `build(to:)`

Before anything is written, the builder validates:

- non-empty `title` and creator display name, at least one video, unique
  video IDs, unique extra IDs, and `compatibility.minRuntime == "1.0"`
- every supplied client value refers to a field ID declared in
  `client.json` (`checkboxes`, `textFields`, `selectFields`, `customLists`,
  `fileUploads`) — unknown IDs throw
- per-video values must supply the ID of a video that exists on the
  creator; supplying a video ID for a shared field (or omitting it for a
  per-video field) throws
- required per-video fields are validated **per video**: every video must
  have a value (or a usable default)
- select values (explicit or default) must be one of the declared `options`
- text values must respect `maxLength`
- file uploads enforce `required`, `multiple`, `maxSizeBytes`, and
  `allowedTypes` using local file metadata only. `allowedTypes` entries may
  be extension-style (`.png`), exact MIME strings (`image/png`), or wildcard
  MIME groups (`image/*`); MIME types are detected from the file extension
  via a small built-in table — when the MIME type cannot be detected, only
  extension-style entries can allow the file
- custom lists enforce `required`, `minItems`, and `maxItems`, and every
  item is validated recursively against the list's `itemSchema`

Declared custom lists are always written, even when optional and empty —
an empty JSON array is produced so clients can rely on the declared
`bucketFile` existing.

### Supported item-schema primitives

Only these primitive schema names are supported: `string`, `string[]`,
`number`, `number[]`, `boolean`, `boolean[]`, `file`, `file[]` — plus nested
`{ "type": "object", "fields": { … } }` and `{ "type": "array", "items": … }`
schemas. Any other primitive name is rejected when the extension is set.

Limitation: `VTISOJSON` cannot carry binary data, so `file` / `file[]`
values are validated as package-relative path **strings** (the shape
VideoThing writes). The kit does not resolve or verify the referenced
files.

### Oyster example (third-party)

Oyster is a third-party VTISO client. The kit contains no Oyster-specific
behavior — see `Examples/OysterChaptersExample.swift`.

## Errors

`VTISOError` covers missing files, unreadable sources, invalid paths,
duplicate IDs / destinations, invalid hex colors, invalid output
extensions, invalid client definitions, unknown field or video IDs,
invalid or missing extension values, JSON encoding, temp dir, ZIP
creation, and output write failures.

`VTISOError` conforms to `LocalizedError`, so `error.localizedDescription`
(and SwiftUI alerts) show the real message instead of a generic
"the operation couldn't be completed".

Package-relative paths are strictly validated: absolute paths, Windows
drive paths (`C:/…`), backslashes, NUL characters, URL-like paths, empty
components, and `.` / `..` components are all rejected — never silently
normalized.

## Tests

```
swift test
```

Runs the included XCTest suite covering minimal builds, output-extension
rejection, stable disc IDs, declared/fallback bucket paths, unsafe bucket
path rejection, unknown field/video IDs, per-video vs. shared misuse,
select/text/upload/custom-list validation, recursive item-schema
validation, archive layout (manifest at root, no wrapping folder),
replacement of existing outputs, and temp-dir cleanup after failures.

## Limitations

- Does not transcode video or generate thumbnails
- No CSS-gradient backgrounds (VideoThing does not export them)
- No physical VTISO disc format — offline `.vtiso` files only
- No DRM
