import Foundation

enum ShowcaseSubcommand {
    case scurve
    case line
}

struct ShowcasePreset {
    let name: String
    let description: String
    let subcommand: ShowcaseSubcommand
    let args: [String]
}

enum ShowcasePresets {
    static let all: [ShowcasePreset] = [
        ShowcasePreset(
            name: "scurve_broadnib",
            description: "Baseline broad-nib sweep (constant size/aspect).",
            subcommand: .scurve,
            args: ["--view", "envelope,centerline", "--envelope-mode", "union", "--size-start", "16", "--size-end", "16", "--aspect-start", "0.8", "--aspect-end", "0.8", "--angle-start", "20", "--angle-end", "20"]
        ),
        ShowcasePreset(
            name: "scurve_hairline_sail_final",
            description: "Hairline → sail (dramatic ramp, final quality).",
            subcommand: .scurve,
            args: ["--view", "envelope", "--envelope-mode", "union", "--quality", "final", "--size-start", "2", "--size-end", "26", "--aspect-start", "0.35", "--aspect-end", "0.35", "--angle-start", "10", "--angle-end", "75"]
        ),
        ShowcasePreset(
            name: "scurve_hairline_sail_early",
            description: "Hairline → sail, swelling earlier (alpha reduced).",
            subcommand: .scurve,
            args: ["--view", "envelope", "--envelope-mode", "union", "--alpha-start", "-0.4", "--alpha-end", "0.2", "--size-start", "2", "--size-end", "26", "--aspect-start", "0.35", "--aspect-end", "0.35", "--angle-start", "10", "--angle-end", "75"]
        ),
        ShowcasePreset(
            name: "scurve_absolute",
            description: "Absolute angle mode comparison.",
            subcommand: .scurve,
            args: ["--view", "envelope,rays", "--envelope-mode", "union", "--angle-mode", "absolute", "--angle-start", "10", "--angle-end", "75"]
        ),
        ShowcasePreset(
            name: "scurve_relative",
            description: "Tangent-relative angle mode comparison.",
            subcommand: .scurve,
            args: ["--view", "envelope,rays", "--envelope-mode", "union", "--angle-mode", "relative", "--angle-start", "10", "--angle-end", "75"]
        ),
        ShowcasePreset(
            name: "scurve_sharp_brush",
            description: "Sharp-ish brush (low aspect).",
            subcommand: .scurve,
            args: ["--view", "envelope", "--envelope-mode", "union", "--size-start", "14", "--size-end", "14", "--aspect-start", "0.2", "--aspect-end", "0.2", "--angle-start", "25", "--angle-end", "25"]
        ),
        ShowcasePreset(
            name: "scurve_flat_brush",
            description: "Flat brush (high aspect).",
            subcommand: .scurve,
            args: ["--view", "envelope", "--envelope-mode", "union", "--size-start", "14", "--size-end", "14", "--aspect-start", "1.8", "--aspect-end", "1.8", "--angle-start", "25", "--angle-end", "25"]
        ),
        ShowcasePreset(
            name: "scurve_debug_bundle",
            description: "Debug bundle (envelope + samples + rays + rails + centerline).",
            subcommand: .scurve,
            args: ["--view", "envelope,samples,rays,rails,centerline", "--envelope-mode", "union", "--angle-start", "10", "--angle-end", "75"]
        ),
        ShowcasePreset(
            name: "line_trumpet_neutral",
            description: "Straight-line trumpet (neutral alpha).",
            subcommand: .line,
            args: ["--view", "envelope,centerline", "--envelope-mode", "union", "--size-start", "5", "--size-end", "50", "--aspect-start", "0.35", "--aspect-end", "0.35", "--angle-start", "30", "--angle-end", "30", "--alpha-start", "0.0", "--alpha-end", "0.0"]
        ),
        ShowcasePreset(
            name: "line_trumpet_pos",
            description: "Straight-line trumpet (positive end bias).",
            subcommand: .line,
            args: ["--view", "envelope,centerline", "--envelope-mode", "union", "--size-start", "5", "--size-end", "50", "--aspect-start", "0.35", "--aspect-end", "0.35", "--angle-start", "30", "--angle-end", "30", "--alpha-end", "0.9"]
        ),
        ShowcasePreset(
            name: "line_trumpet_neg",
            description: "Straight-line trumpet (negative start bias).",
            subcommand: .line,
            args: ["--view", "envelope,centerline", "--envelope-mode", "union", "--size-start", "5", "--size-end", "50", "--aspect-start", "0.35", "--aspect-end", "0.35", "--angle-start", "30", "--angle-end", "30", "--alpha-start", "-0.9"]
        )
    ]
}
