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
    let text: FeedInk
    let dim: FeedInk
    let faint: FeedInk
    let hairline: FeedInk

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

    /// Status colour for the header, which sits on `ground` even when the body
    /// has its own surface. On Cream card those are different colours, so the
    /// header keeps the ink tints while the body uses the paper ones.
    func headerInk(for phase: SessionPhase) -> FeedInk {
        surface == nil ? ink(for: phase) : Self.inkTints.ink(for: phase)
    }

    func color(for phase: SessionPhase) -> Color { ink(for: phase).color }
    func headerColor(for phase: SessionPhase) -> Color { headerInk(for: phase).color }

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

    private static func onInk(ground: FeedInk, surface: FeedInk?) -> FeedTheme {
        FeedTheme(
            ground: ground,
            surface: surface,
            text: .blend(paperText, over: ground, alpha: 0.94),
            dim: .blend(paperText, over: ground, alpha: 0.66),
            faint: .blend(paperText, over: ground, alpha: 0.50),
            hairline: .blend(paperText, over: ground, alpha: 0.14),
            approval: inkTints.approval,
            answer: inkTints.answer,
            running: inkTints.running,
            completed: inkTints.completed
        )
    }

    private static func onPaper(ground: FeedInk, surface: FeedInk?) -> FeedTheme {
        let reading = surface ?? ground
        return FeedTheme(
            ground: ground,
            surface: surface,
            text: creamText,
            dim: .blend(creamText, over: reading, alpha: 0.80),
            faint: .blend(creamText, over: reading, alpha: 0.66),
            hairline: .blend(creamText, over: reading, alpha: 0.20),
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
/// MainActor-isolated because it is only ever used from views, and that keeps
/// the cached image out of Swift 6's global-mutable-state rules.
@MainActor
enum FeedGrain {
    static let tile: Image = Image(decorative: make(), scale: 1)

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
            let value = UInt8(120 + next() * 135)
            pixels[index] = value
            pixels[index + 1] = value
            pixels[index + 2] = value
            pixels[index + 3] = 255
        }
        return context.makeImage()!
    }
}

extension View {
    /// Lays paper grain over a surface. Overlay blend keeps it a texture rather
    /// than a fog -- it darkens and lightens the ground instead of veiling it.
    func feedGrain(opacity: Double = 0.30) -> some View {
        overlay {
            FeedGrain.tile
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
                .opacity(opacity)
                .allowsHitTesting(false)
        }
    }
}
