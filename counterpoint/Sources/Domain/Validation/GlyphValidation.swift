import Foundation

public struct GlyphValidationError: Codable, Equatable {
    public let path: String
    public let code: String
    public let message: String

    public init(path: String, code: String, message: String) {
        self.path = path
        self.code = code
        self.message = message
    }
}

public struct GlyphValidationFailure: Error, LocalizedError {
    public let errors: [GlyphValidationError]

    public init(errors: [GlyphValidationError]) {
        self.errors = errors
    }

    public var errorDescription: String? {
        errors.map { "\($0.path): [\($0.code)] \($0.message)" }.joined(separator: "\n")
    }
}

public struct GlyphDocumentValidator {
    public init() {}

    public func validate(_ document: GlyphDocument) throws {
        var errors: [GlyphValidationError] = []

        if document.schema != GlyphDocument.schemaId {
            errors.append(GlyphValidationError(
                path: "schema",
                code: "schema_mismatch",
                message: "Expected schema '\(GlyphDocument.schemaId)'."
            ))
        }

        validateFrame(document.frame, errors: &errors)
        validateEngine(document.engine, errors: &errors)
        validateGlyphInfo(document.glyph, errors: &errors)
        validateGeometry(document.inputs.geometry, errors: &errors)
        validateDerived(document.derived, errors: &errors)
        validateConstraints(document.inputs.constraints, errors: &errors)
        validateOperations(document.inputs.operations, geometry: document.inputs.geometry, errors: &errors)

        if !errors.isEmpty {
            throw GlyphValidationFailure(errors: errors)
        }
    }

    private func validateFrame(_ frame: GlyphFrame, errors: inout [GlyphValidationError]) {
        if !frame.origin.isFinite {
            errors.append(GlyphValidationError(path: "frame.origin", code: "non_finite", message: "Origin must be finite."))
        }
        if let size = frame.size {
            if !size.isFinite || size.width <= 0 || size.height <= 0 {
                errors.append(GlyphValidationError(path: "frame.size", code: "invalid_size", message: "Size must be positive and finite."))
            }
        }
        if let advanceWidth = frame.advanceWidth {
            if !advanceWidth.isFinite || advanceWidth < 0 {
                errors.append(GlyphValidationError(path: "frame.advanceWidth", code: "invalid_advance", message: "Advance width must be non-negative and finite."))
            }
        }
        if let leftSidebearing = frame.leftSidebearing, !leftSidebearing.isFinite {
            errors.append(GlyphValidationError(path: "frame.leftSidebearing", code: "non_finite", message: "Left sidebearing must be finite."))
        }
        if let rightSidebearing = frame.rightSidebearing, !rightSidebearing.isFinite {
            errors.append(GlyphValidationError(path: "frame.rightSidebearing", code: "non_finite", message: "Right sidebearing must be finite."))
        }
        if let baselineY = frame.baselineY, !baselineY.isFinite {
            errors.append(GlyphValidationError(path: "frame.baselineY", code: "non_finite", message: "Baseline must be finite."))
        }
        if let guides = frame.guides {
            if let capHeightY = guides.capHeightY, !capHeightY.isFinite {
                errors.append(GlyphValidationError(path: "frame.guides.capHeightY", code: "non_finite", message: "Guide values must be finite."))
            }
            if let descenderY = guides.descenderY, !descenderY.isFinite {
                errors.append(GlyphValidationError(path: "frame.guides.descenderY", code: "non_finite", message: "Guide values must be finite."))
            }
        }
    }

    private func validateEngine(_ engine: GlyphEngine?, errors: inout [GlyphValidationError]) {
        guard let engine else { return }
        if engine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(GlyphValidationError(path: "engine.name", code: "empty_value", message: "Engine name must be non-empty."))
        }
        if engine.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(GlyphValidationError(path: "engine.version", code: "empty_value", message: "Engine version must be non-empty."))
        }
        if let ordering = engine.determinism?.stableOrdering, ordering.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(GlyphValidationError(path: "engine.determinism.stableOrdering", code: "empty_value", message: "stableOrdering must be non-empty if provided."))
        }
    }

    private func validateGlyphInfo(_ glyph: GlyphInfo?, errors: inout [GlyphValidationError]) {
        guard let glyph else { return }
        if glyph.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(GlyphValidationError(path: "glyph.id", code: "empty_id", message: "Glyph id must be non-empty."))
        }
    }

    private func validateGeometry(_ geometry: GlyphGeometryInputs, errors: inout [GlyphValidationError]) {
        var seen: Set<String> = []

        func checkId(_ id: String, path: String) {
            if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(GlyphValidationError(path: path, code: "empty_id", message: "ID must be non-empty."))
                return
            }
            if seen.contains(id) {
                errors.append(GlyphValidationError(path: path, code: "duplicate_id", message: "Duplicate ID '\(id)'."))
            } else {
                seen.insert(id)
            }
        }

        for (index, path) in geometry.paths.enumerated() {
            checkId(path.id, path: "inputs.geometry.paths[\(index)].id")
            if path.type != "path" {
                errors.append(GlyphValidationError(path: "inputs.geometry.paths[\(index)].type", code: "invalid_type", message: "Path type must be 'path'."))
            }
            validateSegments(path.segments, pathPrefix: "inputs.geometry.paths[\(index)].segments", errors: &errors)
        }
        for (index, stroke) in geometry.strokes.enumerated() {
            checkId(stroke.id, path: "inputs.geometry.strokes[\(index)].id")
            if stroke.type != "stroke" {
                errors.append(GlyphValidationError(path: "inputs.geometry.strokes[\(index)].type", code: "invalid_type", message: "Stroke type must be 'stroke'."))
            }
            if stroke.skeletons.isEmpty {
                errors.append(GlyphValidationError(path: "inputs.geometry.strokes[\(index)].skeletons", code: "empty_ref", message: "skeletons must contain at least one path id."))
            }
            for (sIndex, skeleton) in stroke.skeletons.enumerated() {
                if skeleton.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errors.append(GlyphValidationError(path: "inputs.geometry.strokes[\(index)].skeletons[\(sIndex)]", code: "empty_ref", message: "skeleton id must be non-empty."))
                }
            }
            validateCurve(stroke.params.width, path: "inputs.geometry.strokes[\(index)].params.width", errors: &errors)
            if let widthLeft = stroke.params.widthLeft {
                validateCurve(widthLeft, path: "inputs.geometry.strokes[\(index)].params.widthLeft", errors: &errors)
            }
            if let widthRight = stroke.params.widthRight {
                validateCurve(widthRight, path: "inputs.geometry.strokes[\(index)].params.widthRight", errors: &errors)
            }
            validateCurve(stroke.params.height, path: "inputs.geometry.strokes[\(index)].params.height", errors: &errors)
            validateCurve(stroke.params.theta, path: "inputs.geometry.strokes[\(index)].params.theta", errors: &errors)
            if let offset = stroke.params.offset {
                validateCurve(offset, path: "inputs.geometry.strokes[\(index)].params.offset", errors: &errors)
            }
            if let alpha = stroke.params.alpha {
                validateCurve(alpha, path: "inputs.geometry.strokes[\(index)].params.alpha", errors: &errors)
            }
        }
        for (index, whitespace) in geometry.whitespace.enumerated() {
            switch whitespace {
            case .path(let path):
                checkId(path.id, path: "inputs.geometry.whitespace[\(index)].id")
                if path.type != "path" && path.type != "whitespace" {
                    errors.append(GlyphValidationError(path: "inputs.geometry.whitespace[\(index)].type", code: "invalid_type", message: "Whitespace type must be 'path' or 'whitespace'."))
                }
                validateSegments(path.segments, pathPrefix: "inputs.geometry.whitespace[\(index)].segments", errors: &errors)
            case .stroke:
                errors.append(GlyphValidationError(path: "inputs.geometry.whitespace[\(index)].type", code: "invalid_type", message: "Whitespace entries must be paths."))
            case .unknown(let type):
                errors.append(GlyphValidationError(path: "inputs.geometry.whitespace[\(index)].type", code: "unknown_geometry_type", message: "Unsupported geometry type '\(type)'."))
            }
        }

        let pathIds = Set(geometry.paths.map { $0.id })
        for (index, stroke) in geometry.strokes.enumerated() {
            for (sIndex, skeleton) in stroke.skeletons.enumerated() {
                if !pathIds.contains(skeleton) {
                    errors.append(GlyphValidationError(
                        path: "inputs.geometry.strokes[\(index)].skeletons[\(sIndex)]",
                        code: "missing_reference",
                        message: "skeleton '\(skeleton)' does not match any path ID."
                    ))
                }
            }
        }
    }

    private func validateDerived(_ derived: GlyphDerived?, errors: inout [GlyphValidationError]) {
        guard let reference = derived?.reference else { return }
        if reference.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(GlyphValidationError(path: "derived.reference.id", code: "empty_id", message: "Reference id must be non-empty."))
        }
        if reference.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(GlyphValidationError(path: "derived.reference.source", code: "empty_source", message: "Reference source must be non-empty."))
        }
        if let scale = reference.transform?.scale, (!scale.isFinite || scale <= 0) {
            errors.append(GlyphValidationError(path: "derived.reference.transform.scale", code: "invalid_scale", message: "Scale must be positive and finite."))
        }
        if let translate = reference.transform?.translate, !translate.isFinite {
            errors.append(GlyphValidationError(path: "derived.reference.transform.translate", code: "non_finite", message: "Translate must be finite."))
        }
    }

    private func validateSegments(_ segments: [GlyphSegment], pathPrefix: String, errors: inout [GlyphValidationError]) {
        if segments.isEmpty {
            errors.append(GlyphValidationError(path: pathPrefix, code: "empty_segments", message: "At least one segment is required."))
            return
        }
        for (index, segment) in segments.enumerated() {
            switch segment {
            case .cubic(let cubic):
                if !cubic.p0.isFinite || !cubic.p1.isFinite || !cubic.p2.isFinite || !cubic.p3.isFinite {
                    errors.append(GlyphValidationError(
                        path: "\(pathPrefix)[\(index)]",
                        code: "non_finite",
                        message: "Segment control points must be finite."
                    ))
                }
            case .unknown(let type):
                errors.append(GlyphValidationError(
                    path: "\(pathPrefix)[\(index)].type",
                    code: "unknown_segment_type",
                    message: "Unsupported segment type '\(type)'."
                ))
            }
        }
    }

    private func validateCurve(_ curve: ParamCurve, path: String, errors: inout [GlyphValidationError]) {
        if curve.keyframes.isEmpty {
            errors.append(GlyphValidationError(path: "\(path).keyframes", code: "empty_keyframes", message: "At least one keyframe is required."))
            return
        }
        var lastT: Double?
        for (index, keyframe) in curve.keyframes.enumerated() {
            if !keyframe.t.isFinite || !keyframe.value.isFinite {
                errors.append(GlyphValidationError(path: "\(path).keyframes[\(index)]", code: "non_finite", message: "Keyframe values must be finite."))
                continue
            }
            if keyframe.t < 0.0 || keyframe.t > 1.0 {
                errors.append(GlyphValidationError(path: "\(path).keyframes[\(index)].t", code: "t_out_of_range", message: "t must be within [0,1]."))
            }
            if let lastT, keyframe.t < lastT {
                errors.append(GlyphValidationError(path: "\(path).keyframes[\(index)].t", code: "non_monotonic_t", message: "Keyframes must be nondecreasing in t."))
            }
            lastT = keyframe.t
        }
    }

    private func validateConstraints(_ constraints: [GlyphConstraint], errors: inout [GlyphValidationError]) {
        for (index, constraint) in constraints.enumerated() {
            switch constraint {
            case .lockToFrame(let lock):
                if lock.targetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errors.append(GlyphValidationError(path: "inputs.constraints[\(index)].targetId", code: "empty_ref", message: "targetId must be non-empty."))
                }
            case .unknown(let type):
                errors.append(GlyphValidationError(path: "inputs.constraints[\(index)].type", code: "unknown_constraint_type", message: "Unsupported constraint type '\(type)'."))
            }
        }
    }

    private func validateOperations(_ operations: [GlyphOperation], geometry: GlyphGeometryInputs, errors: inout [GlyphValidationError]) {
        let pathIds = Set(geometry.paths.map { $0.id })
        for (index, operation) in operations.enumerated() {
            switch operation {
            case .editPathPoint(let op):
                if !pathIds.contains(op.pathId) {
                    errors.append(GlyphValidationError(path: "inputs.operations[\(index)].pathId", code: "missing_reference", message: "pathId '\(op.pathId)' does not match any path ID."))
                }
                if op.segmentIndex < 0 {
                    errors.append(GlyphValidationError(path: "inputs.operations[\(index)].segmentIndex", code: "invalid_index", message: "segmentIndex must be non-negative."))
                }
                if !op.value.isFinite {
                    errors.append(GlyphValidationError(path: "inputs.operations[\(index)].value", code: "non_finite", message: "Point values must be finite."))
                }
            case .setSidebearing(let op):
                if !op.value.isFinite {
                    errors.append(GlyphValidationError(path: "inputs.operations[\(index)].value", code: "non_finite", message: "Sidebearing value must be finite."))
                }
            case .translateGlyph(let op):
                if !op.delta.isFinite {
                    errors.append(GlyphValidationError(path: "inputs.operations[\(index)].delta", code: "non_finite", message: "Delta must be finite."))
                }
            case .unknown(let type):
                errors.append(GlyphValidationError(path: "inputs.operations[\(index)].type", code: "unknown_operation_type", message: "Unsupported operation type '\(type)'."))
            }
        }
    }
}

private extension Point {
    var isFinite: Bool {
        x.isFinite && y.isFinite
    }
}

private extension GlyphSize {
    var isFinite: Bool {
        width.isFinite && height.isFinite
    }
}
