import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// Orca hosts Claude Code in panes as a TTY-less subprocess, so none of the
/// usual pane handles exist and `ORCA_PANE_KEY` is the only way to tell one
/// pane from another. These cover the resolution from that key to the
/// runtime-issued handle `orca terminal switch` needs.
struct OrcaPaneJumpTests {
    private func terminal(
        handle: String,
        tabId: String? = nil,
        leafId: String? = nil,
        worktreePath: String? = nil
    ) -> TerminalJumpService.OrcaTerminal {
        // Decoded rather than constructed: OrcaTerminal is a Decodable wire type
        // with no memberwise init, and going through JSON also pins the field
        // names against Orca's actual output.
        var object: [String: Any] = ["handle": handle]
        if let tabId { object["tabId"] = tabId }
        if let leafId { object["leafId"] = leafId }
        if let worktreePath { object["worktreePath"] = worktreePath }
        let data = try! JSONSerialization.data(withJSONObject: object)
        return try! JSONDecoder().decode(TerminalJumpService.OrcaTerminal.self, from: data)
    }

    private func target(paneKey: String? = nil, cwd: String? = nil) -> JumpTarget {
        JumpTarget(
            terminalApp: "Orca.app",
            workspaceName: "rudderfish",
            paneTitle: "Terminal 1",
            workingDirectory: cwd,
            orcaPaneKey: paneKey
        )
    }

    // MARK: - Pane key

    @Test
    func paneKeyResolvesToTheMatchingHandle() {
        let terminals = [
            terminal(handle: "term_aaa", tabId: "tab-1", leafId: "leaf-1"),
            terminal(handle: "term_bbb", tabId: "tab-1", leafId: "leaf-2"),
            terminal(handle: "term_ccc", tabId: "tab-2", leafId: "leaf-3"),
        ]
        let handle = TerminalJumpService.matchOrcaHandle(
            target: target(paneKey: "tab-1:leaf-2"), terminals: terminals
        )
        #expect(handle == "term_bbb")
    }

    /// The whole point of the feature: several panes sharing a tab must resolve
    /// to different handles, or the jump lands on whichever was last visible.
    @Test
    func panesSharingATabAreDistinguishedByLeaf() {
        let terminals = [
            terminal(handle: "term_aaa", tabId: "tab-1", leafId: "leaf-1"),
            terminal(handle: "term_bbb", tabId: "tab-1", leafId: "leaf-2"),
        ]
        let first = TerminalJumpService.matchOrcaHandle(
            target: target(paneKey: "tab-1:leaf-1"), terminals: terminals
        )
        let second = TerminalJumpService.matchOrcaHandle(
            target: target(paneKey: "tab-1:leaf-2"), terminals: terminals
        )
        #expect(first == "term_aaa")
        #expect(second == "term_bbb")
        #expect(first != second)
    }

    @Test
    func aPaneKeyForAClosedPaneDoesNotMatchAnother() {
        let terminals = [terminal(handle: "term_aaa", tabId: "tab-1", leafId: "leaf-1")]
        let handle = TerminalJumpService.matchOrcaHandle(
            target: target(paneKey: "tab-9:leaf-9"), terminals: terminals
        )
        #expect(handle == nil)
    }

    @Test
    func aMalformedPaneKeyIsIgnoredRatherThanMisMatched() {
        let terminals = [terminal(handle: "term_aaa", tabId: "tab-1", leafId: "leaf-1")]
        #expect(
            TerminalJumpService.matchOrcaHandle(
                target: target(paneKey: "no-colon-here"), terminals: terminals
            ) == nil
        )
        #expect(
            TerminalJumpService.matchOrcaHandle(
                target: target(paneKey: ""), terminals: terminals
            ) == nil
        )
    }

    // MARK: - Worktree fallback

    /// Sessions recorded before the pane key was captured have no key, so the
    /// worktree path is the only handle left.
    @Test
    func worktreePathResolvesWhenNoPaneKeyIsPresent() {
        let terminals = [
            terminal(handle: "term_aaa", worktreePath: "/w/one"),
            terminal(handle: "term_bbb", worktreePath: "/w/two"),
        ]
        let handle = TerminalJumpService.matchOrcaHandle(
            target: target(cwd: "/w/two"), terminals: terminals
        )
        #expect(handle == "term_bbb")
    }

    /// With several panes on one worktree the fallback cannot tell them apart,
    /// and guessing would reintroduce exactly the bug this fixes. Returning nil
    /// lets the caller fall through to plain app activation.
    @Test
    func anAmbiguousWorktreeMatchRefusesToGuess() {
        let terminals = [
            terminal(handle: "term_aaa", worktreePath: "/w/same"),
            terminal(handle: "term_bbb", worktreePath: "/w/same"),
        ]
        let handle = TerminalJumpService.matchOrcaHandle(
            target: target(cwd: "/w/same"), terminals: terminals
        )
        #expect(handle == nil)
    }

    @Test
    func paneKeyWinsOverAWorktreeMatch() {
        let terminals = [
            terminal(handle: "term_aaa", tabId: "tab-1", leafId: "leaf-1", worktreePath: "/w/one"),
            terminal(handle: "term_bbb", tabId: "tab-1", leafId: "leaf-2", worktreePath: "/w/one"),
        ]
        let handle = TerminalJumpService.matchOrcaHandle(
            target: target(paneKey: "tab-1:leaf-2", cwd: "/w/one"), terminals: terminals
        )
        #expect(handle == "term_bbb")
    }

    @Test
    func nothingMatchesWhenThereAreNoTerminals() {
        #expect(
            TerminalJumpService.matchOrcaHandle(
                target: target(paneKey: "tab-1:leaf-1", cwd: "/w/one"), terminals: []
            ) == nil
        )
    }
}

/// The hook side: detection already read `ORCA_PANE_KEY`, but discarded the
/// value, which is why a jump could only ever activate the app.
struct OrcaHookPaneKeyTests {
    private func payload(cwd: String = "/w/one") -> ClaudeHookPayload {
        ClaudeHookPayload(cwd: cwd, hookEventName: .sessionStart, sessionID: "s1")
    }

    private func enriched(_ environment: [String: String]) -> ClaudeHookPayload {
        payload().withRuntimeContext(
            environment: environment,
            currentTTYProvider: { nil },
            terminalLocatorProvider: { _ in (nil, nil, nil) },
            warpPaneResolver: { _ in nil }
        )
    }

    @Test
    func orcaPaneKeyIsCapturedFromTheEnvironment() {
        let result = enriched(["ORCA_PANE_KEY": "tab-1:leaf-2"])
        #expect(result.terminalApp == "Orca.app")
        #expect(result.orcaPaneKey == "tab-1:leaf-2")
    }

    @Test
    func theCapturedKeyReachesTheJumpTarget() {
        let target = enriched(["ORCA_PANE_KEY": "tab-1:leaf-2"]).defaultJumpTarget
        #expect(target.terminalApp == "Orca.app")
        #expect(target.orcaPaneKey == "tab-1:leaf-2")
    }

    /// Orca detected by bundle id alone has no pane key, and must not invent one.
    @Test
    func aBundleIdOnlyOrcaSessionHasNoPaneKey() {
        let result = enriched(["__CFBundleIdentifier": "com.stablyai.orca"])
        #expect(result.terminalApp == "Orca.app")
        #expect(result.orcaPaneKey == nil)
    }

    /// `ORCA_PANE_KEY` outranks `TERM_PROGRAM` by design — Orca leaks the
    /// launching shell's `TERM_PROGRAM` into the subprocess, so trusting it
    /// would misattribute the session to whatever terminal started Orca.
    @Test
    func orcaPaneKeyOutranksALeakedTermProgram() {
        let result = enriched(["TERM_PROGRAM": "iTerm.app", "ORCA_PANE_KEY": "tab-1:leaf-2"])
        #expect(result.terminalApp == "Orca.app")
        #expect(result.orcaPaneKey == "tab-1:leaf-2")
    }

    /// A genuine non-Orca terminal must not acquire a pane key.
    @Test
    func nonOrcaTerminalsDoNotPickUpAPaneKey() {
        let result = enriched(["TERM_PROGRAM": "iTerm.app"])
        #expect(result.terminalApp != "Orca.app")
        #expect(result.orcaPaneKey == nil)
    }
}
