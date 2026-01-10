import Foundation

public struct GlyphDocument: Codable, Equatable {
    public static let schemaId = "font-design-app/glyph@v0"

    public var schema: String
    public var engine: GlyphEngine?
    public var glyph: GlyphInfo?
    public var frame: GlyphFrame
    public var inputs: GlyphInputs
    public var derived: GlyphDerived?

    public init(schema: String, engine: GlyphEngine? = nil, glyph: GlyphInfo? = nil, frame: GlyphFrame, inputs: GlyphInputs, derived: GlyphDerived? = nil) {
        self.schema = schema
        self.engine = engine
        self.glyph = glyph
        self.frame = frame
        self.inputs = inputs
        self.derived = derived
    }

    public static func load(from data: Data) throws -> GlyphDocument {
        let decoder = JSONDecoder()
        let document = try decoder.decode(GlyphDocument.self, from: data)
        try GlyphDocumentValidator().validate(document)
        return document
    }
}

public struct GlyphFrame: Codable, Equatable {
    public var origin: Point
    public var size: GlyphSize?
    public var baselineY: Double?
    public var advanceWidth: Double?
    public var leftSidebearing: Double?
    public var rightSidebearing: Double?
    public var guides: GlyphGuides?

    public init(
        origin: Point,
        size: GlyphSize? = nil,
        baselineY: Double? = nil,
        advanceWidth: Double? = nil,
        leftSidebearing: Double? = nil,
        rightSidebearing: Double? = nil,
        guides: GlyphGuides? = nil
    ) {
        self.origin = origin
        self.size = size
        self.baselineY = baselineY
        self.advanceWidth = advanceWidth
        self.leftSidebearing = leftSidebearing
        self.rightSidebearing = rightSidebearing
        self.guides = guides
    }

    private enum CodingKeys: String, CodingKey {
        case origin
        case size
        case baselineY
        case advanceWidth
        case leftSidebearing
        case rightSidebearing
        case sidebearings
        case guides
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        origin = try container.decode(Point.self, forKey: .origin)
        size = try container.decodeIfPresent(GlyphSize.self, forKey: .size)
        baselineY = try container.decodeIfPresent(Double.self, forKey: .baselineY)
        advanceWidth = try container.decodeIfPresent(Double.self, forKey: .advanceWidth)
        guides = try container.decodeIfPresent(GlyphGuides.self, forKey: .guides)

        if let sidebearings = try container.decodeIfPresent(GlyphSidebearings.self, forKey: .sidebearings) {
            leftSidebearing = sidebearings.left
            rightSidebearing = sidebearings.right
        } else {
            leftSidebearing = try container.decodeIfPresent(Double.self, forKey: .leftSidebearing)
            rightSidebearing = try container.decodeIfPresent(Double.self, forKey: .rightSidebearing)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(origin, forKey: .origin)
        try container.encodeIfPresent(size, forKey: .size)
        try container.encodeIfPresent(baselineY, forKey: .baselineY)
        try container.encodeIfPresent(advanceWidth, forKey: .advanceWidth)
        try container.encodeIfPresent(guides, forKey: .guides)
        if let leftSidebearing, let rightSidebearing {
            try container.encode(GlyphSidebearings(left: leftSidebearing, right: rightSidebearing), forKey: .sidebearings)
        } else {
            try container.encodeIfPresent(leftSidebearing, forKey: .leftSidebearing)
            try container.encodeIfPresent(rightSidebearing, forKey: .rightSidebearing)
        }
    }
}

public struct GlyphSize: Codable, Equatable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct GlyphInputs: Codable, Equatable {
    public var geometry: GlyphGeometryInputs
    public var constraints: [GlyphConstraint]
    public var operations: [GlyphOperation]

    public init(geometry: GlyphGeometryInputs, constraints: [GlyphConstraint] = [], operations: [GlyphOperation] = []) {
        self.geometry = geometry
        self.constraints = constraints
        self.operations = operations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        geometry = try container.decode(GlyphGeometryInputs.self, forKey: .geometry)
        constraints = try container.decodeIfPresent([GlyphConstraint].self, forKey: .constraints) ?? []
        operations = try container.decodeIfPresent([GlyphOperation].self, forKey: .operations) ?? []
    }
}

public struct GlyphGeometryInputs: Codable, Equatable {
    public var ink: [GlyphGeometryItem]
    public var whitespace: [GlyphGeometryItem]

    public var paths: [PathGeometry] {
        ink.compactMap { item in
            if case .path(let path) = item { return path }
            return nil
        }
    }

    public var strokes: [StrokeGeometry] {
        ink.compactMap { item in
            if case .stroke(let stroke) = item { return stroke }
            return nil
        }
    }

    public init(ink: [GlyphGeometryItem] = [], whitespace: [GlyphGeometryItem] = []) {
        self.ink = ink
        self.whitespace = whitespace
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let ink = try container.decodeIfPresent([GlyphGeometryItem].self, forKey: .ink) {
            self.ink = ink
        } else {
            let paths = try container.decodeIfPresent([PathGeometry].self, forKey: .paths) ?? []
            let strokes = try container.decodeIfPresent([StrokeGeometry].self, forKey: .strokes) ?? []
            self.ink = paths.map { .path($0) } + strokes.map { .stroke($0) }
        }
        whitespace = try container.decodeIfPresent([GlyphGeometryItem].self, forKey: .whitespace) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ink, forKey: .ink)
        try container.encode(whitespace, forKey: .whitespace)
    }

    private enum CodingKeys: String, CodingKey {
        case ink
        case whitespace
        case paths
        case strokes
    }
}

public struct GlyphDerived: Codable, Equatable {
    public var reference: GlyphReference?
    public var extra: [String: JSONValue]

    public init(reference: GlyphReference? = nil, extra: [String: JSONValue] = [:]) {
        self.reference = reference
        self.extra = extra
    }

    private enum CodingKeys: String, CodingKey {
        case reference
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reference = try container.decodeIfPresent(GlyphReference.self, forKey: .reference)
        let raw = try JSONValue(from: decoder)
        if case .object(let object) = raw {
            var extras = object
            extras.removeValue(forKey: "reference")
            extra = extras
        } else {
            extra = [:]
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(reference, forKey: .reference)
        if !extra.isEmpty {
            let encoded = JSONValue.object(extra)
            try encoded.encode(to: encoder)
        }
    }
}

public struct GlyphReference: Codable, Equatable {
    public var id: String
    public var source: String
    public var transform: GlyphReferenceTransform?

    public init(id: String, source: String, transform: GlyphReferenceTransform? = nil) {
        self.id = id
        self.source = source
        self.transform = transform
    }
}

public struct GlyphReferenceTransform: Codable, Equatable {
    public var scale: Double?
    public var translate: Point?

    public init(scale: Double? = nil, translate: Point? = nil) {
        self.scale = scale
        self.translate = translate
    }
}

public enum GlyphGeometryItem: Codable, Equatable {
    case path(PathGeometry)
    case stroke(StrokeGeometry)
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try? container.decode(String.self, forKey: .type)) ?? "unknown"
        switch type {
        case "path":
            self = .path(try PathGeometry(from: decoder))
        case "stroke":
            self = .stroke(try StrokeGeometry(from: decoder))
        default:
            self = .unknown(type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .path(let path):
            try path.encode(to: encoder)
        case .stroke(let stroke):
            try stroke.encode(to: encoder)
        case .unknown(let type):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
        }
    }
}

public struct PathGeometry: Codable, Equatable {
    public var id: String
    public var type: String
    public var segments: [GlyphSegment]

    public init(id: String, type: String = "path", segments: [GlyphSegment]) {
        self.id = id
        self.type = type
        self.segments = segments
    }
}

public enum GlyphSegment: Codable, Equatable {
    case cubic(CubicBezier)
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case p0
        case p1
        case p2
        case p3
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try? container.decode(String.self, forKey: .type)) ?? "unknown"
        switch type {
        case "cubic":
            let p0 = try container.decode(Point.self, forKey: .p0)
            let p1 = try container.decode(Point.self, forKey: .p1)
            let p2 = try container.decode(Point.self, forKey: .p2)
            let p3 = try container.decode(Point.self, forKey: .p3)
            self = .cubic(CubicBezier(p0: p0, p1: p1, p2: p2, p3: p3))
        default:
            self = .unknown(type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .cubic(let cubic):
            try container.encode("cubic", forKey: .type)
            try container.encode(cubic.p0, forKey: .p0)
            try container.encode(cubic.p1, forKey: .p1)
            try container.encode(cubic.p2, forKey: .p2)
            try container.encode(cubic.p3, forKey: .p3)
        case .unknown(let type):
            try container.encode(type, forKey: .type)
        }
    }
}

public struct StrokeGeometry: Codable, Equatable {
    public var id: String
    public var type: String
    public var skeletons: [String]
    public var params: StrokeParams
    public var samplingPolicy: SamplingPolicy?
    public var joins: StrokeJoins?

    public init(
        id: String,
        type: String = "stroke",
        skeletons: [String],
        params: StrokeParams,
        samplingPolicy: SamplingPolicy? = nil,
        joins: StrokeJoins? = nil
    ) {
        self.id = id
        self.type = type
        self.skeletons = skeletons
        self.params = params
        self.samplingPolicy = samplingPolicy
        self.joins = joins
    }
}

public struct StrokeParams: Codable, Equatable {
    public var angleMode: AngleMode?
    public var width: ParamCurve
    public var height: ParamCurve
    public var theta: ParamCurve
    public var offset: ParamCurve?
    public var alpha: ParamCurve?

    public init(
        angleMode: AngleMode? = nil,
        width: ParamCurve,
        height: ParamCurve,
        theta: ParamCurve,
        offset: ParamCurve? = nil,
        alpha: ParamCurve? = nil
    ) {
        self.angleMode = angleMode
        self.width = width
        self.height = height
        self.theta = theta
        self.offset = offset
        self.alpha = alpha
    }
}

public struct StrokeJoins: Codable, Equatable {
    public var capStyle: CapStyle?
    public var joinStyle: JoinStyle?

    public init(capStyle: CapStyle? = nil, joinStyle: JoinStyle? = nil) {
        self.capStyle = capStyle
        self.joinStyle = joinStyle
    }
}

public struct ParamCurve: Codable, Equatable {
    public var keyframes: [ParamKeyframe]

    public init(keyframes: [ParamKeyframe]) {
        self.keyframes = keyframes
    }
}

public struct ParamKeyframe: Codable, Equatable {
    public var t: Double
    public var value: Double
    public var interpolationToNext: Interpolation?

    public init(t: Double, value: Double, interpolationToNext: Interpolation? = nil) {
        self.t = t
        self.value = value
        self.interpolationToNext = interpolationToNext
    }
}

public enum GlyphConstraint: Codable, Equatable {
    case lockToFrame(LockToFrameConstraint)
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try? container.decode(String.self, forKey: .type)) ?? "unknown"
        switch type {
        case "lockToFrame":
            self = .lockToFrame(try LockToFrameConstraint(from: decoder))
        default:
            self = .unknown(type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .lockToFrame(let constraint):
            try constraint.encode(to: encoder)
        case .unknown(let type):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
        }
    }
}

public struct LockToFrameConstraint: Codable, Equatable {
    public var type: String
    public var targetId: String

    public init(type: String = "lockToFrame", targetId: String) {
        self.type = type
        self.targetId = targetId
    }
}

public enum GlyphOperation: Codable, Equatable {
    case editPathPoint(EditPathPointOperation)
    case setSidebearing(SetSidebearingOperation)
    case translateGlyph(TranslateGlyphOperation)
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try? container.decode(String.self, forKey: .type)) ?? "unknown"
        switch type {
        case "editPathPoint":
            self = .editPathPoint(try EditPathPointOperation(from: decoder))
        case "setSidebearing":
            self = .setSidebearing(try SetSidebearingOperation(from: decoder))
        case "translateGlyph":
            self = .translateGlyph(try TranslateGlyphOperation(from: decoder))
        default:
            self = .unknown(type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .editPathPoint(let op):
            try op.encode(to: encoder)
        case .setSidebearing(let op):
            try op.encode(to: encoder)
        case .translateGlyph(let op):
            try op.encode(to: encoder)
        case .unknown(let type):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
        }
    }
}

public struct EditPathPointOperation: Codable, Equatable {
    public var type: String
    public var pathId: String
    public var segmentIndex: Int
    public var point: PathPointID
    public var value: Point

    public init(type: String = "editPathPoint", pathId: String, segmentIndex: Int, point: PathPointID, value: Point) {
        self.type = type
        self.pathId = pathId
        self.segmentIndex = segmentIndex
        self.point = point
        self.value = value
    }
}

public enum PathPointID: String, Codable, Equatable {
    case p0
    case p1
    case p2
    case p3
}

public struct SetSidebearingOperation: Codable, Equatable {
    public var type: String
    public var side: SidebearingSide
    public var value: Double

    public init(type: String = "setSidebearing", side: SidebearingSide, value: Double) {
        self.type = type
        self.side = side
        self.value = value
    }
}

public enum SidebearingSide: String, Codable, Equatable {
    case left
    case right
}

public struct TranslateGlyphOperation: Codable, Equatable {
    public var type: String
    public var delta: Point

    public init(type: String = "translateGlyph", delta: Point) {
        self.type = type
        self.delta = delta
    }
}

public struct GlyphEngine: Codable, Equatable {
    public var name: String
    public var version: String
    public var determinism: GlyphDeterminism?

    public init(name: String, version: String, determinism: GlyphDeterminism? = nil) {
        self.name = name
        self.version = version
        self.determinism = determinism
    }
}

public struct GlyphDeterminism: Codable, Equatable {
    public var seed: Int?
    public var stableOrdering: String?

    public init(seed: Int? = nil, stableOrdering: String? = nil) {
        self.seed = seed
        self.stableOrdering = stableOrdering
    }
}

public struct GlyphInfo: Codable, Equatable {
    public var id: String
    public var unicode: String?
    public var tags: [String]?

    public init(id: String, unicode: String? = nil, tags: [String]? = nil) {
        self.id = id
        self.unicode = unicode
        self.tags = tags
    }
}

public struct GlyphSidebearings: Codable, Equatable {
    public var left: Double
    public var right: Double

    public init(left: Double, right: Double) {
        self.left = left
        self.right = right
    }
}

public struct GlyphGuides: Codable, Equatable {
    public var capHeightY: Double?
    public var descenderY: Double?

    public init(capHeightY: Double? = nil, descenderY: Double? = nil) {
        self.capHeightY = capHeightY
        self.descenderY = descenderY
    }
}
