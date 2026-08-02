import Foundation

/// Which body a session's creature wears.
///
/// Six bodies for ten agents: Qoder, Qwen Code, Factory and CodeBuddy are all
/// Claude Code forks sharing its hook format, so they share its body and differ
/// only by marking. They look alike because they are alike.
public enum CreatureSpecies: String, CaseIterable, Sendable {
    case claude
    case codex
    case cursor
    case gemini
    case kimi
    case openCode

    public init(tool: AgentTool) {
        switch tool {
        case .claudeCode, .qoder, .qwenCode, .factory, .codebuddy: self = .claude
        case .codex: self = .codex
        case .cursor: self = .cursor
        case .geminiCLI: self = .gemini
        case .kimiCLI: self = .kimi
        case .openCode: self = .openCode
        }
    }
}
