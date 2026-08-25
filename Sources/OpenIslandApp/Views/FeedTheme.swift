import SwiftUI
import OpenIslandCore

/// A colour the feed can measure.
///
/// The feed's contrast bars are enforced by tests rather than written in
/// comments, and that needs a colour type that knows its own luminance.
/// `SwiftUI.Color` does not expose components portably, so the feed's palette
/// is authored in this type and converted to `Color` at the point of use.
///
/// Pure and outside the view on purpose: a MainActor-isolated helper called
/// from a plain test crashes the runner with signal 5.
struct FeedInk: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255.0,
            green: Double((hex >> 8) & 0xff) / 255.0,
            blue: Double(hex & 0xff) / 255.0
        )
    }

    var color: Color { Color(red: red, green: green, blue: blue) }

    /// Flattens `foreground` at `alpha` onto `ground`, so contrast is measured
    /// on the colour that actually reaches the screen.
    static func blend(_ foreground: FeedInk, over ground: FeedInk, alpha: Double) -> FeedInk {
        FeedInk(
            red: foreground.red * alpha + ground.red * (1 - alpha),
            green: foreground.green * alpha + ground.green * (1 - alpha),
            blue: foreground.blue * alpha + ground.blue * (1 - alpha)
        )
    }

    /// WCAG 2.x relative luminance, sRGB.
    var luminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    func contrast(against other: FeedInk) -> Double {
        let a = luminance
        let b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// The feed's resolved colour, one value per skin.
///
/// Replaces the old `FeedPalette` statics. `IslandDesignPalette` is deliberately
/// NOT modified -- it is used across the whole app, and paper-ground tints are
/// a feed concern.
struct FeedTheme: Equatable, Sendable {
    /// The panel's own background.
    let ground: FeedInk
    /// Inner reading card. `nil` when the ground IS the reading surface.
    let surface: FeedInk?
    /// Text tiers for the reading surface -- the card body on Cream card,
    /// the panel itself on the other two.
    let text: FeedInk
    let dim: FeedInk
    let faint: FeedInk
    let hairline: FeedInk

    /// Text tiers for the chrome: the header and the footer, which sit on
    /// `ground` even when the body has a card of its own.
    ///
    /// Separate tokens rather than a rule each call site has to remember.
    /// Cream card is the only skin whose two grounds differ, and drawing its
    /// chrome in the card's own ink measured 1.16:1 on the panel -- ink on
    /// ink. Which ground a colour is legible against is a property of the
    /// colour, so it belongs to the token, not to the view. On the two skins
    /// where the ground IS the reading surface these are the same values as
    /// `text`/`dim`/`faint`.
    let chromeText: FeedInk
    let chromeDim: FeedInk
    let chromeFaint: FeedInk

    let approval: FeedInk
    let answer: FeedInk
    let running: FeedInk
    let completed: FeedInk

    /// Status colour for text sitting on the reading surface.
    func ink(for phase: SessionPhase) -> FeedInk {
        switch phase {
        case .waitingForApproval: approval
        case .waitingForAnswer: answer
        case .running: running
        case .completed: completed
        }
    }

    /// Status colour for the chrome, which sits on `ground` even when the body
    /// has its own surface. On Cream card those are different colours, so the
    /// chrome keeps the ink tints while the body uses the paper ones.
    func chromeInk(for phase: SessionPhase) -> FeedInk {
        surface == nil ? ink(for: phase) : Self.inkTints.ink(for: phase)
    }

    func color(for phase: SessionPhase) -> Color { ink(for: phase).color }
    func chromeColor(for phase: SessionPhase) -> Color { chromeInk(for: phase).color }

    // MARK: Resolution

    // Grounds. Ink is warmed from #0d0d0f so it reads as paper rather than
    // glass; that costs about 3% contrast and everything still clears (§7.5).
    private static let inkGround = FeedInk(hex: 0x12_11_0f)
    private static let creamGround = FeedInk(hex: 0xef_e7_d6)
    private static let paperText = FeedInk(hex: 0xf1_ea_d9)
    private static let creamText = FeedInk(hex: 0x24_1f_1a)

    private struct StatusSet {
        let approval: FeedInk
        let answer: FeedInk
        let running: FeedInk
        let completed: FeedInk

        func ink(for phase: SessionPhase) -> FeedInk {
            switch phase {
            case .waitingForApproval: approval
            case .waitingForAnswer: answer
            case .running: running
            case .completed: completed
            }
        }
    }

    /// Unchanged from `IslandDesignPalette.Status` -- these are the measured
    /// ink tints the whole app already uses.
    private static let inkTints = StatusSet(
        approval: FeedInk(hex: 0xf4_a4_a4),
        answer: FeedInk(hex: 0xff_d5_8a),
        running: FeedInk(hex: 0x6e_a7_ff),
        completed: FeedInk(hex: 0x6f_b9_82)
    )

    /// Hand-picked from Cat On Chair's own palette. An automated search that
    /// maximises lightness subject to 4.5:1 returns #d10f0f and #005ded --
    /// fully saturated, and the opposite of the reference's muted world.
    private static let paperTints = StatusSet(
        approval: FeedInk(hex: 0xa8_43_2f),
        answer: FeedInk(hex: 0x8a_5a_12),
        running: FeedInk(hex: 0x24_60_8f),
        completed: FeedInk(hex: 0x3d_6b_3d)
    )

    static func resolve(_ theme: IslandTheme) -> FeedTheme {
        switch theme {
        case .inkPaper:
            onInk(ground: inkGround, surface: nil)
        case .creamCard:
            onPaper(ground: inkGround, surface: creamGround)
        case .fullCream:
            onPaper(ground: creamGround, surface: nil)
        }
    }

    /// The four text weights for one ground, at the alphas §7.5 measured.
    private struct TextTiers {
        let text: FeedInk
        let dim: FeedInk
        let faint: FeedInk
        let hairline: FeedInk
    }

    /// Paper pigment on a dark ground.
    private static func inkTiers(on ground: FeedInk) -> TextTiers {
        TextTiers(
            text: .blend(paperText, over: ground, alpha: 0.94),
            dim: .blend(paperText, over: ground, alpha: 0.66),
            faint: .blend(paperText, over: ground, alpha: 0.50),
            hairline: .blend(paperText, over: ground, alpha: 0.14)
        )
    }

    /// Ink pigment on a light ground. `text` is opaque here: cream needs no
    /// veil to come down to a readable weight.
    private static func paperTiers(on ground: FeedInk) -> TextTiers {
        TextTiers(
            text: creamText,
            dim: .blend(creamText, over: ground, alpha: 0.80),
            faint: .blend(creamText, over: ground, alpha: 0.66),
            hairline: .blend(creamText, over: ground, alpha: 0.20)
        )
    }

    private static func onInk(ground: FeedInk, surface: FeedInk?) -> FeedTheme {
        let tiers = inkTiers(on: ground)
        return FeedTheme(
            ground: ground,
            surface: surface,
            text: tiers.text,
            dim: tiers.dim,
            faint: tiers.faint,
            hairline: tiers.hairline,
            chromeText: tiers.text,
            chromeDim: tiers.dim,
            chromeFaint: tiers.faint,
            approval: inkTints.approval,
            answer: inkTints.answer,
            running: inkTints.running,
            completed: inkTints.completed
        )
    }

    private static func onPaper(ground: FeedInk, surface: FeedInk?) -> FeedTheme {
        let reading = paperTiers(on: surface ?? ground)
        // With a card, the chrome is left standing on the ink panel and has to
        // be written in the ink skin's own pigment; without one it is on the
        // same cream the body is, and reads from the same tiers.
        let chrome = surface == nil ? reading : inkTiers(on: ground)
        return FeedTheme(
            ground: ground,
            surface: surface,
            text: reading.text,
            dim: reading.dim,
            faint: reading.faint,
            hairline: reading.hairline,
            chromeText: chrome.text,
            chromeDim: chrome.dim,
            chromeFaint: chrome.faint,
            approval: paperTints.approval,
            answer: paperTints.answer,
            running: paperTints.running,
            completed: paperTints.completed
        )
    }
}

/// The paper grain, built once.
///
/// A 128x128 tile of value noise, generated into a `CGImage` at first use and
/// tiled across the surface. No asset ships and the result is deterministic --
/// a seeded generator, not `Double.random`, so the texture does not crawl
/// between renders.
///
/// The noise lives in the tile's **alpha**, not its colour: the tile is white
/// throughout and varies only in coverage. That is what lets one tile serve
/// both grounds -- rendered as a template it takes whatever tint the theme
/// gives it, so grain lifts on ink and deepens on cream.
///
/// The first attempt varied the tile's *colour* and composited it with
/// `.blendMode(.overlay)`. Measured on device that produced a standard
/// deviation of roughly 1 unit in 255 -- mathematically present, perceptually
/// nothing. Overlay is `2 x base x blend` below mid-grey, so on a #12110f
/// ground the entire output range collapses to 0...0.14 and the noise has
/// nowhere to go. It is a midtone mode; this panel has no midtones.
///
/// MainActor-isolated because it is only ever used from views, and that keeps
/// the cached image out of Swift 6's global-mutable-state rules.
@MainActor
enum FeedGrain {
    static let tile: Image = Image(decorative: make(), scale: 1)
        .renderingMode(.template)

    private static let side = 128

    private static func make() -> CGImage {
        var seed: UInt64 = 0x5f3a_c91e
        func next() -> Double {
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return Double(seed % 1000) / 1000.0
        }

        // The context owns its buffer: passing `&pixels` for `data:` hands
        // CoreGraphics a pointer that dies at the end of the call, which the
        // compiler warns about and this project treats as a defect.
        let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: side * side * 4)
        for index in stride(from: 0, to: side * side * 4, by: 4) {
            // Premultiplied: white at `alpha` means every channel equals alpha.
            let alpha = UInt8(next() * 255)
            pixels[index] = alpha
            pixels[index + 1] = alpha
            pixels[index + 2] = alpha
            pixels[index + 3] = alpha
        }
        return context.makeImage()!
    }
}

extension FeedTheme {
    /// Paper fibre reads as flecks of light on a dark ground and flecks of
    /// shadow on a pale one, so the tint follows **whatever it is drawn over**.
    ///
    /// Taken per-surface rather than per-theme on purpose: on Cream card the
    /// panel ground is ink while `text` is dark, so keying the tint off the
    /// theme's text colour would paint dark grain onto a dark header and lose
    /// it entirely. The card gets its own call with its own ground.
    static func grainTint(over ground: FeedInk) -> Color {
        ground.luminance < 0.2
            ? FeedInk(hex: 0xf1_ea_d9).color
            : FeedInk(hex: 0x24_1f_1a).color
    }

    /// Deliberately low. Grain sits under legibility; anything strong enough to
    /// notice on its own is already muddying the prose.
    static func grainOpacity(over ground: FeedInk) -> Double {
        ground.luminance < 0.2 ? 0.10 : 0.13
    }

    var grainTint: Color { Self.grainTint(over: ground) }
    var grainOpacity: Double { Self.grainOpacity(over: ground) }
}

extension View {
    /// Lays paper grain over a surface, tinted for that surface.
    func feedGrain(tint: Color, opacity: Double) -> some View {
        overlay {
            FeedGrain.tile
                .resizable(resizingMode: .tile)
                .foregroundStyle(tint)
                .opacity(opacity)
                .allowsHitTesting(false)
        }
    }
}
