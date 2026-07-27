import Foundation

/// Untyped JSON value used for custom-list items and option values.
/// Mirrors the arbitrary JSON shape VideoThing writes into bucket files.
public indirect enum VTISOJSON: Codable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([VTISOJSON])
    case object([String: VTISOJSON])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([VTISOJSON].self) { self = .array(a); return }
        if let o = try? c.decode([String: VTISOJSON].self) { self = .object(o); return }
        self = .null
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:            try c.encodeNil()
        case .bool(let b):     try c.encode(b)
        case .number(let n):   try c.encode(n)
        case .string(let s):   try c.encode(s)
        case .array(let a):    try c.encode(a)
        case .object(let o):   try c.encode(o)
        }
    }
}

/// Convenience helpers.
public extension VTISOJSON {
    static func from(_ any: Any) -> VTISOJSON {
        switch any {
        case is NSNull:                       return .null
        case let b as Bool:                   return .bool(b)
        case let i as Int:                    return .number(Double(i))
        case let d as Double:                 return .number(d)
        case let s as String:                 return .string(s)
        case let a as [Any]:                  return .array(a.map(VTISOJSON.from))
        case let o as [String: Any]:
            var m: [String: VTISOJSON] = [:]
            for (k, v) in o { m[k] = .from(v) }
            return .object(m)
        default:                              return .null
        }
    }
}
