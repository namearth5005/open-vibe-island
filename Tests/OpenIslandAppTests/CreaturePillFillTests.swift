import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// `CreaturePalette.pillFill` is a copy of `V6Palette.ink` kept in Core so the
/// creature model can reason about the surface it is drawn on. Core cannot
/// import the app target, so no test inside Core can see the original — a Core
/// test can only pin the copy to a literal, which stays green while the two
/// drift apart. This is the one place both constants are visible at once.
struct CreaturePillFillTests {
    @Test
    func pillFillMatchesV6PaletteInk() throws {
        let ink = try #require(
            NSColor(V6Palette.ink).usingColorSpace(.sRGB),
            "V6Palette.ink could not be resolved into sRGB"
        )
        let copy = CreaturePalette.pillFill

        // Compared on the 0...255 scale so the tolerance reads plainly: half a
        // byte absorbs colour-space round-trip error while still failing on any
        // real change to a channel.
        #expect(abs(ink.redComponent * 255 - Double(copy.red)) < 0.5, "red is \(ink.redComponent * 255)")
        #expect(abs(ink.greenComponent * 255 - Double(copy.green)) < 0.5, "green is \(ink.greenComponent * 255)")
        #expect(abs(ink.blueComponent * 255 - Double(copy.blue)) < 0.5, "blue is \(ink.blueComponent * 255)")
    }
}
