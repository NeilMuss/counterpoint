import Foundation
import CP2Geometry
import CP2Skeleton

public struct CP2Spec: Codable {
    var example: String?
    var render: RenderSettings?
    var reference: ReferenceLayer?
    var ink: Ink?
    var strokes: [StrokeSpec]?
}

func loadSpec(path: String) -> CP2Spec? {
    let url = URL(fileURLWithPath: path)
    guard let data = try? Data(contentsOf: url) else {
        warn("spec file not found: \(path)")
        return nil
    }
    do {
        return try JSONDecoder().decode(CP2Spec.self, from: data)
    } catch {
        warn("spec decode failed: \(path)")
        return nil
    }
}

func writeSpec(_ spec: CP2Spec, path: String) {
    let url = URL(fileURLWithPath: path)
    print("writeSpec to: \(path)")
    if let data = try? JSONEncoder().encode(spec) {
        try? data.write(to: url)
    }
}

func warn(_ message: String) {
    FileHandle.standardError.write(Data("warning: \(message)\n".utf8))
}
