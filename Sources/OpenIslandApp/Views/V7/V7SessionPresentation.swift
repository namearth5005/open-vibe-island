import SwiftUI
import OpenIslandCore

/// How a session reads on the v7 board.
///
/// Kept separate from `AgentSession+Presentation` so the v7 surface can phrase
/// things its own way — the board's copy rules are specific — without
/// disturbing the strings the shipping v6 panel depends on.
extension AgentSession {

    /// The headline: what the agent is actually doing, in its own words.
    ///
    /// The board's rows read `find the cc history and reconcile it` and
    /// `swift build` — the work, not the session's name.
    var v7Headline: String {
        if let prompt = spotlightHeadlinePromptText?.trimmedForSurface, !prompt.isEmpty {
            return prompt
        }
        let trimmedSummary = summary.trimmedForSurface
        if !trimmedSummary.isEmpty {
            return trimmedSummary
        }
        return title.trimmedForSurface
    }

    /// `rudderfish · claude · 17m`, or with a worktree,
    /// `open-vibe-island · feat/companion-pill · claude · <1m`.
    ///
    /// Monospace, because it is data that lines up.
    var v7Meta: String {
        var parts = [spotlightWorkspaceName]
        if let branch = spotlightWorktreeBranch, !branch.isEmpty {
            parts.append(branch)
        }
        parts.append(tool.rawValue == "claudeCode" ? "claude" : tool.shortName.lowercased())
        parts.append(spotlightAgeBadge)
        return parts.joined(separator: " · ")
    }

    /// The meta line with the reason it is waiting appended, for rows that
    /// need a human. Every concierge line names who, what, and why.
    var v7MetaWithReason: String {
        switch phase {
        case .waitingForApproval: "\(v7Meta) — waiting on you"
        case .waitingForAnswer:   "\(v7Meta) — asked you a question"
        default:                  v7Meta
        }
    }

    var v7StatusLabel: String {
        switch phase {
        case .waitingForApproval: "needs decision"
        case .waitingForAnswer:   "question"
        case .running:            "working"
        case .completed:          "done"
        }
    }

    /// Ranked by urgency, not launch order. Ties break on recency so the list
    /// stays stable while agents churn.
    var v7UrgencyRank: Int {
        switch phase {
        case .waitingForApproval: 0
        case .waitingForAnswer:   1
        case .running:            2
        case .completed:          3
        }
    }

    /// Idle: alive but not working and not waiting on anyone. These collapse
    /// to a count — never a row — because nothing that needs the user may
    /// fall below the fold.
    func v7IsIdle(at referenceDate: Date) -> Bool {
        guard !phase.requiresAttention, phase != .running else { return false }
        return referenceDate.timeIntervalSince(islandActivityDate) > 300
    }

    /// The rule the agent itself suggested, phrased for the checkbox row:
    /// *Always allow Read in rudderfish*.
    ///
    /// Accepting it is how the leash loosens, so it has to say plainly what it
    /// will do and where.
    var v7SuggestedRuleLabel: String? {
        guard let request = permissionRequest else { return nil }

        for update in request.suggestedUpdates {
            guard case let .addRules(_, rules, behavior) = update, let rule = rules.first else {
                continue
            }
            let verb = behavior == .deny ? "Always deny" : "Always allow"
            let scope = spotlightWorkspaceName
            if let content = rule.ruleContent?.trimmedForSurface, !content.isEmpty {
                return "\(verb) \(rule.toolName)(\(content)) in \(scope)"
            }
            return "\(verb) \(rule.toolName) in \(scope)"
        }
        return nil
    }

    /// The updates to apply when the user ticks the rule row and allows.
    var v7SuggestedRuleUpdates: [ClaudePermissionUpdate] {
        permissionRequest?.suggestedUpdates ?? []
    }

    /// One-tap answers for a structured question, if the agent offered any.
    var v7AnswerChips: [String] {
        guard let prompt = questionPrompt else { return [] }
        if let first = prompt.questions.first {
            return first.options.filter { !$0.allowsFreeform }.map(\.label)
        }
        return prompt.options
    }
}

// MARK: - Fleet summary

/// The counts behind the headline and its meta line.
struct V7FleetSummary {
    var total = 0
    var needsDecision = 0
    var questions = 0
    var working = 0
    var done = 0
    var idle = 0

    var needsYou: Int { needsDecision + questions }

    init(sessions: [AgentSession], referenceDate: Date = .now) {
        total = sessions.count
        for session in sessions {
            if session.v7IsIdle(at: referenceDate) {
                idle += 1
                continue
            }
            switch session.phase {
            case .waitingForApproval: needsDecision += 1
            case .waitingForAnswer:   questions += 1
            case .running:            working += 1
            case .completed:          done += 1
            }
        }
    }

    /// The two-second read. Names the one thing that matters, and never
    /// inflates it — "All quiet" is a legitimate answer.
    var headline: String {
        switch needsYou {
        case 0 where working > 0: "All quiet — \(working) agent\(working == 1 ? "" : "s") working."
        case 0:                   "Nothing needs you. Go build something."
        case 1:                   "One needs your say."
        default:                  "\(needsYou) need your say."
        }
    }

    /// `10 sessions · 2 need you · 4 working · 2 done · 2 idle`
    var breakdown: String {
        guard total > 0 else { return "no sessions · start an agent in any terminal" }
        var parts = ["\(total) session\(total == 1 ? "" : "s")"]
        if needsYou > 0 { parts.append("\(needsYou) need you") }
        if working > 0  { parts.append("\(working) working") }
        if done > 0     { parts.append("\(done) done") }
        if idle > 0     { parts.append("\(idle) idle") }
        return parts.joined(separator: " · ")
    }

    /// What collapses into the quiet footer row.
    var collapsedLabel: String? {
        var parts: [String] = []
        if done > 0 { parts.append("\(done) done") }
        if idle > 0 { parts.append("\(idle) idle") }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ") + " — collapsed"
    }
}
