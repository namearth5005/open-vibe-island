import Foundation

/// Raw sRGB colour. Core deliberately has no SwiftUI dependency — the app layer
/// converts, and the offscreen render harness links Core without pulling in UI.
public struct CreatureColor: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// WCAG 2.1 relative luminance.
    public var relativeLuminance: Double {
        func channel(_ raw: UInt8) -> Double {
            let c = Double(raw) / 255.0
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG 2.1 contrast ratio, 1.0...21.0.
    public static func contrastRatio(_ a: CreatureColor, _ b: CreatureColor) -> Double {
        let la = a.relativeLuminance
        let lb = b.relativeLuminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// The same colour at a different brightness.
    ///
    /// Scales all three channels in *linear* light by one factor, so
    /// chromaticity is untouched and only value moves. Doing this in sRGB space
    /// instead would drag the hue toward whichever channel was largest.
    public func scaledToLuminance(_ target: Double) -> CreatureColor {
        let current = relativeLuminance
        guard current > 0, target > 0 else { return CreatureColor(red: 0, green: 0, blue: 0) }
        let factor = target / current

        func rescale(_ raw: UInt8) -> UInt8 {
            let value = Double(raw) / 255.0
            let linear = value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            let scaled = min(1.0, max(0.0, linear * factor))
            let encoded = scaled <= 0.0031308 ? 12.92 * scaled : 1.055 * pow(scaled, 1.0 / 2.4) - 0.055
            return UInt8(max(0, min(255, (encoded * 255).rounded())))
        }
        return CreatureColor(red: rescale(red), green: rescale(green), blue: rescale(blue))
    }
}

/// Species colours, chosen as a deliberate luminance ladder rather than a hue
/// wheel.
///
/// The reference style assumes a dark subject on a light ground; the pill
/// inverts that, so creatures are light masses read by silhouette and dark line
/// is used only *inside* the shape. The measurements behind that inversion are
/// in `docs/superpowers/specs/2026-08-01-island-reward-mechanics-design.md`.
///
/// Values are spread across ~55 luminance points so species survive greyscale
/// and stay distinguishable for colour-blind users. Every entry clears 3:1
/// against the pill; `CreaturePaletteTests` enforces both properties.
public enum CreaturePalette {
    public static func color(for species: CreatureSpecies) -> CreatureColor {
        switch species {
        case .claude:   CreatureColor(red: 0xf8, green: 0xd7, blue: 0xb7) // L 72.0%  14.23:1
        case .codex:    CreatureColor(red: 0xb2, green: 0xcb, blue: 0xe8) // L 58.0%  11.65:1
        case .cursor:   CreatureColor(red: 0x7d, green: 0xc3, blue: 0xa2) // L 46.0%   9.43:1
        case .gemini:   CreatureColor(red: 0xaa, green: 0x99, blue: 0xbd) // L 35.0%   7.40:1
        case .kimi:     CreatureColor(red: 0xba, green: 0x74, blue: 0x92) // L 25.0%   5.55:1
        case .openCode: CreatureColor(red: 0x79, green: 0x71, blue: 0x53) // L 16.5%   3.98:1
        }
    }

    /// Interior line work. Never used to carry the silhouette edge — at 1.16:1
    /// against the pill it is invisible there.
    public static let lineWork = CreatureColor(red: 0x21, green: 0x1e, blue: 0x12)

    /// Mirrors `V6Palette.ink` (`V6ClosedPillShape.swift`), duplicated here so
    /// Core can assert against the surface creatures are drawn on without
    /// depending on the app target.
    ///
    /// Nothing in Core can catch these two diverging — a Core test only sees
    /// this copy, so pinning it to a literal stays green while the original
    /// moves. `CreaturePillFillTests` in the app target is the real guard: it
    /// is the only place both constants are in scope together.
    public static let pillFill = CreatureColor(red: 0x0d, green: 0x0d, blue: 0x0f)

    /// The opened panel's foreground wash — the ground panel creatures stand on.
    ///
    /// At L 63.1% this is very nearly the inverse of the pill, which is the
    /// whole reason `panelColor(for:)` exists.
    public static let panelGround = CreatureColor(red: 0xb4, green: 0xde, blue: 0x6f)

    /// Species value for the panel surface.
    ///
    /// The pill ladder cannot be reused here. Clearing 3:1 against a ground at
    /// L 63.1% requires L <= 17.7%, and five of the six pill values sit above
    /// that — measured, they land between 1.08:1 and 2.27:1 on the panel, which
    /// is invisible. There is no single ground that serves the pill ladder and
    /// the panel both; the only one that would is itself near-black.
    ///
    /// So the ladder is restated rather than reused: the same order, the same
    /// hues, compressed into a dark band the panel can actually show. Rank is
    /// preserved so a species stays recognisable across the two surfaces, and
    /// scaling happens in linear light so only value moves.
    ///
    /// Identity works differently on each surface as a result — value carries it
    /// on the pill, where there are no pixels for anything else; silhouette and
    /// hue carry it on the panel, where there are. See `docs/STYLE-SPEC.md` §3.3.
    public static func panelColor(for species: CreatureSpecies) -> CreatureColor {
        let luminances = CreatureSpecies.allCases.map { color(for: $0).relativeLuminance }
        guard let darkest = luminances.min(), let lightest = luminances.max(), lightest > darkest else {
            return color(for: species).scaledToLuminance(panelLuminanceFloor)
        }
        let position = (color(for: species).relativeLuminance - darkest) / (lightest - darkest)
        let target = panelLuminanceFloor + position * (panelLuminanceCeiling - panelLuminanceFloor)
        return color(for: species).scaledToLuminance(target)
    }

    /// Bounds of the panel band. The ceiling is held below the 17.7% that 3:1
    /// against `panelGround` allows, so 8-bit rounding cannot push the lightest
    /// species under the bar.
    static let panelLuminanceFloor = 0.03
    static let panelLuminanceCeiling = 0.14
}
