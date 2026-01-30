import Foundation
import CP2Geometry
import CP2Skeleton

public struct CP2Spec: Codable {
    var example: String?
    var render: RenderSettings?
    var reference: ReferenceLayer?
    var ink: Ink?
    var counters: CounterSet? = nil
    var strokes: [StrokeSpec]?
}

enum SpecIOError: Error, CustomStringConvertible {
    case readFailed(path: String, underlying: Error)
    case decodeFailed(path: String, underlying: Error)

    var description: String {
        switch self {
        case .readFailed(let path, let underlying):
            return "spec read failed: \(path)\n\(underlying)"
        case .decodeFailed(let path, let underlying):
            return "spec decode failed: \(path)\n\(underlying)"
        }
    }
}

func loadSpecOrThrow(path: String) throws -> CP2Spec {
    do {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(CP2Spec.self, from: data)
        } catch {
            throw SpecIOError.decodeFailed(path: path, underlying: error)
        }
    } catch {
        throw SpecIOError.readFailed(path: path, underlying: error)
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
