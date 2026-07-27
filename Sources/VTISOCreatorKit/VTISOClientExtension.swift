import Foundation

// Mirrors VideoThing's ClientExtensionSpec (client.json) exactly.

public indirect enum CxItemSchemaFieldType: Codable, Sendable {
    case primitive(String)                                  // "string" | "string[]" | "number" | "number[]" | "boolean" | "boolean[]" | "file" | "file[]"
    case object(fields: [String: CxItemSchemaFieldType])
    case array(items: CxItemSchemaFieldType)

    private enum Keys: String, CodingKey { case type, fields, items }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let s = try? single.decode(String.self) {
            self = .primitive(s); return
        }
        let c = try decoder.container(keyedBy: Keys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "object":
            self = .object(fields: try c.decode([String: CxItemSchemaFieldType].self, forKey: .fields))
        case "array":
            self = .array(items: try c.decode(CxItemSchemaFieldType.self, forKey: .items))
        default:
            self = .primitive(type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .primitive(let s):
            var c = encoder.singleValueContainer(); try c.encode(s)
        case .object(let fields):
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode("object", forKey: .type)
            try c.encode(fields, forKey: .fields)
        case .array(let items):
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode("array", forKey: .type)
            try c.encode(items, forKey: .items)
        }
    }
}

public struct CxFileUploadField: Codable, Sendable {
    public var id: String
    public var label: String
    public var description: String?
    public var allowedTypes: [String]
    public var multiple: Bool
    public var required: Bool
    public var destination: String
    public var maxSizeBytes: Int?
    public var perVideo: Bool?

    public init(id: String,
                label: String,
                description: String? = nil,
                allowedTypes: [String] = [],
                multiple: Bool = false,
                required: Bool = false,
                destination: String,
                maxSizeBytes: Int? = nil,
                perVideo: Bool? = nil) {
        self.id = id
        self.label = label
        self.description = description
        self.allowedTypes = allowedTypes
        self.multiple = multiple
        self.required = required
        self.destination = destination
        self.maxSizeBytes = maxSizeBytes
        self.perVideo = perVideo
    }
}

public struct CxCustomListField: Codable, Sendable {
    public var id: String
    public var label: String
    public var description: String?
    public var required: Bool
    public var minItems: Int?
    public var maxItems: Int?
    public var bucketFile: String
    public var itemSchema: [String: CxItemSchemaFieldType]
    public var perVideo: Bool?

    public init(id: String,
                label: String,
                description: String? = nil,
                required: Bool = false,
                minItems: Int? = nil,
                maxItems: Int? = nil,
                bucketFile: String,
                itemSchema: [String: CxItemSchemaFieldType],
                perVideo: Bool? = nil) {
        self.id = id
        self.label = label
        self.description = description
        self.required = required
        self.minItems = minItems
        self.maxItems = maxItems
        self.bucketFile = bucketFile
        self.itemSchema = itemSchema
        self.perVideo = perVideo
    }
}

public struct CxCheckboxField: Codable, Sendable {
    public var id: String
    public var label: String
    public var description: String?
    public var defaultValue: Bool
    public var required: Bool
    public var bucketFile: String
    public var group: String?
    public var perVideo: Bool?

    public init(id: String,
                label: String,
                description: String? = nil,
                defaultValue: Bool = false,
                required: Bool = false,
                bucketFile: String,
                group: String? = nil,
                perVideo: Bool? = nil) {
        self.id = id
        self.label = label
        self.description = description
        self.defaultValue = defaultValue
        self.required = required
        self.bucketFile = bucketFile
        self.group = group
        self.perVideo = perVideo
    }
}

public struct CxTextField: Codable, Sendable {
    public var id: String
    public var label: String
    public var description: String?
    public var defaultValue: String?
    public var required: Bool
    public var maxLength: Int?
    public var bucketFile: String
    public var group: String?
    public var perVideo: Bool?

    public init(id: String,
                label: String,
                description: String? = nil,
                defaultValue: String? = nil,
                required: Bool = false,
                maxLength: Int? = nil,
                bucketFile: String,
                group: String? = nil,
                perVideo: Bool? = nil) {
        self.id = id
        self.label = label
        self.description = description
        self.defaultValue = defaultValue
        self.required = required
        self.maxLength = maxLength
        self.bucketFile = bucketFile
        self.group = group
        self.perVideo = perVideo
    }
}

public struct CxSelectField: Codable, Sendable {
    public var id: String
    public var label: String
    public var description: String?
    public var options: [String]
    public var defaultValue: String?
    public var required: Bool
    public var bucketFile: String
    public var group: String?
    public var perVideo: Bool?

    public init(id: String,
                label: String,
                description: String? = nil,
                options: [String],
                defaultValue: String? = nil,
                required: Bool = false,
                bucketFile: String,
                group: String? = nil,
                perVideo: Bool? = nil) {
        self.id = id
        self.label = label
        self.description = description
        self.options = options
        self.defaultValue = defaultValue
        self.required = required
        self.bucketFile = bucketFile
        self.group = group
        self.perVideo = perVideo
    }
}

public struct CxMenuAddition: Codable, Sendable {
    public var id: String
    public var label: String
    public var appearsInMenu: Bool
    public var requiresList: String?

    public init(id: String,
                label: String,
                appearsInMenu: Bool = true,
                requiresList: String? = nil) {
        self.id = id
        self.label = label
        self.appearsInMenu = appearsInMenu
        self.requiresList = requiresList
    }
}

public struct CxExportFeatures: Codable, Sendable {
    public var fileUploads: [CxFileUploadField]
    public var customLists: [CxCustomListField]
    public var checkboxes: [CxCheckboxField]
    public var textFields: [CxTextField]
    public var selectFields: [CxSelectField]
    public var menuAdditions: [CxMenuAddition]

    public init(fileUploads: [CxFileUploadField] = [],
                customLists: [CxCustomListField] = [],
                checkboxes: [CxCheckboxField] = [],
                textFields: [CxTextField] = [],
                selectFields: [CxSelectField] = [],
                menuAdditions: [CxMenuAddition] = []) {
        self.fileUploads = fileUploads
        self.customLists = customLists
        self.checkboxes = checkboxes
        self.textFields = textFields
        self.selectFields = selectFields
        self.menuAdditions = menuAdditions
    }
}

public struct CxBucketDefinition: Codable, Sendable {
    public var bucketId: String
    public var path: String
    public init(bucketId: String, path: String) { self.bucketId = bucketId; self.path = path }
}

public struct ClientExtensionSpec: Codable, Sendable {
    public var clientId: String
    public var clientName: String
    public var description: String?
    public var extensionVersion: String
    public var minimumRuntimeVersion: String
    public var authorName: String?
    public var websiteUrl: String?
    public var supportedPlatforms: [String]
    public var exportFeatures: CxExportFeatures
    public var bucketDefinitions: [CxBucketDefinition]

    /// Creates a spec in code. When `bucketDefinitions` is not supplied, a
    /// single default bucket `client-buckets/<clientId>/` (with `bucketId`
    /// equal to `clientId`) is declared; passing an explicit array — even an
    /// empty one — uses exactly what was passed.
    public init(clientId: String,
                clientName: String,
                description: String? = nil,
                extensionVersion: String = "1.0",
                minimumRuntimeVersion: String = "1.0",
                authorName: String? = nil,
                websiteUrl: String? = nil,
                supportedPlatforms: [String] = [],
                exportFeatures: CxExportFeatures = CxExportFeatures(),
                bucketDefinitions: [CxBucketDefinition]? = nil) {
        self.clientId = clientId
        self.clientName = clientName
        self.description = description
        self.extensionVersion = extensionVersion
        self.minimumRuntimeVersion = minimumRuntimeVersion
        self.authorName = authorName
        self.websiteUrl = websiteUrl
        self.supportedPlatforms = supportedPlatforms
        self.exportFeatures = exportFeatures
        self.bucketDefinitions = bucketDefinitions
            ?? [CxBucketDefinition(bucketId: clientId, path: "client-buckets/\(clientId)/")]
    }
}
