import Foundation

// Mirrors the VideoThing VTISO 1.0 manifest exactly.
// Do not add fields here without a matching change in VideoThing's exporter.

public enum VTISOMenuLayout: String, Codable, CaseIterable, Sendable {
    case classicDisc     = "classic-disc"
    case grid            = "grid"
    case theater         = "theater"
    case episodeList     = "episode-list"
    case creatorShowcase = "creator-showcase"
    case minimalGlass    = "minimal-glass"
}

public enum VTISOButtonStyle: String, Codable, CaseIterable, Sendable {
    case pill, square, glass, outline
}

public enum VTISOAccentStyle: String, Codable, CaseIterable, Sendable {
    case fiery, neon, gold, sky, pink
}

public enum VTISOIntendedForm: String, Codable, Sendable {
    case web, tv, tablet, any
}

public struct VTISOCreatorInfo: Codable, Sendable {
    public var id: String?
    public var displayName: String
    public var channelUrl: String?
    public var avatar: String?

    public init(id: String? = nil, displayName: String, channelUrl: String? = nil, avatar: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.channelUrl = channelUrl
        self.avatar = avatar
    }
}

public struct VTISOMenu: Codable, Sendable {
    public var layout: VTISOMenuLayout
    public var background: String?          // hex color OR package-relative path
    public var buttonStyle: VTISOButtonStyle
    public var accent: VTISOAccentStyle
    public var cover: String?

    public init(layout: VTISOMenuLayout = .grid,
                background: String? = nil,
                buttonStyle: VTISOButtonStyle = .glass,
                accent: VTISOAccentStyle = .fiery,
                cover: String? = nil) {
        self.layout = layout
        self.background = background
        self.buttonStyle = buttonStyle
        self.accent = accent
        self.cover = cover
    }
}

public struct VTISOPlaylistOptions: Codable, Sendable {
    public var autoplay: Bool
    public var loop: Bool
    public var shuffle: Bool
    public init(autoplay: Bool = true, loop: Bool = false, shuffle: Bool = false) {
        self.autoplay = autoplay; self.loop = loop; self.shuffle = shuffle
    }
}

public struct VTISOVideoEntry: Codable, Sendable {
    public var id: String
    public var title: String
    public var description: String?
    public var sourceType: String       // always "local-file"
    public var source: String           // "videos/video_<id>.<ext>"
    public var thumbnail: String?
    public var durationSeconds: Double?
    public var tags: [String]?
}

public struct VTISOExtra: Codable, Sendable {
    public var id: String
    public var title: String
    public var body: String
    public init(id: String = UUID().uuidString.lowercased(), title: String, body: String) {
        self.id = id; self.title = title; self.body = body
    }
}

public struct VTISOPermissions: Codable, Sendable {
    public var allowDownload: Bool
    public var allowExport: Bool
    public init(allowDownload: Bool = true, allowExport: Bool = true) {
        self.allowDownload = allowDownload; self.allowExport = allowExport
    }
}

public struct VTISOCompatibility: Codable, Sendable {
    public var minRuntime: String       // "1.0"
    public var intendedForm: VTISOIntendedForm?
    public init(minRuntime: String = "1.0", intendedForm: VTISOIntendedForm? = .any) {
        self.minRuntime = minRuntime; self.intendedForm = intendedForm
    }
}

public struct VTISOClientBucketRef: Codable, Sendable {
    public var clientId: String
    public var path: String
    public var optionalForOtherClients: Bool
    public init(clientId: String, path: String, optionalForOtherClients: Bool = true) {
        self.clientId = clientId; self.path = path
        self.optionalForOtherClients = optionalForOtherClients
    }
}

public struct VTISOManifest: Codable, Sendable {
    public var vtisoVersion: String     // always "1.0"
    public var discId: String
    public var belongingClient: String?
    public var title: String
    public var subtitle: String?
    public var description: String?
    public var creator: VTISOCreatorInfo
    public var createdAt: String
    public var menu: VTISOMenu
    public var playlist: VTISOPlaylistOptions
    public var videos: [VTISOVideoEntry]
    public var extras: [VTISOExtra]?
    public var assets: [String]?
    public var permissions: VTISOPermissions?
    public var compatibility: VTISOCompatibility?
    public var clientBuckets: [VTISOClientBucketRef]?
}
