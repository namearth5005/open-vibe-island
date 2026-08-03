import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// The receipt is arithmetic printed on paper, so the arithmetic is what is
/// worth asserting: which figure each line carries, which lines the TOTAL is
/// the sum of, and that a day with nothing on it still prints a receipt rather
/// than a hole. A view body can be looked at; it cannot be added up.
struct ReceiptTests {
    /// Fixed and UTC so a day never straddles midnight by accident — the same
    /// arrangement `SessionStatsTests` uses.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let now = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13:20 UTC

    private func day(_ offset: Int, hour: Int = 12) -> Date {
        let today = calendar.startOfDay(for: now)
        let base = calendar.date(byAdding: .day, value: -offset, to: today)!
        return calendar.date(byAdding: .hour, value: hour, to: base)!
    }

    private func record(
        _ id: String,
        endedAt: Date? = nil,
        durationSeconds: TimeInterval = 60,
        interrupted: Bool = false,
        gates: Int = 0,
        meanLatency: Double? = nil,
        worstLatency: Double? = nil,
        inferred: Bool? = nil
    ) -> SessionLogRecord {
        let ended = endedAt ?? day(0)
        return SessionLogRecord(
            sessionID: id,
            tool: .claudeCode,
            startedAt: ended.addingTimeInterval(-durationSeconds),
            endedAt: ended,
            wasInterrupted: interrupted,
            stallCount: gates,
            meanGateLatency: meanLatency,
            worstGateLatency: worstLatency,
            isInferred: inferred
        )
    }

    private func receipt(_ records: [SessionLogRecord], width: CGFloat = 540) -> Receipt {
        Receipt(records: records, now: now, width: width, calendar: calendar)
    }

    private func figure(_ item: ReceiptItem, _ records: [SessionLogRecord]) -> String? {
        receipt(records).line(item)?.figure
    }

    private func polarity(_ item: ReceiptItem, _ records: [SessionLogRecord]) -> ReceiptLine.Polarity? {
        receipt(records).line(item)?.polarity
    }

    // MARK: - Every line item is on the receipt

    /// The seven items the design asks for, present whatever the day held.
    @Test
    func everyLineItemIsPrintedExactlyOnce() {
        for records in [[], [record("a"), record("b", interrupted: true)]] {
            let printed = receipt(records).lines.map(\.item)
            #expect(printed.count == ReceiptItem.allCases.count)
            #expect(Set(printed) == Set(ReceiptItem.allCases))
        }
    }

    /// A receipt reads top to bottom: what you bought, what it came to, then the
    /// memo. Nothing may drift out of that order silently.
    @Test
    func linesReadInTillRollOrder() {
        #expect(receipt([]).lines.map(\.item) == [
            .cleanFinish, .interrupted, .total, .sessionsRun, .answeredInTime, .keptWaiting, .bestRun,
        ])
    }

    // MARK: - A day with nothing on it

    /// The requirement in full: an empty day must read as a deliberate receipt.
    /// Every line still prints, every figure is a real mark, and none of them
    /// claims a measurement nobody took.
    @Test
    func aDayWithNoSessionsStillPrintsAWholeReceipt() {
        let empty = receipt([])
        #expect(empty.lines.count == ReceiptItem.allCases.count)
        #expect(empty.lines.allSatisfy { !$0.figure.isEmpty })
        #expect(empty.total.figure == "0")
    }

    /// Counts print zero because zero sessions is a measured fact. Durations and
    /// answer times print an em dash because no clock was ever started — the
    /// same distinction `IslandDetailBand.absentBadge` already draws.
    @Test
    func anEmptyDayPrintsZerosForCountsAndDashesForUnmeasuredFigures() {
        #expect(figure(.sessionsRun, []) == "0")
        #expect(figure(.cleanFinish, []) == "0")
        #expect(figure(.interrupted, []) == "0")
        #expect(figure(.answeredInTime, []) == IslandDetailBand.absentBadge)
        #expect(figure(.keptWaiting, []) == IslandDetailBand.absentBadge)
        #expect(figure(.bestRun, []) == IslandDetailBand.absentBadge)
    }

    /// Nothing happened, so nothing went well and nothing went badly. A green
    /// `+0` would be the receipt congratulating an empty day.
    @Test
    func anEmptyDayColoursNothingAndSignsNothing() {
        let empty = receipt([])
        #expect(empty.lines.allSatisfy { $0.polarity == .neutral })
        #expect(empty.lines.allSatisfy { !$0.figure.hasPrefix("+") && !$0.figure.hasPrefix("-") })
    }

    @Test
    func anEmptyDayGetsItsOwnFooterRatherThanABlankOne() {
        #expect(receipt([]).footer == Receipt.emptyFooter)
        #expect(receipt([record("a")]).footer == Receipt.busyFooter)
        #expect(!Receipt.emptyFooter.isEmpty)
    }

    // MARK: - The ledger, and what the TOTAL is the sum of

    @Test
    func cleanFinishesArePrintedAsACredit() {
        let records = [record("a"), record("b"), record("c")]
        #expect(figure(.cleanFinish, records) == "+3")
        #expect(polarity(.cleanFinish, records) == .credit)
    }

    @Test
    func interruptsArePrintedAsADebit() {
        let records = [record("a", interrupted: true), record("b", interrupted: true)]
        #expect(figure(.interrupted, records) == "-2")
        #expect(polarity(.interrupted, records) == .debit)
    }

    /// The whole reason the amount column exists: two signed lines and a rule
    /// under them.
    @Test
    func theTotalIsCleanFinishesLessInterrupts() {
        let records = [record("a"), record("b"), record("c"), record("d", interrupted: true)]
        #expect(figure(.total, records) == "+2")
        #expect(polarity(.total, records) == .credit)
    }

    @Test
    func aDayThatWentBadlyTotalsNegative() {
        let records = [record("a"), record("b", interrupted: true), record("c", interrupted: true)]
        #expect(figure(.total, records) == "-1")
        #expect(polarity(.total, records) == .debit)
    }

    /// A day that broke even is neither a win nor a loss, and an unsigned `0`
    /// is how a till roll says so.
    @Test
    func aDayThatBrokeEvenPrintsAnUnsignedZero() {
        let records = [record("a"), record("b", interrupted: true)]
        #expect(figure(.total, records) == "0")
        #expect(polarity(.total, records) == .neutral)
    }

    /// The claim that makes the receipt readable: the number under the rule is
    /// the sum of the numbers above it, and of nothing else. Mutation guard —
    /// if a memo figure ever started contributing, this fails.
    @Test
    func theTotalIsTheSumOfTheLedgerAndOfNothingBelowIt() {
        let records = [
            record("a", durationSeconds: 4_000, gates: 2, meanLatency: 90, worstLatency: 200),
            record("b", gates: 1, meanLatency: 3, worstLatency: 3),
            record("c", interrupted: true),
            record("d", inferred: true),
        ]
        let printed = receipt(records)
        let ledgerSum = printed.ledger.reduce(0) { $0 + $1.amount }
        #expect(printed.total.amount == ledgerSum)
        #expect(printed.memo.allSatisfy { $0.amount == 0 })
    }

    /// Yesterday's work is on yesterday's receipt. A daily total that quietly
    /// included last week would be the one number nobody could check.
    @Test
    func onlyTodayIsOnTodaysReceipt() {
        let records = [
            record("today", endedAt: day(0)),
            record("yesterday", endedAt: day(1)),
            record("lastWeek", endedAt: day(7)),
        ]
        #expect(figure(.sessionsRun, records) == "1")
        #expect(figure(.total, records) == "+1")
    }

    // MARK: - The memo block

    @Test
    func sessionsRunCountsEveryFinishedSessionCleanOrNot() {
        let records = [record("a"), record("b", interrupted: true), record("c")]
        #expect(figure(.sessionsRun, records) == "3")
        #expect(polarity(.sessionsRun, records) == .neutral)
    }

    /// Total frozen time across every gate of the day. `meanGateLatency` is
    /// `frozenSeconds / stallCount` by construction, so the product restores
    /// the exact seconds rather than approximating them.
    @Test
    func keptWaitingIsEveryGateOfTheDayAddedUp() {
        let records = [
            record("a", gates: 3, meanLatency: 20, worstLatency: 40), // 60s
            record("b", gates: 2, meanLatency: 45, worstLatency: 60), // 90s
        ]
        #expect(figure(.keptWaiting, records) == IslandDurationGrain(seconds: 150).badge)
        #expect(polarity(.keptWaiting, records) == .debit)
    }

    /// A session that never blocked cost you nothing, and a receipt that
    /// printed `<1m` for it would invent a wait.
    @Test
    func aDayNobodyWasKeptWaitingPrintsNoWait() {
        #expect(figure(.keptWaiting, [record("a"), record("b")]) == IslandDetailBand.absentBadge)
        #expect(polarity(.keptWaiting, [record("a")]) == .neutral)
    }

    @Test
    func bestRunIsTheLongestCleanSessionOfTheDay() {
        let records = [
            record("short", durationSeconds: 300),
            record("long", durationSeconds: 52 * 60),
            record("middling", durationSeconds: 20 * 60),
        ]
        #expect(figure(.bestRun, records) == IslandDurationGrain(seconds: 52 * 60).badge)
        #expect(polarity(.bestRun, records) == .credit)
    }

    /// An interrupt is not a run. The longest session of a day can be the one
    /// you killed, and crowning it would make the line meaningless.
    @Test
    func bestRunIgnoresInterruptedSessionsHoweverLongTheyRan() {
        let records = [
            record("killed", durationSeconds: 3 * 3_600, interrupted: true),
            record("finished", durationSeconds: 12 * 60),
        ]
        #expect(figure(.bestRun, records) == IslandDurationGrain(seconds: 12 * 60).badge)
    }

    @Test
    func aDayWithNothingButInterruptsHasNoBestRun() {
        #expect(figure(.bestRun, [record("a", interrupted: true)]) == IslandDetailBand.absentBadge)
    }

    // MARK: - Answers inside the grace window

    /// The grace window is `RewardRarity.graceWindow`, read through the same
    /// rule the rarity ladder uses so the receipt and the objects can never
    /// disagree about what "in time" means.
    @Test
    func answeredInTimeCountsSessionsThatKeptEveryGateInsideTheWindow() {
        let records = [
            record("fast", gates: 2, meanLatency: 4, worstLatency: 9),
            record("slow", gates: 1, meanLatency: 90, worstLatency: 90),
            record("alsoFast", gates: 1, meanLatency: 30, worstLatency: 30),
        ]
        #expect(figure(.answeredInTime, records) == "2")
        #expect(receipt(records).line(.answeredInTime)?.note == "of 3 asked")
        #expect(polarity(.answeredInTime, records) == .credit)
    }

    /// A session that never asked has no answer to be in time for, so it is
    /// neither numerator nor denominator. This is the line's whole subtlety:
    /// `RewardRarity` passes a gateless session vacuously because a *tier* is a
    /// judgement, but a *count of answers* that included one would be a lie.
    @Test
    func sessionsThatNeverAskedAreNotCountedAsAnswers() {
        let records = [record("quiet"), record("alsoQuiet")]
        #expect(figure(.answeredInTime, records) == IslandDetailBand.absentBadge)
        #expect(receipt(records).line(.answeredInTime)?.note == nil)
    }

    /// Answering nothing in time is a measured zero, not an absence — the
    /// denominator proves the clock ran.
    @Test
    func aDayWhereEveryAnswerWasLatePrintsAMeasuredZero() {
        let records = [record("slow", gates: 1, meanLatency: 120, worstLatency: 120)]
        #expect(figure(.answeredInTime, records) == "0")
        #expect(receipt(records).line(.answeredInTime)?.note == "of 1 asked")
        #expect(polarity(.answeredInTime, records) == .neutral)
    }

    /// Records written before `worstGateLatency` existed fall back to the mean,
    /// exactly as `RewardRarity` does, rather than dropping off the receipt.
    @Test
    func recordsWithoutAWorstGateFallBackToTheMean() {
        let records = [record("old", gates: 2, meanLatency: 12)]
        #expect(figure(.answeredInTime, records) == "1")
    }

    /// One gate past the window loses the line however fast the rest were —
    /// the worst gate decides, not the average.
    @Test
    func oneSlowGateDisqualifiesASessionEvenWhenTheMeanIsInside() {
        let records = [record("mixed", gates: 2, meanLatency: 30, worstLatency: 59)]
        #expect(figure(.answeredInTime, records) == "0")
    }

    // MARK: - Back-filled history

    /// Inference can support "this session happened and finished", which is
    /// what the count of sessions and the clean-finish credit both claim, so a
    /// back-filled session is on the receipt like any other.
    @Test
    func backFilledSessionsAreCountedAndTotalled() {
        let records = [record("watched"), record("inferred", inferred: true)]
        #expect(figure(.sessionsRun, records) == "2")
        #expect(figure(.cleanFinish, records) == "+2")
        #expect(figure(.total, records) == "+2")
    }

    /// It cannot support gate timings, so an inferred session is kept out of
    /// the answers line on both sides of the fraction.
    @Test
    func backFilledSessionsAreKeptOutOfTheAnswersLine() {
        let watchedOnly = [record("watched", gates: 1, meanLatency: 5, worstLatency: 5)]
        let plusInferred = watchedOnly + [record("inferred", inferred: true)]
        #expect(figure(.answeredInTime, plusInferred) == figure(.answeredInTime, watchedOnly))
        #expect(receipt(plusInferred).line(.answeredInTime)?.note == "of 1 asked")
    }

    /// And the guard is on *provenance*, not on whether the fields happen to be
    /// empty. Today's back-fill writes no latencies at all, so a filter that
    /// only checked for absence would pass the test above by accident and stop
    /// holding the day inference learned to estimate an answer time. A latency
    /// nobody observed is not an answer however plausible it looks.
    @Test
    func aLatencyThatWasInferredRatherThanObservedIsStillNotAnAnswer() {
        let watchedOnly = [record("watched", gates: 1, meanLatency: 5, worstLatency: 5)]
        let plusGuessed = watchedOnly + [
            record("guessed", gates: 2, meanLatency: 2, worstLatency: 2, inferred: true),
        ]
        #expect(figure(.answeredInTime, plusGuessed) == "1")
        #expect(receipt(plusGuessed).line(.answeredInTime)?.note == "of 1 asked")
    }

    /// And the gap is printed rather than swallowed: the receipt says how many
    /// of the day's sessions it only inferred, so the answers line reading
    /// "of 1 asked" under "Sessions run 3" is explained on the paper.
    @Test
    func theReceiptSaysHowManySessionsItOnlyInferred() {
        let records = [record("a"), record("b", inferred: true), record("c", inferred: true)]
        #expect(receipt(records).line(.sessionsRun)?.note == "2 unwatched")
    }

    @Test
    func aFullyWatchedDayCarriesNoUnwatchedNote() {
        #expect(receipt([record("a"), record("b")]).line(.sessionsRun)?.note == nil)
    }

    // MARK: - Typesetting

    /// Every duration on the receipt is the island's one duration vocabulary,
    /// not a fourth formatter that can round differently from the strip and the
    /// detail band.
    @Test
    func durationsUseTheSharedGrain() {
        for seconds in [30.0, 90.0, 59 * 60.0, 3 * 3_600.0, 50 * 3_600.0] {
            let records = [record("run", durationSeconds: seconds)]
            #expect(figure(.bestRun, records) == IslandDurationGrain(seconds: seconds).badge)
        }
    }

    /// Signs and dashes are printer's marks. Read aloud they are noise, so
    /// every line carries a spoken figure that says the thing in words.
    @Test
    func spokenFiguresNeverReadOutPunctuation() {
        let records = [
            record("a", durationSeconds: 40 * 60, gates: 1, meanLatency: 3, worstLatency: 3),
            record("b", interrupted: true),
        ]
        for line in receipt(records).lines + receipt([]).lines {
            #expect(!line.spokenFigure.contains("+"))
            #expect(!line.spokenFigure.contains("-"))
            #expect(!line.spokenFigure.contains(IslandDetailBand.absentBadge))
            #expect(!line.spokenFigure.isEmpty)
        }
    }

    /// The receipt names its own day, in the same time zone it counted the day
    /// in — a header dated by the device while the arithmetic used UTC would
    /// put the wrong date on a correct receipt.
    @Test
    func theHeaderIsDatedInTheCalendarTheDayWasCountedIn() {
        #expect(receipt([]).dateLine == "TUE 14 NOV 2023")
    }

    // MARK: - Fitting the band

    /// A till roll is paper lying on the panel, not a pane filling it, so it is
    /// narrower than the band at both widths the island is drawn at.
    @Test
    func thePaperFitsInsideBothPanelWidths() {
        for width in [540.0, 520.0] as [CGFloat] {
            let printed = receipt([], width: width)
            #expect(printed.paperWidth <= width - Receipt.horizontalInset * 2)
            #expect(printed.paperWidth > 0)
            #expect(printed.paperWidth < width)
        }
    }

    /// Narrow enough and the paper gives up its margins rather than overrunning
    /// the band — nothing here may draw outside the panel.
    @Test
    func aNarrowBandShrinksThePaperRatherThanOverflowing() {
        let printed = receipt([], width: 200)
        #expect(printed.paperWidth <= 200 - Receipt.horizontalInset * 2)
    }

    /// Height is derived from what is printed, so the panel can reserve the
    /// right space without rendering first.
    @Test
    func heightGrowsByExactlyOneRowWhenANoteIsPrinted() {
        let plain = receipt([record("a")])
        let noted = receipt([record("a"), record("b", inferred: true)])
        #expect(noted.height == plain.height + Receipt.noteHeight)
    }

    @Test
    func anEmptyReceiptIsStillTallEnoughToReadAsPaper() {
        #expect(receipt([]).height > Receipt.tornEdgeHeight * 2)
    }
}

/// The receipt is the one island surface that inverts the panel: dark ink on
/// light stock. That makes every colour on it a fresh contrast problem, and the
/// project's rule is that contrast is a test rather than a design review.
struct ReceiptPaperTests {
    private func contrast(_ colour: CreatureColor) -> Double {
        CreatureColor.contrastRatio(colour, IslandDesignPalette.Paper.stock)
    }

    /// 4.5:1 is the body-text bar, and every mark on this paper is body text or
    /// smaller.
    @Test
    func everyMarkOnThePaperClearsBodyTextContrast() {
        for ink in [
            IslandDesignPalette.Paper.ink,
            IslandDesignPalette.Paper.credit,
            IslandDesignPalette.Paper.debit,
            IslandDesignPalette.Paper.faint,
        ] {
            #expect(contrast(ink) >= 4.5)
        }
    }

    /// Credit and debit are peers in a ledger, so they are set to one luminance
    /// and differ only in hue. That is also precisely why the amount column is
    /// signed: at equal value the two are one colour in greyscale, and the
    /// `+`/`-` is what a colour-blind reader has instead.
    @Test
    func creditAndDebitCarryEqualWeightAndDifferOnlyInHue() {
        let credit = IslandDesignPalette.Paper.credit
        let debit = IslandDesignPalette.Paper.debit
        #expect(abs(credit.relativeLuminance - debit.relativeLuminance) < 0.005)
        #expect(credit != debit)
    }

    /// The stock is the app's paper, not a second cream invented for one view.
    @Test
    func theStockIsThePanelsOwnPaperRatherThanASecondCream() {
        #expect(IslandDesignPalette.Paper.stock == CreatureColor(red: 0xF1, green: 0xEA, blue: 0xD9))
    }
}
