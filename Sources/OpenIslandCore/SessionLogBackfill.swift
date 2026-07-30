import Foundation

/// Derives historical session records from Claude Code transcripts already on
/// disk, so the Stats view has something to show on first launch.
///
/// Without this, statistics start empty and stay thin for days — exactly the
/// window in which someone decides whether to care about the feature. A user with
/// a year of transcripts should see a year of history immediately.
///
/// Everything here is inference from file metadata rather than observed events,
/// so it is deliberately conservative: it never claims an interrupt, never
/// invents gate latencies, and skips anything it cannot date confidently.
public struct SessionLogBackfill {
    private let rootURL: URL
    private let fileManager: FileManager

    /// Transcripts shorter than this are aborted starts, template writes, or
    /// crashes — counting them would inflate history with sessions that never
    /// really happened.
    public static let minimumLineCount = 4

    /// A transcript whose first and last entry are this close together did not
    /// represent real work.
    public static let minimumDuration: TimeInterval = 20

    public init(
        rootURL: URL = ClaudeTranscriptDiscovery.defaultRootURL,
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    /// Build records for every transcript not already represented in the log.
    ///
    /// `existingSessionIDs` makes this idempotent: running it on every launch
    /// re-derives nothing that has already been recorded, and any session the
    /// live event path logged wins over inference.
    public func derivedRecords(existingSessionIDs: Set<String>) -> [SessionLogRecord] {
        guard fileManager.fileExists(atPath: rootURL.path),
              let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              )
        else {
            return []
        }

        var records: [SessionLogRecord] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl",
                  // Subagent transcripts are not sessions the human ran.
                  !fileURL.path.contains("/subagents/")
            else {
                continue
            }

            let sessionID = fileURL.deletingPathExtension().lastPathComponent
            guard !existingSessionIDs.contains(sessionID) else { continue }

            guard let record = derive(from: fileURL, sessionID: sessionID) else { continue }
            records.append(record)
        }

        return records
    }

    private func derive(from fileURL: URL, sessionID: String) -> SessionLogRecord? {
        guard let values = try? fileURL.resourceValues(
            forKeys: [.isRegularFileKey, .contentModificationDateKey]
        ),
            values.isRegularFile == true,
            let modifiedAt = values.contentModificationDate
        else {
            return nil
        }

        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count >= Self.minimumLineCount else { return nil }

        // Prefer the first timestamp inside the transcript over file creation
        // date, which copies and syncs routinely rewrite.
        guard let startedAt = Self.firstTimestamp(in: lines) else { return nil }
        let endedAt = max(modifiedAt, startedAt)
        guard endedAt.timeIntervalSince(startedAt) >= Self.minimumDuration else { return nil }

        return SessionLogRecord(
            sessionID: sessionID,
            tool: .claudeCode,
            workspace: Self.workspaceName(from: fileURL),
            startedAt: startedAt,
            endedAt: endedAt,
            // Inference cannot distinguish a clean finish from an interrupt, and
            // claiming an interrupt that did not happen is worse than missing one.
            wasInterrupted: false,
            stallCount: 0,
            // Never invent a latency: nil keeps these out of the median entirely
            // rather than skewing it with a fabricated number.
            meanGateLatency: nil
        )
    }

    /// First ISO-8601 `timestamp` field in the transcript.
    static func firstTimestamp(in lines: [Substring]) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()

        for line in lines.prefix(20) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let raw = object["timestamp"] as? String
            else {
                continue
            }
            if let date = formatter.date(from: raw) ?? plain.date(from: raw) {
                return date
            }
        }
        return nil
    }

    /// Claude encodes the project path in the directory name, with separators
    /// flattened to dashes. The trailing component is close enough to a repo name
    /// to be useful, and this never has to be exact — it is a label, not an id.
    static func workspaceName(from fileURL: URL) -> String? {
        let directory = fileURL.deletingLastPathComponent().lastPathComponent
        guard !directory.isEmpty else { return nil }
        let trimmed = directory.hasPrefix("-") ? String(directory.dropFirst()) : directory
        let parts = trimmed.split(separator: "-").filter { !$0.isEmpty }
        return parts.last.map(String.init)
    }
}
