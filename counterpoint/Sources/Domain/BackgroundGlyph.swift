import Foundation

public enum BackgroundGlyphAlign: String, Codable {
    case center
    case none
}

public struct BackgroundGlyph: Codable, Equatable {
    public var svgPath: String
    public var opacity: Double
    public var zoom: Double
    public var fill: String
    public var stroke: String
    public var strokeWidth: Double
    public var align: BackgroundGlyphAlign
    public var transform: String?

    private enum CodingKeys: String, CodingKey {
        case svgPath
        case opacity
        case zoom
        case fill
        case stroke
        case strokeWidth
        case align
        case transform
    }

    public init(
        svgPath: String,
        opacity: Double = 0.25,
        zoom: Double = 100.0,
        fill: String = "#e0e0e0",
        stroke: String = "#4169e1",
        strokeWidth: Double = 1.0,
        align: BackgroundGlyphAlign = .center,
        transform: String? = nil
    ) {
        self.svgPath = svgPath
        self.opacity = opacity
        self.zoom = zoom
        self.fill = fill
        self.stroke = stroke
        self.strokeWidth = strokeWidth
        self.align = align
        self.transform = transform
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        svgPath = try container.decode(String.self, forKey: .svgPath)
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.25
        zoom = try container.decodeIfPresent(Double.self, forKey: .zoom) ?? 100.0
        fill = try container.decodeIfPresent(String.self, forKey: .fill) ?? "#e0e0e0"
        stroke = try container.decodeIfPresent(String.self, forKey: .stroke) ?? "#4169e1"
        strokeWidth = try container.decodeIfPresent(Double.self, forKey: .strokeWidth) ?? 1.0
        align = try container.decodeIfPresent(BackgroundGlyphAlign.self, forKey: .align) ?? .center
        transform = try container.decodeIfPresent(String.self, forKey: .transform)
    }
}
