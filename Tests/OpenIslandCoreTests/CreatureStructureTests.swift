import Testing
@testable import OpenIslandCore

struct CreatureStructureTests {
    @Test
    func thereAreExactlyFiveStructures() {
        #expect(CreatureStructure.allCases.count == 5)
    }

    @Test
    func terminalEmulatorsStandAtATerminal() {
        for app in ["Terminal", "Ghostty", "iTerm", "iTerm2", "WezTerm", "Kaku", "cmux", "Warp"] {
            #expect(CreatureStructure(terminalApp: app) == .terminal, "\(app)")
        }
    }

    @Test
    func multiplexersStandAtAMultiplexer() {
        for app in ["tmux", "Zellij", "Orca.app"] {
            #expect(CreatureStructure(terminalApp: app) == .multiplexer, "\(app)")
        }
    }

    @Test
    func vsCodeFamilyEditorsStandAtAnEditor() {
        for app in ["VS Code", "VS Code Insiders", "Cursor", "Windsurf", "Trae"] {
            #expect(CreatureStructure(terminalApp: app) == .editor, "\(app)")
        }
    }

    /// Nine JetBrains IDEs, one tower — the same reason four Claude Code forks
    /// share one creature body. Telling RubyMine from GoLand at pill scale is
    /// not a distinction anyone can make or wants to.
    @Test
    func everyJetBrainsIDEStandsAtTheSameTower() {
        for app in [
            "IntelliJ IDEA", "WebStorm", "PyCharm", "GoLand", "CLion",
            "RubyMine", "PhpStorm", "Rider", "RustRover",
        ] {
            #expect(CreatureStructure(terminalApp: app) == .tower, "\(app)")
        }
    }

    /// Why this returns a structure rather than an optional: a host nobody has
    /// taught the app about still has a live session standing in it, and an
    /// empty plot next to a creature reads as a rendering bug rather than as
    /// "unknown terminal".
    @Test
    func unrecognisedHostsStillGetAStructure() {
        for app in ["Hyper", "Alacritty", "Unknown", "Codex.app", "Claude.app", "", "   "] {
            #expect(CreatureStructure(terminalApp: app) == .workshop, "\(app)")
        }
    }

    /// `terminalApp` is whatever a hook stamped, not a curated value: Orca
    /// arrives with a `.app` suffix, iTerm2 arrives as `iTerm`, `TERM_PROGRAM`
    /// casing is the terminal author's choice, and the VS Code family answers
    /// to its CLI name as readily as its display name.
    @Test
    func matchingIgnoresCaseSpacingAndTheAppSuffix() {
        #expect(CreatureStructure(terminalApp: "orca.app") == .multiplexer)
        #expect(CreatureStructure(terminalApp: "ORCA") == .multiplexer)
        #expect(CreatureStructure(terminalApp: "iTerm.app") == .terminal)
        #expect(CreatureStructure(terminalApp: "apple_terminal") == .terminal)
        #expect(CreatureStructure(terminalApp: "  Ghostty  ") == .terminal)
        #expect(CreatureStructure(terminalApp: "vscode") == .editor)
        #expect(CreatureStructure(terminalApp: "visual studio code") == .editor)
        #expect(CreatureStructure(terminalApp: "intellij") == .tower)
    }

    /// The input is an open string, so — unlike `CreatureSpecies` — the compiler
    /// guarantees nothing here. A structure no identifier can reach is shipped
    /// artwork that never renders, which nothing else in the build notices.
    @Test
    func noStructureIsOrphaned() {
        let reached = Set(
            ["Terminal", "tmux", "VS Code", "GoLand", "Hyper"]
                .map { CreatureStructure(terminalApp: $0) }
        )
        let orphans = Set(CreatureStructure.allCases).subtracting(reached)
        #expect(orphans.isEmpty, "no identifier maps to \(orphans.map(\.rawValue).sorted())")
    }
}
