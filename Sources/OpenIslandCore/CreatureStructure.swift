import Foundation

/// Which structure a session's creature stands at.
///
/// The creature says which agent; the structure says where it is running. Five
/// structures for two dozen hosts, because "where" is a coarser question than
/// "which build" — the nine JetBrains IDEs share one tower for the same reason
/// the Claude Code forks share one body, they are one IDE in nine skins.
///
/// `workshop` is not an error case, it is the answer for a host nobody has
/// taught the app about yet. The identifier arrives as a free-form string from
/// a hook, so unrecognised values are inevitable and a session standing beside
/// nothing would read as a rendering bug rather than as an unknown terminal.
public enum CreatureStructure: String, CaseIterable, Sendable {
    case terminal
    case multiplexer
    case editor
    case tower
    case workshop

    /// Built from `JumpTarget.terminalApp` verbatim — that string is the
    /// identifier the rest of the app already carries, and there is no terminal
    /// enum to key off.
    ///
    /// Matching is deliberately loose because the string is whatever a hook
    /// managed to infer: `TERM_PROGRAM` values, bundle display names and CLI
    /// names all reach here, so `Orca.app`, `orca` and `ORCA` have to land
    /// together, and iTerm2 arrives spelled `iTerm`. The alias set mirrors
    /// `TerminalJumpService.knownApps` on purpose — a host we can jump to is a
    /// host we should be able to draw.
    public init(terminalApp: String) {
        switch Self.normalized(terminalApp) {
        case "terminal", "appleterminal", "ghostty", "iterm", "iterm2",
             "wezterm", "kaku", "cmux", "warp", "warpterminal":
            self = .terminal
        case "tmux", "zellij", "orca":
            self = .multiplexer
        case "vscode", "code", "visualstudiocode", "vscodeinsiders", "codeinsiders",
             "cursor", "windsurf", "trae", "traecn":
            self = .editor
        case "intellij", "intellijidea", "idea", "webstorm", "pycharm", "goland",
             "clion", "rubymine", "phpstorm", "rider", "rustrover":
            self = .tower
        default:
            self = .workshop
        }
    }

    /// Folds away the three ways the same host spells itself: casing, a `.app`
    /// suffix on desktop-hosted agents, and the separators that differ between
    /// a display name (`VS Code`) and its CLI or `TERM_PROGRAM` name
    /// (`vscode`, `apple_terminal`, `vscode-insiders`).
    private static func normalized(_ terminalApp: String) -> String {
        var value = terminalApp.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasSuffix(".app") {
            value.removeLast(4)
        }
        return value.filter { !" -_".contains($0) }
    }
}
