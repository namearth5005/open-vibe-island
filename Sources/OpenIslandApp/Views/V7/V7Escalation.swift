import SwiftUI
import OpenIslandCore

/// **A critical escalation** — board 05, and the hardest state in the product.
///
/// The question it answers is how *"you really need to look at this"* reads
/// without panic. The answer is that **the hold has already happened**. The
/// session is paused, the diff is kept, nothing was pushed — so the screen is
/// reporting a safe state, not begging for a rescue. Urgency with no time
/// pressure.
///
/// What that buys, concretely:
///
/// - One clay seat. Everything else on the list **dims but stays** — the fleet
///   is still legible, so the user can see this is one session out of ten.
/// - No red wash, no pulse, no sound, no auto-expand. The pill asks first; a
///   human opens the panel.
/// - The companion points. It does not plead, and it never blocks the copy.
struct V7EscalationView: View {
    var model: AppModel
    var session: AgentSession
    /// The rest of the fleet, rendered dimmed behind the seat.
    var otherSessions: [AgentSession]
    var heldAgo: String
    /// Where the paused work is kept. Naming the path is what makes "nothing
    /// left the machine" a checkable claim rather than reassurance.
    var holdPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: V7Tokens.Rhythm.titleToMeta) {
                Text("\(session.spotlightWorkspaceName) needs you.")
                    .font(V7Tokens.Typeface.hand(size: 19))
                    .foregroundStyle(V7Tokens.Text.primary)
                    .lineLimit(1)
                Text("held \(heldAgo) · the rest of the fleet is fine")
                    .font(V7Tokens.Typeface.mono(size: 9.5))
                    .foregroundStyle(V7Tokens.Text.tertiary)
            }

            seat.padding(.top, 2)

            // Dimmed, not hidden. Removing the rest would make this feel like
            // an alert took over the machine.
            VStack(alignment: .leading, spacing: 5) {
                ForEach(otherSessions.prefix(5)) { other in
                    HStack(spacing: 8) {
                        Text(other.v7Headline)
                            .font(V7Tokens.Typeface.ui(size: 12))
                            .foregroundStyle(V7Tokens.Text.onCard)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(other.v7Meta)
                            .font(V7Tokens.Typeface.mono(size: 9))
                            .foregroundStyle(V7Tokens.Text.onCardMuted)
                            .lineLimit(1)
                            .layoutPriority(-1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background {
                        RoundedRectangle(cornerRadius: V7Tokens.Radius.row, style: .continuous)
                            .fill(Color.white.opacity(0.9))
                    }
                }
            }
            .opacity(0.35)
            .padding(.top, 4)
            .allowsHitTesting(false)

            Spacer(minLength: 0)
        }
    }

    private var seat: some View {
        V7Seat(seat: .clay, padding: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                // Anxious is the pointing silhouette — a shape difference, not
                // an expression, so it still reads at a glance.
                V7CompanionView(mood: .anxious, bodyTreatment: .dark)
                    .frame(width: 76, height: 47)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 5) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text("HELD · NEEDS YOU")
                            .font(V7Tokens.Typeface.mono(size: 9))
                            .tracking(0.8)
                    }
                    .foregroundStyle(V7Tokens.Text.onClay)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(V7Tokens.Ground.ink.opacity(0.16))
                    }

                    Text(headline)
                        .font(V7Tokens.Typeface.ui(size: 15.5, weight: .bold))
                        .foregroundStyle(V7Tokens.Text.onClay)
                        .lineLimit(2)
                        .padding(.top, 6)

                    // Explains and directs. Never apologises, never goes vague.
                    Text(explanation)
                        .font(V7Tokens.Typeface.ui(size: 12.5))
                        .foregroundStyle(V7Tokens.Text.onSeat)
                        .lineLimit(3)
                        .padding(.top, 4)

                    HStack(spacing: 8) {
                        Button("Look now") {
                            model.jumpToSession(session)
                        }
                        .buttonStyle(
                            V7ScribbleButtonStyle(
                                tint: V7Tokens.Ground.ink,
                                scribble: V7Tokens.Accent.scribbleOnSeat
                            )
                        )

                        Button("Keep holding") {
                            // Deliberately a no-op on the model: the session is
                            // already paused, so "keep holding" is the state
                            // the user is already in. It exists to make that
                            // legible — and to be an answer that is not "act".
                        }
                        .buttonStyle(
                            V7OutlineButtonStyle(tint: V7Tokens.Text.onClay, borderOpacity: 0.4)
                        )

                        Button("Deny the turn") {
                            model.approvePermission(for: session.id, action: .deny)
                        }
                        .buttonStyle(
                            V7OutlineButtonStyle(tint: V7Tokens.Text.onClay, borderOpacity: 0.4)
                        )

                        Spacer(minLength: 0)
                    }
                    .padding(.top, 10)

                    if let holdPath {
                        Text("diff saved · \(holdPath) · nothing left the machine")
                            .font(V7Tokens.Typeface.mono(size: 8.5))
                            .foregroundStyle(V7Tokens.Text.onClay.opacity(0.75))
                            .lineLimit(1)
                            .padding(.top, 8)
                    }
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
        }
    }

    /// What it wants, in its own words.
    private var headline: String {
        if let request = session.permissionRequest {
            return request.title.isEmpty ? session.v7Headline : request.title
        }
        return session.v7Headline
    }

    /// Why it is held, and what the concierge did about it.
    private var explanation: String {
        if let summary = session.permissionRequest?.summary, !summary.isEmpty {
            return "\(summary) I paused it and kept the diff — nothing was pushed."
        }
        return "I paused it and kept the diff — nothing was pushed."
    }
}

// MARK: - What counts as critical

extension AgentSession {
    /// Whether this session warrants the clay seat rather than the rose one.
    ///
    /// Kept narrow on purpose. If everything can be critical then nothing
    /// reads as critical, and the escalation stops meaning anything — which
    /// is precisely the failure this screen exists to avoid.
    var v7IsCriticalEscalation: Bool {
        guard let request = permissionRequest else { return false }

        // The app already models one hard line: a prompt the agent cannot
        // resolve without the terminal is one the concierge cannot absorb.
        if request.requiresTerminalApproval { return true }

        let haystack = "\(request.title) \(request.summary) \(request.affectedPath)".lowercased()
        return V7CriticalPatterns.all.contains { haystack.contains($0) }
    }
}

/// Operations that are never routine, whatever the leash says.
///
/// These mirror the Rules tab's locked row: some things always ask, and are
/// not a setting.
enum V7CriticalPatterns {
    static let all = [
        "push --force",
        "push -f",
        "reset --hard",
        "rm -rf",
        "drop table",
        "force-push",
        "git clean -fd",
    ]
}
