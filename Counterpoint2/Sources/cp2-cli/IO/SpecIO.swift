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

func warnKeyframeTimesOutOfRange(spec: CP2Spec, warnHandler: (String) -> Void) {
    guard let strokes = spec.strokes else { return }

    func checkScalar(_ scalar: KeyframedScalar?, strokeId: String, param: String) {
        guard let scalar else { return }
        for keyframe in scalar.keyframes {
            if keyframe.t < 0.0 || keyframe.t > 1.0 {
                let message = String(
                    format: "KEYFRAME_T_OUT_OF_RANGE stroke=%@ param=%@ t=%.6f clamped=none",
                    strokeId,
                    param,
                    keyframe.t
                )
                warnHandler(message)
            }
        }
    }

    for stroke in strokes {
        let strokeId = stroke.id
        let params = stroke.params
        checkScalar(params?.theta, strokeId: strokeId, param: "theta")
        checkScalar(params?.width, strokeId: strokeId, param: "width")
        checkScalar(params?.widthLeft, strokeId: strokeId, param: "widthLeft")
        checkScalar(params?.widthRight, strokeId: strokeId, param: "widthRight")
        checkScalar(params?.offset, strokeId: strokeId, param: "offset")
        checkScalar(params?.alpha, strokeId: strokeId, param: "alpha")
    }
}
