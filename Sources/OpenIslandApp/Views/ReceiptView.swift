import OpenIslandCore
import SwiftUI

/// The seven things the day's receipt accounts for.
///
/// An enum rather than seven strings so the set is closed: the acceptance
/// condition is that every one of these is printed, which is only checkable if
/// the list exists as a value. Declaration order is till-roll order.
enum ReceiptItem: String, CaseIterable, Sendable {
    case cleanFinish
    case interrupted
    case total
    case sessionsRun
    case answeredInTime
    case keptWaiting
    case bestRun

    /// Mixed case for the items, upper for the total, exactly as a printer
    /// emits them — the shift in register is what makes the total look like the
    /// bottom line rather than an eighth item. The case distinction is carried
    /// in the translations, because it does not survive into Chinese and a
    /// `.uppercased()` here would be a no-op there rather than an emphasis.
    var labelKey: String { "receipt.item.\(rawValue)" }

    func label(_ lang: LanguageManager) -> String { lang.t(labelKey) }
}

/// One printed line: what it was, what it came to, and whether that was a good
/// thing.
struct ReceiptLine: Equatable, Identifiable, Sendable {
    enum Polarity: Equatable, Sendable {
        case credit
        case debit
        case neutral
    }

    let item: ReceiptItem
    /// Signed sessions this line contributes to the TOTAL, and zero for every
    /// line that does not. The figure column is a string because it also holds
    /// durations and dashes; this is the arithmetic behind it, kept separate so
    /// the total can be *proved* to be the sum of the ledger rather than
    /// asserted to be.
    let amount: Int
    /// The right-hand column, monospaced.
    let figure: String
    /// The same fact in words. `+8`, `-3` and `—` are printer's marks: read
    /// aloud they are noise, which is the same reason `IslandDurationGrain`
    /// carries a spoken form beside its badge.
    let spokenFigure: String
    /// The indented sub-line under the label, receipt-style. Used where a
    /// figure would otherwise be unexplainable — a count of answers needs its
    /// denominator, and a session count needs to say how much of it was
    /// inferred rather than watched.
    let note: String?
    let polarity: Polarity
    /// Resolved when the receipt is printed, like every other string on it.
    let label: String

    var id: ReceiptItem { item }

    var accessibilityDescription: String {
        [label, spokenFigure, note].compactMap { $0 }.joined(separator: ", ")
    }
}

/// The day, printed.
///
/// Everything here already exists in `SessionStats`; nothing is computed twice
/// and nothing is stored. The point of the type is that the *arithmetic* is
/// separable from the paper: which figure lands on which line, and what the
/// total is the sum of, are claims that can be checked without rendering
/// anything — which is the only way "correct on a day with no sessions" can be
/// an assertion rather than a promise.
///
/// **The TOTAL is sessions, not points.** The design shows `+105` but this app
/// has no scoring system, no currency and nothing to spend one on, and the
/// spec's own non-goals close that off. So the amount column is the one unit the
/// receipt already deals in: a session that went well is `+1`, a session that
/// was interrupted is `-1`, and the total is the difference. That is the
/// reference product's exact shape with the arbitrary multiplier set to one —
/// which is why the quantity column collapses away and there is nothing left to
/// tune, re-balance or farm.
///
/// The lines that are not sessions — a wait, a longest run, a count of answers —
/// therefore cannot enter the total, and are printed *below* it as a memo block.
/// That is standard till-roll grammar (`Items: 3`, `You saved £0.72`) and it is
/// what keeps the arithmetic legible: the rule is "add up the signed column",
/// and only the ledger is signed.
struct Receipt: Equatable, Sendable {
    /// 540pt on notch Macs, 520 on external displays — the band the scene, the
    /// strip and the detail row are all drawn into.
    let width: CGFloat
    let dateLine: String
    /// The two lines the TOTAL is the sum of.
    let ledger: [ReceiptLine]
    let total: ReceiptLine
    /// Figures the total does not sum, because they are not sessions.
    let memo: [ReceiptLine]
    let footer: String

    /// The shop's name, and the one string on the paper that stays English in
    /// every locale — it is a trading name, and the app's own name is already
    /// left untranslated everywhere else in the catalogue.
    static let title = "OPEN ISLAND INC."
    /// Two of this design's non-goals, printed where a till roll prints its
    /// returns policy. It is a joke that is also true.
    static let busyFooterKey = "receipt.footer.busy"
    /// A day with nothing on it still gets a receipt, and this is the line that
    /// makes it read as one. A blank sheet is indistinguishable from a view
    /// that failed to load; a printed "nothing" is a statement.
    static let emptyFooterKey = "receipt.footer.empty"

    // MARK: - Paper

    /// The band's own side inset, taken from the strip rather than restated, so
    /// the paper can never come to sit inside a margin the other bands stopped
    /// using.
    static let horizontalInset = IslandIdentityStripLayout.horizontalInset
    /// A till roll is paper lying on the panel, not a pane filling it. Wider
    /// than this and the two-column rhythm stops reading as a printed slip.
    static let maximumPaperWidth: CGFloat = 300
    /// Margin inside the paper.
    static let paperPadding: CGFloat = 22

    static let tornEdgeHeight: CGFloat = 7
    static let verticalPadding: CGFloat = 14
    static let titleHeight: CGFloat = 18
    static let dateHeight: CGFloat = 14
    static let ruleHeight: CGFloat = 13
    static let lineHeight: CGFloat = 16
    static let noteHeight: CGFloat = 12
    static let totalHeight: CGFloat = 24
    static let footerHeight: CGFloat = 20

    static let titleFontSize: CGFloat = 11.5
    static let dateFontSize: CGFloat = 9
    static let lineFontSize: CGFloat = 10.5
    static let noteFontSize: CGFloat = 8.5
    static let totalFontSize: CGFloat = 14
    static let footerFontSize: CGFloat = 8.5

    var paperWidth: CGFloat {
        max(0, min(Self.maximumPaperWidth, width - Self.horizontalInset * 2))
    }

    /// Derived from what is actually printed, so the panel can reserve the
    /// space before anything is laid out. Notes are the only variable: a day
    /// with back-filled sessions prints one extra sub-line.
    var height: CGFloat {
        func rows(_ lines: [ReceiptLine]) -> CGFloat {
            lines.reduce(0) { $0 + Self.lineHeight + ($1.note == nil ? 0 : Self.noteHeight) }
        }

        return (Self.tornEdgeHeight + Self.verticalPadding) * 2
            + Self.titleHeight
            + Self.dateHeight
            + Self.ruleHeight * 3
            + rows(ledger)
            + Self.totalHeight
            + rows(memo)
            + Self.footerHeight
    }

    var lines: [ReceiptLine] { ledger + [total] + memo }

    func line(_ item: ReceiptItem) -> ReceiptLine? {
        lines.first { $0.item == item }
    }

    // MARK: - Printing

    init(
        records: [SessionLogRecord],
        now: Date,
        width: CGFloat,
        calendar: Calendar = .current,
        lang: LanguageManager = .shared
    ) {
        self.width = width

        let summary = SessionStats.summary(for: .today, records: records, now: now, calendar: calendar)
        dateLine = Self.dateLine(for: now, calendar: calendar)
        footer = lang.t(summary.finished == 0 ? Self.emptyFooterKey : Self.busyFooterKey)

        ledger = [
            Self.ledgerLine(.cleanFinish, sessions: summary.cleanFinishes, sign: 1, lang: lang),
            Self.ledgerLine(.interrupted, sessions: summary.interrupted, sign: -1, lang: lang),
        ]
        total = Self.totalLine(ledger.reduce(0) { $0 + $1.amount }, lang: lang)

        memo = [
            Self.sessionsRunLine(summary, lang: lang),
            Self.answeredInTimeLine(summary, lang: lang),
            Self.durationLine(
                .keptWaiting,
                // Zero is "nobody was kept waiting", which is the absence of a
                // measurement rather than a wait of no length.
                seconds: summary.totalWaiting > 0 ? summary.totalWaiting : nil,
                polarity: .debit,
                lang: lang
            ),
            Self.durationLine(.bestRun, seconds: summary.longestCleanRun, polarity: .credit, lang: lang),
        ]
    }

    /// A signed session count.
    ///
    /// Zero prints unsigned and uncoloured. `+0` in green would be the receipt
    /// congratulating a day that did not happen, and it is the one figure on an
    /// empty receipt most likely to read as a rendering fault.
    private static func ledgerLine(
        _ item: ReceiptItem,
        sessions: Int,
        sign: Int,
        lang: LanguageManager
    ) -> ReceiptLine {
        ReceiptLine(
            item: item,
            amount: sessions * sign,
            figure: sessions == 0 ? "0" : (sign > 0 ? "+\(sessions)" : "-\(sessions)"),
            spokenFigure: spokenSessions(sessions, lang),
            note: nil,
            polarity: sessions == 0 ? .neutral : (sign > 0 ? .credit : .debit),
            label: item.label(lang)
        )
    }

    private static func totalLine(_ amount: Int, lang: LanguageManager) -> ReceiptLine {
        ReceiptLine(
            item: .total,
            amount: amount,
            figure: amount == 0 ? "0" : (amount > 0 ? "+\(amount)" : "\(amount)"),
            spokenFigure: amount == 0
                ? lang.t("receipt.spoken.even")
                : lang.t(amount > 0 ? "receipt.spoken.up" : "receipt.spoken.down", abs(amount)),
            note: nil,
            polarity: amount == 0 ? .neutral : (amount > 0 ? .credit : .debit),
            label: ReceiptItem.total.label(lang)
        )
    }

    /// The day's item count, and how much of it the island only inferred.
    ///
    /// Back-filled sessions are counted here and credited above, because a
    /// transcript does prove a session happened and finished — that is the whole
    /// of what those lines claim. But it proves nothing about answer times, so
    /// the note is what stops "Sessions run 11" sitting over "of 1 asked" and
    /// looking like a bug. The gap is printed rather than swallowed.
    private static func sessionsRunLine(_ summary: StatsSummary, lang: LanguageManager) -> ReceiptLine {
        ReceiptLine(
            item: .sessionsRun,
            amount: 0,
            figure: "\(summary.finished)",
            spokenFigure: spokenSessions(summary.finished, lang),
            note: summary.inferred > 0 ? lang.t("receipt.note.unwatched", summary.inferred) : nil,
            polarity: .neutral,
            label: ReceiptItem.sessionsRun.label(lang)
        )
    }

    /// How many sessions kept every gate inside the 30-second grace window.
    ///
    /// A session that never asked is neither numerator nor denominator.
    /// `RewardRarity` passes one vacuously — correctly, because a *tier* is a
    /// judgement about a whole session — but a *count of answers* that included
    /// a session nobody was asked anything by would simply be false.
    private static func answeredInTimeLine(_ summary: StatsSummary, lang: LanguageManager) -> ReceiptLine {
        guard summary.gatedSessions > 0 else {
            return ReceiptLine(
                item: .answeredInTime,
                amount: 0,
                figure: IslandDetailBand.absentBadge,
                spokenFigure: lang.t("receipt.spoken.noneAsked"),
                note: nil,
                polarity: .neutral,
                label: ReceiptItem.answeredInTime.label(lang)
            )
        }

        let answered = summary.answeredInsideGrace
        return ReceiptLine(
            item: .answeredInTime,
            amount: 0,
            figure: "\(answered)",
            spokenFigure: lang.t(
                answered == 1 ? "receipt.spoken.answer" : "receipt.spoken.answers",
                answered
            ),
            note: lang.t("receipt.note.asked", summary.gatedSessions),
            // Zero is a measured zero — the denominator proves the clock ran —
            // but it is not a debit. Slowness is already charged for on the line
            // above it, and charging twice for one failing would be the receipt
            // arguing with you.
            polarity: answered > 0 ? .credit : .neutral,
            label: ReceiptItem.answeredInTime.label(lang)
        )
    }

    /// A duration, in the island's one duration vocabulary.
    ///
    /// `IslandDurationGrain` and nothing else: the strip, the detail row and the
    /// receipt round the same way or the same session reads as two lengths in
    /// two bands.
    private static func durationLine(
        _ item: ReceiptItem,
        seconds: TimeInterval?,
        polarity: ReceiptLine.Polarity,
        lang: LanguageManager
    ) -> ReceiptLine {
        guard let seconds else {
            return ReceiptLine(
                item: item,
                amount: 0,
                figure: IslandDetailBand.absentBadge,
                spokenFigure: lang.t("receipt.spoken.none"),
                note: nil,
                polarity: .neutral,
                label: item.label(lang)
            )
        }

        let grain = IslandDurationGrain(seconds: seconds)
        return ReceiptLine(
            item: item,
            amount: 0,
            figure: grain.badge,
            spokenFigure: grain.spoken(lang),
            note: nil,
            polarity: polarity,
            label: item.label(lang)
        )
    }

    private static func spokenSessions(_ count: Int, _ lang: LanguageManager) -> String {
        switch count {
        case 0: lang.t("receipt.spoken.none")
        case 1: lang.t("receipt.spoken.session")
        default: lang.t("receipt.spoken.sessions", count)
        }
    }

    /// Dated in the calendar the day was counted in, and in a fixed printer's
    /// format.
    ///
    /// Both halves matter. A header dated by the device while the arithmetic
    /// bucketed by another time zone would put the wrong date on a correct
    /// receipt; and a locale-sensitive format would make the one string on the
    /// paper that is supposed to be machine-printed drift with the region.
    private static func dateLine(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEE dd MMM yyyy"
        return formatter.string(from: date).uppercased()
    }
}

// MARK: - Paper

/// A slip torn off a roll: straight sides, ragged top and bottom.
///
/// The tear is deterministic. A shape that re-rolled its randomness would
/// shiver every time a figure changed, and the one thing a printed document may
/// not do is move.
struct TornPaperShape: Shape {
    var tooth: CGFloat = Receipt.tornEdgeHeight

    /// Fine enough that the edge reads as paper fibre rather than as a zigzag
    /// border drawn round a rectangle — at the pitch a tooth is visible as a
    /// tooth, the slip stops looking torn and starts looking stamped.
    static let toothWidth: CGFloat = 4.5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = max(4, Int((rect.width / Self.toothWidth).rounded()))
        let step = rect.width / CGFloat(count)

        func x(_ index: Int) -> CGFloat { rect.minX + step * CGFloat(index) }
        func topY(_ index: Int) -> CGFloat { rect.minY + tooth * Self.depth(index) }
        // Offset so the bottom tear is a different tear from the top one.
        func bottomY(_ index: Int) -> CGFloat { rect.maxY - tooth * Self.depth(index + count + 1) }

        path.move(to: CGPoint(x: x(0), y: topY(0)))
        for index in 1...count {
            path.addLine(to: CGPoint(x: x(index), y: topY(index)))
        }
        path.addLine(to: CGPoint(x: x(count), y: bottomY(count)))
        for index in stride(from: count - 1, through: 0, by: -1) {
            path.addLine(to: CGPoint(x: x(index), y: bottomY(index)))
        }
        path.closeSubpath()
        return path
    }

    /// How far into the paper this vertex bites, 0…1.
    ///
    /// Neighbouring vertices are averaged rather than drawn independently. Pure
    /// per-vertex noise gives a comb; a tear runs in short streaks, and one tap
    /// of smoothing is the whole difference between the two.
    private static func depth(_ index: Int) -> CGFloat {
        (noise(index) + noise(index + 1)) / 2
    }

    private static func noise(_ index: Int) -> CGFloat {
        let raw = sin(Double(index) * 12.9898) * 43_758.5453
        return CGFloat(raw - raw.rounded(.down))
    }
}

extension ReceiptLine.Polarity {
    var inkColor: Color {
        switch self {
        case .credit: IslandDesignPalette.Paper.creditColor
        case .debit: IslandDesignPalette.Paper.debitColor
        case .neutral: IslandDesignPalette.Paper.inkColor
        }
    }
}

/// The end of the day, printed on a slip of paper.
///
/// Typography, not painting: no creature, no scene, no illustration. The whole
/// of its charm is that the numbers the Stats pane renders as medians and a
/// sparkline are the same numbers, and set as a till roll they are a thing you
/// would screenshot.
///
/// It is the one island surface that inverts the panel — dark ink on cream
/// stock rather than paper-on-ink — which is what makes it read as an object
/// lying on the panel rather than as another band of it.
struct ReceiptView: View {
    let receipt: Receipt

    /// A line at a time rather than one long sentence. The receipt is a
    /// document, and a reader who wants the total should not have to sit
    /// through the memo block to reach it.
    var body: some View {
        slip
            .frame(width: receipt.width, height: receipt.height)
            .accessibilityElement(children: .contain)
    }

    private var slip: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: Receipt.tornEdgeHeight + Receipt.verticalPadding)

            header
            DashedRule()

            ForEach(receipt.ledger) { row($0) }

            DashedRule()
            totalRow
            DashedRule()

            ForEach(receipt.memo) { row($0) }

            Text(receipt.footer)
                .font(.system(size: Receipt.footerFontSize, weight: .medium, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(IslandDesignPalette.Paper.faintColor)
                .frame(height: Receipt.footerHeight)

            Color.clear
                .frame(height: Receipt.tornEdgeHeight + Receipt.verticalPadding)
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, Receipt.paperPadding)
        .frame(width: receipt.paperWidth)
        .background(
            TornPaperShape()
                .fill(IslandDesignPalette.Paper.stockColor)
                // The lift is what separates paper from panel; without it the
                // torn edge reads as a decorative border on a light rectangle.
                .shadow(color: .black.opacity(0.4), radius: 7, x: 0, y: 3)
        )
    }

    private var header: some View {
        VStack(spacing: 0) {
            Text(Receipt.title)
                .font(.system(size: Receipt.titleFontSize, weight: .bold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(IslandDesignPalette.Paper.inkColor)
                .frame(height: Receipt.titleHeight)

            Text(receipt.dateLine)
                .font(.system(size: Receipt.dateFontSize, weight: .medium, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(IslandDesignPalette.Paper.faintColor)
                .frame(height: Receipt.dateHeight)
        }
    }

    /// Label left, figure right, note indented beneath.
    ///
    /// Monospaced throughout rather than only in the figure column: a till roll
    /// is one typewriter, and the even column is what makes a stack of numbers
    /// scan as a printed document instead of as a settings pane.
    private func row(_ line: ReceiptLine) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(line.label)
                    .foregroundStyle(IslandDesignPalette.Paper.inkColor)

                Spacer(minLength: 8)

                Text(line.figure)
                    .foregroundStyle(line.polarity.inkColor)
            }
            .font(.system(size: Receipt.lineFontSize, weight: .regular, design: .monospaced))
            .frame(height: Receipt.lineHeight)

            if let note = line.note {
                Text(note)
                    .font(.system(size: Receipt.noteFontSize, design: .monospaced))
                    .foregroundStyle(IslandDesignPalette.Paper.faintColor)
                    .frame(height: Receipt.noteHeight, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10)
            }
        }
        // The figure is a mark and the note is a fragment; neither says
        // anything on its own, so the row speaks as one phrase.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.accessibilityDescription)
    }

    /// The bottom line, and the only thing on the paper set larger than the
    /// items — because it is the one figure a screenshot is of.
    private var totalRow: some View {
        HStack(spacing: 8) {
            Text(receipt.total.label)
                .tracking(1.2)
                .foregroundStyle(IslandDesignPalette.Paper.inkColor)

            Spacer(minLength: 8)

            Text(receipt.total.figure)
                .foregroundStyle(receipt.total.polarity.inkColor)
        }
        .font(.system(size: Receipt.totalFontSize, weight: .bold, design: .monospaced))
        .frame(height: Receipt.totalHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(receipt.total.accessibilityDescription)
    }
}

/// The dotted rule a receipt printer draws between sections.
private struct DashedRule: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let y = proxy.size.height / 2
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: proxy.size.width, y: y))
            }
            .stroke(
                IslandDesignPalette.Paper.faintColor,
                style: StrokeStyle(lineWidth: 1, dash: [2, 3])
            )
        }
        .frame(height: Receipt.ruleHeight)
    }
}
