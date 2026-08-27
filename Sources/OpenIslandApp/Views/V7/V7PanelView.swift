import SwiftUI
import OpenIslandCore

/// The expanded v7 panel: 560 × 560pt, dark, hanging from the notch.
///
/// Content stays 46pt clear of the left and right edges — the notch shape
/// masks 22pt each side, plus 24pt of breathing room. The geometry is fixed
/// and nothing may be designed narrower.
///
/// Tab order is Sessions · Usage · Pet · Rules (board 5a), reached from four
/// hand-lettered words in the four corners rather than a tab bar.
struct V7PanelView: View {
    var model: AppModel
    /// Ships-today count and the earned shelf. Supplied by the caller so the
    /// Pet room can be driven by real outcomes once they are recorded.
    var board: V7BoardState

    @State private var selection: V7Tab = .sessions

    var body: some View {
        // One shared clock. Elapsed times are relative, so they need a
        // periodic nudge — but every row must read from the same instant or
        // the list disagrees with itself mid-render.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let sessions = model.islandListSessions
            let attention = sessions.filter(\.phase.requiresAttention).count

            V7PanelChrome(
                selection: $selection,
                attentionCount: attention,
                labelsOverArt: selection == .pet
            ) {
                content(sessions: sessions, referenceDate: now)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(V7Tokens.Ground.ink)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func content(sessions: [AgentSession], referenceDate: Date) -> some View {
        switch selection {
        case .sessions:
            // A genuine escalation takes over the Sessions surface rather than
            // becoming a louder row. Everything else stays visible behind it.
            if let critical = sessions.first(where: \.v7IsCriticalEscalation) {
                V7EscalationView(
                    model: model,
                    session: critical,
                    otherSessions: sessions.filter { $0.id != critical.id },
                    heldAgo: critical.spotlightAgeBadge,
                    holdPath: board.holdPath(for: critical)
                )
            } else {
                V7SessionsTab(
                    model: model,
                    sessions: sessions,
                    referenceDate: referenceDate,
                    stats: board.stats
                )
            }

        case .usage:
            V7UsageTab(model: model, sessions: sessions, referenceDate: referenceDate)

        case .pet:
            V7PetTab(
                mood: V7CompanionMood.forFleet(
                    sessions: sessions,
                    shippedRecently: board.shippedToday > 0
                ),
                shippedToday: board.shippedToday,
                recap: board.recap,
                shelf: board.shelf
            )
            // The room runs to the panel edges, so it opts out of the
            // chrome's side inset. The corner labels still sit inside it.
            .padding(.horizontal, -V7Tokens.Rhythm.sideInset)
            .padding(.top, -V7Tokens.Panel.headerHeight)
            .padding(.bottom, -V7Tokens.Panel.footerHeight)

        case .rules:
            V7RulesTab(rules: board.rules)
        }
    }
}

// MARK: - Board state

/// The product state the v7 board designs but the app does not record yet.
///
/// Ships today, the earned shelf, the weekly recap, the concierge's handled
/// counter and the rules model are all **new state**. None of it exists in
/// `AppModel` — there is no store for auto-approvals, no leash persistence and
/// no ship ledger — so it is gathered here behind one explicit type rather
/// than scattered as literals through the views.
///
/// The default is empty, and every surface that reads it degrades to an honest
/// empty state. That is deliberate: a fabricated "214 handled this week" would
/// undermine exactly the trust these screens exist to earn.
///
/// ``V7BoardState/preview`` carries the board's own sample data for design
/// review, and is the only place those numbers appear.
struct V7BoardState: Equatable {
    var shippedToday: Int = 0
    var stats: V7ConciergeStats = .empty
    var rules: V7RulesModel = .empty
    var recap: V7RecapSummary?
    var shelf: [V7ShelfItem] = []
    /// Where a held turn's diff was saved, keyed by session id.
    var holds: [String: String] = [:]

    func holdPath(for session: AgentSession) -> String? {
        holds[session.id]
    }

    static let empty = V7BoardState()
}

extension V7BoardState {
    /// The board's sample data, for design review and previews only.
    ///
    /// Never use this as a fallback for missing real state — showing these
    /// numbers to a user would be a lie about what the concierge has done.
    static let preview = V7BoardState(
        shippedToday: 3,
        stats: V7ConciergeStats(
            handledThisWeek: 214,
            escalatedThisWeek: 12,
            entries: [
                .init(text: "Held rudderfish's force-push and paused the session.", age: "40s"),
                .init(text: "Approved 12 file reads in reelle-ios. Nothing looked unusual.", age: "2m"),
                .init(text: "Ran swift build in open-vibe-island, six times, all clean.", age: "26m"),
            ]
        ),
        rules: V7RulesModel(
            leashes: [
                .init(repo: "reelle-ios", slack: 0.95, note: "loose · 41 auto this wk"),
                .init(repo: "open-vibe-island", slack: 0.78, note: "builds & reads pass"),
                .init(repo: "zhende", slack: 0.5, note: "asks before edits"),
                .init(repo: "rudderfish", slack: 0.08, note: "escalates everything"),
            ],
            patterns: [
                .init(pattern: "Read **/*", scope: "everywhere", enabled: true),
                .init(pattern: "Edit src/**", scope: "reelle-ios", enabled: true),
                .init(pattern: "npm test", scope: "everywhere", enabled: true),
            ],
            quietHoursEnabled: true,
            quietHoursNote: "until 2:00 pm — critical still comes through",
            batchInterval: "every 25m",
            escalationSound: false
        ),
        recap: V7RecapSummary(
            dateRange: "AUG 17–23",
            lines: [
                .init(label: "turns shipped", value: "+9", tone: .gain),
                .init(label: "prs merged", value: "+4", tone: .gain),
                .init(label: "interruptions handled", value: "+214", tone: .gain),
                .init(label: "escalated to you", value: "12", tone: .neutral),
                .init(label: "lines, net", value: "+3,841", tone: .gain),
                .init(label: "rolled back", value: "−2", tone: .loss),
            ],
            total: 221
        ),
        shelf: [
            .init(id: "crown", label: "paper crown", requirement: "3-ship day", earned: true, object: .star),
            .init(id: "monstera", label: "tiny monstera", requirement: "7-day streak", earned: true, object: .plant),
            .init(id: "mug", label: "studio mug", requirement: "100 turns", earned: true, object: .mug),
            .init(id: "cup", label: "brass cup", requirement: "2 ships away", earned: false, object: .ball),
        ]
    )
}
