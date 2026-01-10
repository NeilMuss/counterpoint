# Font Design App — Vision & Constraints

## Purpose

This project is an experimental font design application built around a single core idea:

> **Letterforms are systems of relationships, not collections of outlines.**

The goal is to design glyphs by defining proportions, paths, strokes, and whitespace symbolically, so that form emerges as a consequence of intention rather than manual adjustment.

This is not a general-purpose font editor.
It is a principled environment for constructing typefaces as coherent systems.

---

## Core Design Principles

### 1. Minimal Interface, Maximum Attention

- ~95% of screen space is devoted to glyphs or empty space
- No permanent toolbars
- No modes
- No inspector panels by default

The interface must get out of the way and allow sustained focus on form and relationships.

UI elements appear only when explicitly invoked or contextually necessary.

---

### 2. Multiple Live Views (“Boards”)

The application supports an unlimited number of floating canvas boards.

Each board is a *view* of the same underlying glyph system and may:
- show different glyph subsets
- arrange glyphs differently (single glyph, comparison, word)
- appear at different scales
- coexist simultaneously

Example boards:
- A large construction view of a single glyph
- A comparison of round letters
- A live word like `hamburger` for spacing and rhythm

Boards never duplicate data. They are always live views of the same model.

---

### 3. Glyphs Are Constructed, Not Drawn

A glyph is defined as an arrangement of:

- **Proportions** (symbolic measurements)
- **Paths** (skeleton Bézier paths)
- **Strokes** (swept shapes applied to paths)
- **Whitespace** (counters, apertures, margins)

Outlines are generated artifacts.
They are never edited directly.

---

### 4. Symbolic Measurement System (Strict DAG)

All measurements are symbolic and form a **strict directed acyclic graph (DAG)**.

Examples:
- `xHeight`
- `stemWidth = xHeight * 0.12`
- `twoThirdsX = xHeight * 2/3`

Rules:
- No cyclic dependencies
- Symbols may reference other symbols only
- Geometry may reference symbols
- Nothing references outlines

Changing one symbol must deterministically cascade through the system.

---

### 5. Overrides Are Named and Intentional

All deviations from inherited structure must be expressed as **named overrides**.

Overrides:
- modify path control points or stroke behavior
- are symbolic (reference measurements, not fixed numbers)
- are ordered and inspectable
- may be reused across glyphs

There are no anonymous tweaks.

If a curve looks different, the system must be able to explain *why*.

---

### 6. Whitespace Is First-Class

Whitespace is treated as a real design object.

Examples:
- counters
- apertures
- sidebearings
- clearance / keep-out regions

Whitespace is represented as editable closed shapes (“SpaceShapes”) that:
- can be inherited and overridden
- can be measured
- produce symbolic values (e.g. counter width)

Black geometry may depend on measurements derived from whitespace.
Whitespace does not react to black geometry (no feedback loops).

---

### 7. Stroke-Based, Skeleton-First Model

The system is grounded in a stroke-based view of type, influenced by calligraphic theory.

Workflow:
1. Skeleton paths define structure
2. Stroke definitions define expansion, angle, and behavior
3. Outlines are generated from stroke sweeps

Strokes may vary along a path via symbolic modulation (e.g. alpha functions).
Stroke behavior is separated from path geometry.

---

### 8. Explicit Evaluation Order

Glyph resolution follows a strict pipeline:

1. Resolve base symbol DAG
2. Resolve whitespace shapes (with overrides)
3. Compute whitespace-derived measurements
4. Resolve black skeleton paths (with overrides)
5. Apply stroke sweep
6. Generate outlines (read-only)

Nothing breaks this order.
No stage feeds backward.

---

### 9. Inspectability Over Convenience

The system must support answering the question:

> “Why does this look the way it does?”

At any point, a user should be able to:
- select a feature
- inspect which symbols affect it
- see which overrides contributed
- understand the dependency chain

This is more important than speed or familiarity.

---

### 10. Fixed Frame Principle

In the Font Design App, every glyph is edited within a stable reference frame.

The reference frame defines *where* a glyph exists.
Geometry defines *what* the glyph is.

Geometry edits never alter the reference frame.
Repositioning and metrics changes are always explicit actions.

This separation is enforced structurally in the data model.

- The `frame` is immutable during geometry edits.
- The `geometry` is evaluated entirely in frame-local coordinates.
- Derived outlines never feed back into frame values.

If an operation moves a glyph, it must say so.

## One-Way Evaluation Principle

All rendering and measurement is downstream-only.
Derived results (bounds, extrema, unions, fitted outlines) never modify inputs.
If something changes the glyph’s position or metrics, it must be an explicit frame edit.

## Deterministic Core Principle

The core engine is pure and deterministic.
The same inputs produce identical outputs (including ordering), enabling caching, diffs, and goldens.

## First-Class Whitespace Principle

Whitespace (counters and negative shapes) is a first-class editable object.
Designers can author and constrain negative space directly, and ink can be derived around it.


---

## GLYPH JSON v0

```
{
  "schema": "font-design-app/glyph@v0",
  "engine": {
    "name": "counterpoint-core",
    "version": "0.1.0",
    "determinism": {
      "seed": 0,
      "stableOrdering": "byIdThenIndex"
    }
  },

  "glyph": {
    "id": "J",
    "unicode": "U+004A",
    "tags": ["uppercase", "roman"]
  },

  "frame": {
    "origin": { "x": 0, "y": 0 },
    "baselineY": 0,
    "advanceWidth": 620,
    "sidebearings": { "left": 40, "right": 30 },

    "guides": {
      "capHeightY": 700,
      "xHeightY": 480,
      "ascenderY": 730,
      "descenderY": -200,
      "overshoot": { "roundTop": 12, "roundBottom": 12 }
    }
  },

  "inputs": {
    "geometry": {
      "ink": [
        {
          "id": "ink:spine",
          "type": "path",
          "closed": false,
          "segments": [
            { "type": "cubic", "p0": {"x": 120, "y": 680}, "p1": {"x": 210, "y": 700}, "p2": {"x": 260, "y": 540}, "p3": {"x": 210, "y": 380} }
          ]
        },
        {
          "id": "ink:hook",
          "type": "stroke",
          "skeletonPathRef": "ink:spine",
          "counterpoint": { "type": "rect" },
          "params": {
            "angleMode": "absolute",
            "theta": { "keyframes": [{ "t": 0, "value": 10 }, { "t": 1, "value": 75 }] },
            "width": { "keyframes": [{ "t": 0, "value": 18 }, { "t": 1, "value": 18 }] },
            "height": { "keyframes": [{ "t": 0, "value": 6 }, { "t": 1, "value": 30 }] },
            "offset": { "keyframes": [{ "t": 0, "value": 0 }, { "t": 1, "value": 0 }] }
          },
          "sampling": {
            "quality": "preview",
            "policy": {
              "flattenTolerance": 1.5,
              "envelopeTolerance": 1.0,
              "maxSamples": 80,
              "maxRecursionDepth": 7,
              "minParamStep": 0.01
            }
          },
          "joins": { "capStyle": "round", "joinStyle": { "type": "miter", "miterLimit": 4.0 } }
        }
      ],

      "whitespace": [
        {
          "id": "ws:counter:main",
          "type": "path",
          "closed": true,
          "role": "counter",
          "segments": [
            { "type": "cubic", "p0": {"x": 210, "y": 430}, "p1": {"x": 260, "y": 470}, "p2": {"x": 330, "y": 420}, "p3": {"x": 290, "y": 360} },
            { "type": "cubic", "p0": {"x": 290, "y": 360}, "p1": {"x": 250, "y": 300}, "p2": {"x": 180, "y": 330}, "p3": {"x": 210, "y": 430} }
          ]
        }
      ]
    },

    "constraints": [
      {
        "id": "c:ws-lock",
        "type": "lockToFrame",
        "targetRef": "ws:counter:main",
        "frameAnchor": "baselineY"
      }
    ]
  },

  "operations": [
    {
      "id": "op0001",
      "type": "editPathPoint",
      "targetRef": "ink:spine",
      "segmentIndex": 0,
      "point": "p2",
      "newValue": { "x": 255, "y": 545 }
    },
    {
      "id": "op0002",
      "type": "setSidebearing",
      "side": "left",
      "value": 40
    }
  ],

  "derived": {
    "note": "Derived fields are cacheable outputs. They never modify inputs.",
    "metrics": {
      "bounds": { "minX": 38, "minY": -192, "maxX": 590, "maxY": 712 },
      "inkBounds": { "minX": 38, "minY": -192, "maxX": 590, "maxY": 712 },
      "whitespaceBounds": { "minX": 190, "minY": 330, "maxX": 335, "maxY": 470 }
    },
    "outlines": {
      "inkRings": [
        {
          "id": "ring:ink:0",
          "winding": "ccw",
          "points": [ { "x": 0, "y": 0 } ]
        }
      ],
      "whitespaceRings": [
        {
          "id": "ring:ws:0",
          "winding": "cw",
          "points": [ { "x": 0, "y": 0 } ]
        }
      ],
      "finalRings": [
        {
          "id": "ring:final:0",
          "winding": "ccw",
          "points": [ { "x": 0, "y": 0 } ]
        }
      ],
      "outlineFit": {
        "mode": "none",
        "tolerance": 0.0
      }
    }
  }
}
```

**Contract**
- `frame` is only changed by explicit frame/metrics operations (e.g. setSidebearing, setAdvanceWidth, translateGlyph).
- Everything under `derived` is disposable cache: it may be regenerated at any time and never alters `inputs`.

---

## Non-Goals (Explicit)

This project intentionally does NOT prioritize:

- direct outline editing
- quick sketching workflows
- beginner accessibility
- feature completeness
- production export pipelines (initially)

Those can come later if they do not compromise the core model.

---

## Intended Audience

This tool is for designers who:
- think in systems
- care about consistency across families
- already design rules manually
- value clarity over immediacy

It is not intended to replace existing font editors for all users.

---

## Project Status

This repository contains an early, focused prototype.

The initial goal is to fully support a minimal set of glyphs (e.g. `o` and `n`) end-to-end within this model, proving the approach before expanding scope.

---

## Guiding Question

When making implementation decisions, prefer the option that best answers:

> “Does this make typographic intent more explicit?”

If not, it probably does not belong here.

