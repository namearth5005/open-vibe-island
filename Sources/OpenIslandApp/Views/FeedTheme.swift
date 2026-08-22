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
