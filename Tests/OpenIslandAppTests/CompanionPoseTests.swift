import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct CompanionPoseTests {
    /// Nothing to watch over — the companion sleeps.
    @Test
    func noSessionsSleeps() {
        let model = AppModel()
        model.state = SessionState(sessions: [])

        #expect(model.companionPose == .sleeping)
    }

    /// Work in flight — the companion is alert.
    @Test
    func aRunningSessionIsAlert() {
        let model = AppModel()
        model.state = SessionState(sessions: [makeSession(id: "r", phase: .running)])

        #expect(model.companionPose == .alert)
    }

    /// Attention beats running, mirroring `islandClosedMode`'s precedence.
    @Test
    func attentionOutranksRunning() {
        let model = AppModel()
        model.state = SessionState(sessions: [
            makeSession(id: "r", phase: .running),
            makeSession(id: "w", phase: .waitingForApproval),
        ])

        #expect(model.companionPose == .attending)
    }

    /// Both waiting phases attend, not just approval.
    @Test
    func waitingForAnswerAlsoAttends() {
        let model = AppModel()
        model.state = SessionState(sessions: [makeSession(id: "q", phase: .waitingForAnswer)])

        #expect(model.companionPose == .attending)
    }

    /// Completion is a transient beat, never a resting pose — a pose that
    /// lingered on it would show a stale fact.
    @Test
    func completionIsNotARestingPose() {
        let model = AppModel()
        model.state = SessionState(sessions: [makeSession(id: "c", phase: .completed)])

        #expect(model.companionPose == .sleeping)
    }

    /// Quantity is the right slot's job. One running session and twelve read
    /// the same, because a drawing communicates counts badly.
    @Test
    func poseIsIndifferentToCount() {
        let one = AppModel()
        one.state = SessionState(sessions: [makeSession(id: "s-0", phase: .running)])

        let many = AppModel()
        many.state = SessionState(sessions: (0..<12).map { makeSession(id: "s-\($0)", phase: .running) })

        // Pinned to `.alert` so the comparison can't pass vacuously on two
        // models that both fell through to `.sleeping`.
        #expect(one.companionPose == .alert)
        #expect(one.companionPose == many.companionPose)
    }

    // MARK: - helpers

    private func makeSession(id: String, phase: SessionPhase) -> AgentSession {
        let now = Date(timeIntervalSince1970: 100_000)
        var session = AgentSession(
            id: id,
            title: "Claude · \(id)",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: "",
            updatedAt: now,
            firstSeenAt: now,
            permissionRequest: nil,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: id,
                paneTitle: "claude ~/\(id)",
                workingDirectory: "/tmp/\(id)",
                terminalSessionID: "ghostty-\(id)"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                transcriptPath: "/tmp/\(id).jsonl",
                currentTool: "Task"
            )
        )
        session.isProcessAlive = true
        session.isHookManaged = true
        return session
    }
}
