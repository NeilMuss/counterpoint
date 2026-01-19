import Foundation

public struct CanvasSize: Equatable, Codable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct WorldRect: Equatable, Codable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
    public var min: Vec2 { Vec2(minX, minY) }
    public var max: Vec2 { Vec2(maxX, maxY) }

    public func padded(by padding: Double) -> WorldRect {
        WorldRect(
            minX: minX - padding,
            minY: minY - padding,
            maxX: maxX + padding,
            maxY: maxY + padding
        )
    }

    public func union(_ other: WorldRect) -> WorldRect {
        WorldRect(
            minX: Swift.min(minX, other.minX),
            minY: Swift.min(minY, other.minY),
            maxX: Swift.max(maxX, other.maxX),
            maxY: Swift.max(maxY, other.maxY)
        )
    }

    public static func fromAABB(_ box: AABB) -> WorldRect {
        WorldRect(minX: box.min.x, minY: box.min.y, maxX: box.max.x, maxY: box.max.y)
    }

    public func toAABB() -> AABB {
        AABB(min: Vec2(minX, minY), max: Vec2(maxX, maxY))
    }
}

public enum RenderFitMode: String, Codable {
    case glyph
    case glyphPlusReference
    case everything
    case none
}

public struct RenderSettings: Equatable, Codable {
    public var canvasPx: CanvasSize
    public var fitMode: RenderFitMode
    public var paddingWorld: Double
    public var clipToFrame: Bool
    public var worldFrame: WorldRect?

    public init(
        canvasPx: CanvasSize = CanvasSize(width: 1200, height: 1200),
        fitMode: RenderFitMode = .glyph,
        paddingWorld: Double = 30.0,
        clipToFrame: Bool = false,
        worldFrame: WorldRect? = nil
    ) {
        self.canvasPx = canvasPx
        self.fitMode = fitMode
        self.paddingWorld = paddingWorld
        self.clipToFrame = clipToFrame
        self.worldFrame = worldFrame
    }
}

public struct ReferenceLayer: Equatable, Codable {
    public var path: String
    public var translateWorld: Vec2
    public var scale: Double
    public var rotateDeg: Double
    public var opacity: Double
    public var lockPlacement: Bool

    public init(
        path: String,
        translateWorld: Vec2 = Vec2(0, 0),
        scale: Double = 1.0,
        rotateDeg: Double = 0.0,
        opacity: Double = 0.35,
        lockPlacement: Bool = true
    ) {
        self.path = path
        self.translateWorld = translateWorld
        self.scale = scale
        self.rotateDeg = rotateDeg
        self.opacity = opacity
        self.lockPlacement = lockPlacement
    }
}

public struct Transform2D: Equatable, Codable {
    public var a: Double
    public var b: Double
    public var c: Double
    public var d: Double
    public var tx: Double
    public var ty: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }
}

public func referenceTransformMatrix(_ layer: ReferenceLayer) -> Transform2D {
    let radians = layer.rotateDeg * Double.pi / 180.0
    let cosA = cos(radians)
    let sinA = sin(radians)
    return Transform2D(
        a: layer.scale * cosA,
        b: layer.scale * sinA,
        c: layer.scale * -sinA,
        d: layer.scale * cosA,
        tx: layer.translateWorld.x,
        ty: layer.translateWorld.y
    )
}

public func resolveWorldFrame(
    settings: RenderSettings,
    glyphBounds: AABB?,
    referenceBounds: AABB?,
    debugBounds: AABB?
) -> WorldRect {
    let fallback = WorldRect(minX: -1.0, minY: -1.0, maxX: 1.0, maxY: 1.0)
    let glyphRect = glyphBounds.map(WorldRect.fromAABB)
    let refRect = referenceBounds.map(WorldRect.fromAABB)
    let debugRect = debugBounds.map(WorldRect.fromAABB)

    let base: WorldRect = {
        switch settings.fitMode {
        case .none:
            if let worldFrame = settings.worldFrame {
                return worldFrame
            }
            return glyphRect ?? refRect ?? debugRect ?? fallback
        case .glyph:
            return glyphRect ?? settings.worldFrame ?? fallback
        case .glyphPlusReference:
            if let glyphRect, let refRect {
                return glyphRect.union(refRect)
            }
            return glyphRect ?? refRect ?? settings.worldFrame ?? fallback
        case .everything:
            var rect = glyphRect ?? refRect ?? debugRect ?? settings.worldFrame ?? fallback
            if let glyphRect {
                rect = rect.union(glyphRect)
            }
            if let refRect {
                rect = rect.union(refRect)
            }
            if let debugRect {
                rect = rect.union(debugRect)
            }
            return rect
        }
    }()

    return base.padded(by: settings.paddingWorld)
}
