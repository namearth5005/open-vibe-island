import Foundation
import OpenIslandCore

/// Which unit a duration rounded down to, and the two ways the island says it.
///
/// The badge and the sentence are one decision rendered twice — once for a 26pt
/// column, once for a voice — so they are derived from a single grain rather
/// than from two formatters that can drift apart. "12m" read aloud is "twelve
/// em", which is why the spoken form exists at all.
enum IslandDurationGrain: Equatable, Sendable {
    case underAMinute
    case minutes(Int)
    case hours(Int)
    case days(Int)

    init(seconds: TimeInterval) {
        // A clock adjustment must not produce a negative age, and the floor of
        // one is what keeps "59 minutes" from rendering as "0h".
        let value = max(0, Int(seconds))
        switch value {
        case ..<60:
            self = .underAMinute
        case ..<3_600:
            self = .minutes(max(1, value / 60))
        case ..<86_400:
            self = .hours(max(1, value / 3_600))
        default:
            self = .days(max(1, value / 86_400))
        }
    }

    var badge: String {
        switch self {
        case .underAMinute: "<1m"
        case let .minutes(value): "\(value)m"
        case let .hours(value): "\(value)h"
        case let .days(value): "\(value)d"
        }
    }

    var spoken: String {
        switch self {
        case .underAMinute: "less than a minute"
        case let .minutes(value): value == 1 ? "1 minute" : "\(value) minutes"
        case let .hours(value): value == 1 ? "1 hour" : "\(value) hours"
        case let .days(value): value == 1 ? "1 day" : "\(value) days"
        }
    }
}

enum SpotlightActivityTone {
    case live
    case idle
    case ready
    case attention
}

enum IslandSessionPresence: Equatable {
    case running
    case active
    case inactive
}

extension AgentSession {
    private static let collapsedDetailAgeThreshold: TimeInterval = 20 * 60
    private static let islandActivityThreshold: TimeInterval = 20 * 60
    static let staleCompletedDisplayThreshold: TimeInterval = 5 * 60

    /// Whether this session represents a subagent (worktree agent) that should
    /// not appear as a separate entry in the session list.  The parent session
    /// already tracks subagents via `claudeMetadata.activeSubagents`.
    ///
    /// Note: `claudeMetadata.agentID` is NOT a reliable signal here because
    /// SubagentStart hooks set `agent_id` on the *parent* session's metadata.
    var isSubagentSession: Bool {
        if let path = claudeMetadata?.transcriptPath, path.contains("/subagents/") {
            return true
        }
        return false
    }

    var islandActivityDate: Date {
        updatedAt
    }

    /// What this session is blocked on, or `nil` while it just works.
    ///
    /// Named rather than inlined because the island's detail band needs the
    /// *presence* of a question, not only its text: a pending question is the
    /// one thing on that row worth colouring. Reading it out of the same two
    /// fields `spotlightPrimaryText` leads with keeps the band and the panel's
    /// cards from ever quoting a session differently.
    var islandPendingQuestion: String? {
        if let request = permissionRequest {
            return request.summary
        }

        if let prompt = questionPrompt {
            return prompt.title
        }

        return nil
    }

    var spotlightPrimaryText: String {
        if let pending = islandPendingQuestion {
            return pending
        }

        if let assistantMessage = lastAssistantMessageText?.trimmedForSurface,
           !assistantMessage.isEmpty {
            return assistantMessage
        }

        return summary
    }

    var spotlightSecondaryText: String? {
        if let request = permissionRequest {
            return request.affectedPath.isEmpty ? nil : request.affectedPath
        }

        if let currentTool = displayCurrentToolName {
            return phase == .completed
                ? summary
                : "Running \(currentTool)"
        }

        let normalizedPrimary = spotlightPrimaryText.trimmedForSurface
        let normalizedSummary = summary.trimmedForSurface
        guard normalizedSummary != normalizedPrimary else {
            return nil
        }

        return summary
    }

    var spotlightCurrentToolLabel: String? {
        displayCurrentToolName
    }

    var spotlightTrackingLabel: String? {
        guard let transcriptPath = trackingTranscriptPath?.trimmedForSurface,
              !transcriptPath.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: transcriptPath).lastPathComponent
    }

    var spotlightStatusLabel: String {
        switch phase {
        case .running:
            if let currentTool = spotlightCurrentToolLabel {
                return "Live · \(currentTool)"
            }
            return "Live"
        case .waitingForApproval:
            return "Approval"
        case .waitingForAnswer:
            return "Question"
        case .completed:
            return jumpTarget != nil ? "Idle" : "Completed"
        }
    }

    var spotlightTerminalLabel: String? {
        guard let jumpTarget else {
            return nil
        }

        return "\(jumpTarget.terminalApp) · \(jumpTarget.workspaceName)"
    }

    var spotlightTerminalBadge: String? {
        jumpTarget?.terminalApp
    }

    var spotlightWorkspaceName: String {
        if let workspaceName = jumpTarget?.workspaceName.trimmedForSurface,
           !workspaceName.isEmpty {
            return workspaceName
        }

        let trimmedTitle = title.trimmedForSurface
        let pieces = trimmedTitle.split(separator: "·", maxSplits: 1).map {
            String($0).trimmedForSurface
        }
        if pieces.count == 2, !pieces[1].isEmpty {
            return pieces[1]
        }

        return trimmedTitle
    }

    var spotlightWorktreeBranch: String? {
        // This is a SwiftUI computed property read on every layout
        // pass. It MUST stay free of filesystem IO. Calling
        // `WorkspaceNameResolver.gitBranch` here previously walked
        // parent directories every layout, which combined with
        // SwiftUI's measure/layout convergence cycle pinned the
        // process at 99 % CPU during session-list rendering even
        // with the resolver result cached.
        //
        // Read order: hook-supplied metadata wins (already resolved
        // by `BridgeServer` from the hook payload), then the pure
        // string-based worktree-path detector (no IO). Other
        // sessions surface the workspace name without a branch
        // suffix; for branch info on arbitrary `cwd` values to
        // come back, it has to be resolved when the session is
        // created or updated, not from the view body.
        if let branch = claudeMetadata?.worktreeBranch?.trimmedForSurface,
           !branch.isEmpty {
            return branch
        }

        guard let workingDirectory = jumpTarget?.workingDirectory?.trimmedForSurface,
              !workingDirectory.isEmpty else {
            return nil
        }

        return WorkspaceNameResolver.worktreeBranch(for: workingDirectory)
    }

    var spotlightSubagentLabel: String? {
        guard let subagents = claudeMetadata?.activeSubagents, !subagents.isEmpty else {
            return nil
        }
        return "Subagents (\(subagents.count))"
    }

    var spotlightHeadlineText: String {
        var headline = spotlightWorkspaceName

        if let branch = spotlightWorktreeBranch {
            headline += " (\(branch))"
        }

        guard let prompt = spotlightHeadlinePromptText else {
            return headline
        }

        return "\(headline) · \(prompt)"
    }

    var spotlightHeadlinePromptText: String? {
        // Headline shows the initial prompt (session topic), not the latest.
        // The latest prompt is shown separately in the "You:" line.
        initialPromptText ?? latestPromptText
    }

    var spotlightPromptText: String? {
        latestPromptText
    }

    var spotlightPromptLineText: String? {
        guard spotlightShowsDetailLines,
              let prompt = spotlightPromptText else {
            return nil
        }

        return "You: \(prompt)"
    }

    var completionReplyRecipientName: String {
        switch tool {
        case .claudeCode:
            return "Claude"
        case .codex:
            return "Codex"
        case .geminiCLI:
            return "Gemini"
        case .openCode:
            return "OpenCode"
        case .qoder:
            return "Qoder"
        case .qwenCode:
            return "Qwen Code"
        case .factory:
            return "Factory"
        case .codebuddy:
            return "CodeBuddy"
        case .cursor:
            return "Cursor"
        case .kimiCLI:
            return "Kimi"
        }
    }

    var notificationHeaderPromptLineText: String? {
        guard phase != .completed else {
            return nil
        }

        return spotlightPromptLineText
    }

    var spotlightActivityLineText: String? {
        guard spotlightShowsDetailLines else {
            return nil
        }

        if let request = permissionRequest?.summary.trimmedForSurface,
           !request.isEmpty {
            return request
        }

        if let prompt = questionPrompt?.title.trimmedForSurface,
           !prompt.isEmpty {
            return prompt
        }

        switch phase {
        case .running:
            if let activity = spotlightRunningActivityText {
                return activity
            }
            return spotlightPromptLineText == nil ? "Running" : "Thinking"
        case .waitingForApproval:
            return permissionRequest?.summary.trimmedForSurface ?? "Approval needed"
        case .waitingForAnswer:
            return questionPrompt?.title.trimmedForSurface ?? "Answer needed"
        case .completed:
            if let assistantMessage = lastAssistantMessageText?.trimmedForSurface,
               !assistantMessage.isEmpty {
                return assistantMessage
            }

            return jumpTarget != nil ? "Ready" : "Completed"
        }
    }

    var spotlightActivityTone: SpotlightActivityTone {
        if phase.requiresAttention {
            return .attention
        }

        switch phase {
        case .running:
            return .live
        case .completed:
            if lastAssistantMessageText?.trimmedForSurface.isEmpty == false {
                return .idle
            }
            return .ready
        case .waitingForApproval, .waitingForAnswer:
            return .attention
        }
    }

    var spotlightShowsDetailLines: Bool {
        spotlightShowsDetailLines(at: .now)
    }

    func spotlightShowsDetailLines(at referenceDate: Date) -> Bool {
        if phase == .running || phase.requiresAttention {
            return true
        }

        if referenceDate.timeIntervalSince(islandActivityDate) >= Self.collapsedDetailAgeThreshold {
            return false
        }

        return spotlightPromptText != nil || lastAssistantMessageText?.trimmedForSurface.isEmpty == false
    }

    var spotlightAgeBadge: String {
        IslandDurationGrain(seconds: Date.now.timeIntervalSince(islandActivityDate)).badge
    }

    /// How long this session has been going.
    ///
    /// Measured from `firstSeenAt`, not from the last event, because the island
    /// strip answers "which session is this" rather than "what just happened" —
    /// a run you started this morning stays an hours-old run even when it
    /// printed a line a second ago.
    ///
    /// A finished session stops at its last event. Letting it keep counting
    /// would report work that is not happening.
    func islandElapsed(at referenceDate: Date) -> TimeInterval {
        let endpoint = phase == .completed ? updatedAt : referenceDate
        return max(0, endpoint.timeIntervalSince(firstSeenAt))
    }

    func islandPresence(at referenceDate: Date) -> IslandSessionPresence {
        if phase == .running {
            return .running
        }

        if phase.requiresAttention {
            return .active
        }

        if referenceDate.timeIntervalSince(islandActivityDate) <= Self.islandActivityThreshold {
            return .active
        }

        return .inactive
    }

    /// v8 UI-only staleness: keep `SessionPhase.completed` unchanged, but
    /// visually fold older completed rows into the low-priority presentation.
    func isStaleCompletedForIsland(
        at referenceDate: Date,
        threshold: TimeInterval = Self.staleCompletedDisplayThreshold
    ) -> Bool {
        phase == .completed
            && referenceDate.timeIntervalSince(islandActivityDate) >= threshold
    }

    private var spotlightRunningActivityText: String? {
        guard let currentTool = currentToolName?.trimmedForSurface,
              !currentTool.isEmpty else {
            return nil
        }

        let label = Self.currentToolDisplayName(for: currentTool)
        guard let preview = currentCommandPreviewText?.trimmedForSurface,
              !preview.isEmpty else {
            return label
        }

        return "\(label) \(preview)"
    }

    var displayCurrentToolName: String? {
        guard let currentTool = currentToolName?.trimmedForSurface,
              !currentTool.isEmpty else {
            return nil
        }

        return Self.currentToolDisplayName(for: currentTool)
    }

    static func currentToolDisplayName(for toolName: String) -> String {
        switch toolName {
        case "exec_command":
            return "Bash"
        case "Bash":
            return "Bash"
        case "AskUserQuestion":
            return "Question"
        case "ExitPlanMode":
            return "Plan"
        case "apply_patch":
            return "Patch"
        case "write_stdin":
            return "Input"
        case "web_search", "tool_search":
            return "Search"
        case "image_generation", "view_image":
            return "Image"
        case "context_compaction":
            return "Compact"
        case "update_plan":
            return "Plan"
        case "request_user_input":
            return "Question"
        case "spawn_agent":
            return "Subagent"
        default:
            return humanizedToolName(toolName)
        }
    }

    private static func humanizedToolName(_ toolName: String) -> String {
        let trimmed = toolName.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrivatePrefix = String(trimmed.drop(while: { $0 == "_" }))
        let pieces = withoutPrivatePrefix
            .split(separator: "_", omittingEmptySubsequences: true)
            .map { piece -> String in
                let upper = piece.uppercased()
                if ["API", "CI", "ID", "PR", "URL"].contains(upper) {
                    return upper
                }
                return piece.prefix(1).uppercased() + piece.dropFirst().lowercased()
            }
        let label = pieces.joined(separator: " ")
        return label.isEmpty ? toolName : label
    }

    private var initialPromptText: String? {
        let prompt = initialUserPromptText?.trimmedForSurface
        guard let prompt, !prompt.isEmpty else {
            return nil
        }

        return prompt
    }

    private var latestPromptText: String? {
        let prompt = latestUserPromptText?.trimmedForSurface
        guard let prompt, !prompt.isEmpty else {
            return nil
        }

        return prompt
    }

    private var prefersLivePromptHeadline: Bool {
        isProcessAlive || phase == .running || phase.requiresAttention
    }
}

private extension String {
    var trimmedForSurface: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
