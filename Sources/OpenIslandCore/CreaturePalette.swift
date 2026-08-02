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
}

/// Species colours, chosen as a deliberate luminance ladder rather than a hue
/// wheel.
///
/// The reference style assumes a dark subject on a light ground; the pill
/// inverts that, so creatures are light masses read by silhouette and dark line
/// is used only *inside* the shape. Measured: the reference product's own cat
/// scores 6.39:1 on its light ground and 1.97:1 on this pill.
///
/// Values are spread across ~55 luminance points so species survive greyscale
/// and stay distinguishable for colour-blind users. Every entry clears 3:1
/// against the pill; `CreaturePaletteTests` enforces both properties.
public enum CreaturePalette {
    public static func color(for species: CreatureSpecies) -> CreatureColor {
        switch species {
        case .claude:   CreatureColor(red: 0xf8, green: 0xd7, blue: 0xb7) // L 72.0%  14.25:1
        case .codex:    CreatureColor(red: 0xb2, green: 0xcb, blue: 0xe8) // L 58.0%  11.67:1
        case .cursor:   CreatureColor(red: 0x7d, green: 0xc3, blue: 0xa2) // L 46.0%   9.44:1
        case .gemini:   CreatureColor(red: 0xaa, green: 0x99, blue: 0xbd) // L 35.0%   7.41:1
        case .kimi:     CreatureColor(red: 0xba, green: 0x74, blue: 0x92) // L 25.0%   5.56:1
        case .openCode: CreatureColor(red: 0x79, green: 0x71, blue: 0x53) // L 16.5%   3.98:1
        }
    }

    /// Interior line work. Never used to carry the silhouette edge — at 1.17:1
    /// against the pill it is invisible there.
    public static let lineWork = CreatureColor(red: 0x21, green: 0x1e, blue: 0x12)

    /// `V6Palette.ink`, duplicated here so Core can assert against it.
    public static let pillFill = CreatureColor(red: 0x0c, green: 0x0d, blue: 0x0f)
}
