import SwiftUI
import OpenIslandCore

enum IslandDesignPalette {
    /// The receipt's ink, on the receipt's stock.
    ///
    /// Every other island surface is light-on-dark; the receipt is the one that
    /// inverts, because paper is what makes a till roll read as a printed thing
    /// rather than as another pane. That inversion makes the panel's own opacity
    /// ladder useless here — `paper.opacity(0.42)` lightens *toward* the stock
    /// and lands at 1.6:1 — so the marks are separate colours rather than
    /// transparencies.
    ///
    /// They are derived, not picked. Each starts from the design spec's measured
    /// palette and is scaled in linear light to a fixed luminance, exactly as
    /// `CreaturePalette.panelColor(for:)` does, which is what makes the 4.5:1
    /// property hold by construction rather than by review. Asserted in
    /// `ReceiptPaperTests`.
    enum Paper {
        /// The panel's own cream, not a second one.
        static let stock = CreatureColor(red: 0xF1, green: 0xEA, blue: 0xD9)

        /// The spec's `lineWork`, unmodified: 13.9:1 on this stock.
        static let ink = CreatureColor(red: 0x21, green: 0x1E, blue: 0x12)

        /// Where credit, debit and the notes sit. Low enough to read as print
        /// at 6.7:1, high enough that a coloured amount does not out-shout the
        /// black label beside it.
        static let markLuminance = 0.08

        /// The spec's contact-band green.
        static let credit = CreatureColor(red: 0x70, green: 0x94, blue: 0x58)
            .scaledToLuminance(markLuminance)

        /// The spec's accent red.
        static let debit = CreatureColor(red: 0xB7, green: 0x3B, blue: 0x3A)
            .scaledToLuminance(markLuminance)

        /// Sub-lines and rules — the ink lifted until it recedes without
        /// dropping under the body-text bar.
        static let faint = ink.scaledToLuminance(0.11)

        static var stockColor: Color { Color(stock) }
        static var inkColor: Color { Color(ink) }
        static var creditColor: Color { Color(credit) }
        static var debitColor: Color { Color(debit) }
        static var faintColor: Color { Color(faint) }
    }

    enum Status {
        static let waitingAggregate = Color(red: 231.0 / 255.0, green: 167.0 / 255.0, blue: 98.0 / 255.0)
        static let waitingForApproval = Color(red: 244.0 / 255.0, green: 164.0 / 255.0, blue: 164.0 / 255.0)
        static let waitingForAnswer = Color(red: 255.0 / 255.0, green: 213.0 / 255.0, blue: 138.0 / 255.0)
        static let running = Color(red: 110.0 / 255.0, green: 167.0 / 255.0, blue: 255.0 / 255.0)
        static let completed = Color(red: 111.0 / 255.0, green: 185.0 / 255.0, blue: 130.0 / 255.0)
        static let inactive = V6Palette.paper.opacity(0.38)
        static let idle = V6Palette.paper.opacity(0.35)

        static func tint(for phase: SessionPhase) -> Color {
            switch phase {
            case .waitingForApproval:
                waitingForApproval
            case .waitingForAnswer:
                waitingForAnswer
            case .running:
                running
            case .completed:
                completed
            }
        }

        static func tint(for phase: SessionPhase, presence: IslandSessionPresence) -> Color {
            if phase == .waitingForApproval || phase == .waitingForAnswer {
                return tint(for: phase)
            }

            switch presence {
            case .running:
                return running
            case .active:
                return completed
            case .inactive:
                return inactive
            }
        }
    }
}
