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

