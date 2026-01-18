import XCTest
@testable import Domain

final class GlyphDocumentV0Tests: XCTestCase {
    func testLoadsMinimalValidDocument() throws {
        let data = try loadFixture(named: "glyph_v0_min.json")
        let doc = try GlyphDocument.load(from: data)
        XCTAssertEqual(doc.schema, GlyphDocument.schemaId)
        XCTAssertEqual(doc.inputs.geometry.paths.count, 1)
        XCTAssertEqual(doc.inputs.geometry.strokes.count, 1)
    }

    func testDecodesTangentPhaseDegrees() throws {
        let json = """
        {
          "schema": "\(GlyphDocument.schemaId)",
          "frame": {
            "origin": {"x": 0, "y": 0},
            "size": {"width": 600, "height": 700},
            "advanceWidth": 600,
            "leftSidebearing": 50,
            "rightSidebearing": 50
          },
          "inputs": {
            "geometry": {
              "paths": [
                {
                  "id": "path-stem",
                  "type": "path",
                  "segments": [
                    {
                      "type": "cubic",
                      "p0": {"x": 0, "y": 0},
                      "p1": {"x": 0, "y": 0},
                      "p2": {"x": 0, "y": 100},
                      "p3": {"x": 0, "y": 100}
                    }
                  ]
                }
              ],
              "strokes": [
                {
                  "id": "stroke-main",
                  "type": "stroke",
                  "skeletons": ["path-stem"],
                  "params": {
                    "angleMode": "tangentRelative",
                    "tangentPhaseDegrees": 90,
                    "width": {"keyframes": [{"t": 0, "value": 10}]},
                    "height": {"keyframes": [{"t": 0, "value": 6}]},
                    "theta": {"keyframes": [{"t": 0, "value": 0}]}
                  }
                }
              ],
              "whitespace": []
            }
          }
        }
        """
        let data = Data(json.utf8)
        let doc = try GlyphDocument.load(from: data)
        let stroke = try XCTUnwrap(doc.inputs.geometry.strokes.first)
        XCTAssertEqual(stroke.params.tangentPhaseDegrees ?? 0.0, 90.0, accuracy: 1.0e-6)
    }

    func testRejectsDuplicateIds() throws {
        let json = """
        {
          "schema": "\(GlyphDocument.schemaId)",
          "frame": {
            "origin": {"x": 0, "y": 0},
            "size": {"width": 600, "height": 700},
            "advanceWidth": 600,
            "leftSidebearing": 50,
            "rightSidebearing": 50
          },
          "inputs": {
            "geometry": {
              "paths": [
                {
                  "id": "dup",
                  "type": "path",
                  "segments": [
                    {
                      "type": "cubic",
                      "p0": {"x": 0, "y": 0},
                      "p1": {"x": 0, "y": 50},
                      "p2": {"x": 0, "y": 100},
                      "p3": {"x": 0, "y": 150}
                    }
                  ]
                }
              ],
              "strokes": [
                {
                  "id": "dup",
                  "type": "stroke",
                  "skeletons": ["dup"],
                  "params": {
                    "angleMode": "absolute",
                    "width": {"keyframes": [{"t": 0, "value": 10}]},
                    "height": {"keyframes": [{"t": 0, "value": 20}]},
                    "theta": {"keyframes": [{"t": 0, "value": 0}]}
                  }
                }
              ],
              "whitespace": []
            }
          }
        }
        """
        let error = try XCTUnwrap(assertValidationFailure(json))
        XCTAssertTrue(error.errors.contains { $0.code == "duplicate_id" })
    }

    func testRejectsMissingSkeletonPathRef() throws {
        let json = """
        {
          "schema": "\(GlyphDocument.schemaId)",
          "frame": {
            "origin": {"x": 0, "y": 0},
            "size": {"width": 600, "height": 700},
            "advanceWidth": 600,
            "leftSidebearing": 50,
            "rightSidebearing": 50
          },
          "inputs": {
            "geometry": {
              "paths": [],
              "strokes": [
                {
                  "id": "stroke-main",
                  "type": "stroke",
                  "skeletons": ["missing"],
                  "params": {
                    "angleMode": "absolute",
                    "width": {"keyframes": [{"t": 0, "value": 10}]},
                    "height": {"keyframes": [{"t": 0, "value": 20}]},
                    "theta": {"keyframes": [{"t": 0, "value": 0}]}
                  }
                }
              ],
              "whitespace": []
            }
          }
        }
        """
        let error = try XCTUnwrap(assertValidationFailure(json))
        XCTAssertTrue(error.errors.contains { $0.code == "missing_reference" })
    }

    func testRejectsNonMonotonicKeyframes() throws {
        let json = """
        {
          "schema": "\(GlyphDocument.schemaId)",
          "frame": {
            "origin": {"x": 0, "y": 0},
            "size": {"width": 600, "height": 700},
            "advanceWidth": 600,
            "leftSidebearing": 50,
            "rightSidebearing": 50
          },
          "inputs": {
            "geometry": {
              "paths": [
                {
                  "id": "path-stem",
                  "type": "path",
                  "segments": [
                    {
                      "type": "cubic",
                      "p0": {"x": 0, "y": 0},
                      "p1": {"x": 0, "y": 50},
                      "p2": {"x": 0, "y": 100},
                      "p3": {"x": 0, "y": 150}
                    }
                  ]
                }
              ],
              "strokes": [
                {
                  "id": "stroke-main",
                  "type": "stroke",
                  "skeletons": ["path-stem"],
                  "params": {
                    "angleMode": "absolute",
                    "width": {"keyframes": [{"t": 0.5, "value": 10}, {"t": 0.2, "value": 12}]},
                    "height": {"keyframes": [{"t": 0, "value": 20}]},
                    "theta": {"keyframes": [{"t": 0, "value": 0}]}
                  }
                }
              ],
              "whitespace": []
            }
          }
        }
        """
        let error = try XCTUnwrap(assertValidationFailure(json))
        XCTAssertTrue(error.errors.contains { $0.code == "non_monotonic_t" })
    }

    func testAcceptsDerivedCache() throws {
        let json = """
        {
          "schema": "\(GlyphDocument.schemaId)",
          "frame": {
            "origin": {"x": 0, "y": 0},
            "size": {"width": 600, "height": 700},
            "advanceWidth": 600,
            "leftSidebearing": 50,
            "rightSidebearing": 50
          },
          "inputs": {
            "geometry": {
              "paths": [
                {
                  "id": "path-stem",
                  "type": "path",
                  "segments": [
                    {
                      "type": "cubic",
                      "p0": {"x": 0, "y": 0},
                      "p1": {"x": 0, "y": 50},
                      "p2": {"x": 0, "y": 100},
                      "p3": {"x": 0, "y": 150}
                    }
                  ]
                }
              ],
              "strokes": [
                {
                  "id": "stroke-main",
                  "type": "stroke",
                  "skeletons": ["path-stem"],
                  "params": {
                    "angleMode": "absolute",
                    "width": {"keyframes": [{"t": 0, "value": 10}]},
                    "height": {"keyframes": [{"t": 0, "value": 20}]},
                    "theta": {"keyframes": [{"t": 0, "value": 0}]}
                  }
                }
              ],
              "whitespace": []
            }
          },
          "derived": {
            "note": "cached outline",
            "samples": [1, 2, 3]
          }
        }
        """
        let data = Data(json.utf8)
        let doc = try GlyphDocument.load(from: data)
        XCTAssertNotNil(doc.derived)
        XCTAssertEqual(doc.derived?.extra["note"], .string("cached outline"))
    }

    func testAcceptsEmptyGeometry() throws {
        let json = """
        {
          "schema": "\(GlyphDocument.schemaId)",
          "frame": {
            "origin": {"x": 0, "y": 0},
            "size": {"width": 600, "height": 700},
            "advanceWidth": 600,
            "leftSidebearing": 50,
            "rightSidebearing": 50
          },
          "inputs": {
            "geometry": {}
          }
        }
        """
        let data = Data(json.utf8)
        let doc = try GlyphDocument.load(from: data)
        XCTAssertTrue(doc.inputs.geometry.paths.isEmpty)
        XCTAssertTrue(doc.inputs.geometry.strokes.isEmpty)
        XCTAssertTrue(doc.inputs.geometry.whitespace.isEmpty)
    }

    func testLoadsUserGlyphFile() throws {
        let data = try loadFixture(named: "glyph_v0_min.json")
        let doc = try GlyphDocument.load(from: data)
        XCTAssertEqual(doc.schema, GlyphDocument.schemaId)
    }

    private func assertValidationFailure(_ json: String) -> GlyphValidationFailure? {
        do {
            _ = try GlyphDocument.load(from: Data(json.utf8))
            return nil
        } catch let error as GlyphValidationFailure {
            return error
        } catch {
            XCTFail("Unexpected error: \(error)")
            return nil
        }
    }

    private func loadFixture(named name: String) throws -> Data {
        let fileURL = URL(fileURLWithPath: #file)
        var dir = fileURL.deletingLastPathComponent()
        while dir.path != "/" {
            let testCandidate = dir.appendingPathComponent("Tests/Fixtures/\(name)")
            if FileManager.default.fileExists(atPath: testCandidate.path) {
                return try Data(contentsOf: testCandidate)
            }
            let candidate = dir.appendingPathComponent("Fixtures/\(name)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try Data(contentsOf: candidate)
            }
            dir = dir.deletingLastPathComponent()
        }
        throw NSError(domain: "GlyphDocumentV0Tests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture not found: \(name)"])
    }

}
