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
/// invents gate latencies, and skips anything it cannot date confidently. It
/// also marks what it produces `isInferred`, because a conservative value still
/// reads as a fact to whoever loads it next.
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

    /// Transcripts spanning longer than this are skipped entirely.
    ///
    /// A resumed session can be appended to across days, so its first-to-last
    /// span is wall-clock calendar time, not time an agent spent working. Probing
    /// real data produced a "session" of 104 hours. Counting that as agent
    /// runtime would make the headline number meaningless, and clamping it would
    /// be inventing a duration — so these are excluded and the loss is stated
    /// rather than hidden.
    public static let maximumDuration: TimeInterval = 12 * 3600

    /// Bytes read from the tail when locating the final timestamp. Comfortably
    /// larger than any single transcript entry.
    private static let tailByteCount = 64 * 1024

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
            forKeys: [.isRegularFileKey, .fileSizeKey]
        ),
            values.isRegularFile == true,
            let byteCount = values.fileSize,
            byteCount > 0
        else {
            return nil
        }

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        // Head and tail only. Reading all 1,249 transcripts in full took 27
        // seconds; the timestamps live at both ends and nothing between matters.
        guard let headData = try? handle.read(upToCount: Self.tailByteCount) else { return nil }
        let headLines = Self.lines(from: headData)
        guard headLines.count >= Self.minimumLineCount || byteCount > Self.tailByteCount else {
            return nil
        }
        guard let startedAt = Self.firstTimestamp(in: headLines) else { return nil }

        let tailLines: [Substring]
        if byteCount > Self.tailByteCount {
            let offset = UInt64(byteCount - Self.tailByteCount)
            guard (try? handle.seek(toOffset: offset)) != nil,
                  let tailData = try? handle.readToEnd()
            else {
                return nil
            }
            tailLines = Self.lines(from: tailData)
        } else {
            tailLines = headLines
        }

        // Last timestamp in the transcript, not file mtime: mtime moves when a
        // session is resumed days later, which produced multi-day "sessions".
        guard let endedAt = Self.lastTimestamp(in: tailLines), endedAt > startedAt else {
            return nil
        }

        let span = endedAt.timeIntervalSince(startedAt)
        guard span >= Self.minimumDuration, span <= Self.maximumDuration else { return nil }

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
            meanGateLatency: nil,
            // Per-gate timings are not in a transcript at all, so the worst gate
            // is not merely absent here — it is unknowable. Zero would say "every
            // gate was answered instantly", which is a claim, not a gap.
            worstGateLatency: nil,
            // The conservative values above are what this had to write, not what
            // it saw. Without saying so, a reader takes "clean, no gates" at face
            // value and hands the top tier to every transcript on disk.
            isInferred: true
        )
    }

    static func lines(from data: Data) -> [Substring] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return Array(text.split(separator: "\n", omittingEmptySubsequences: true))
    }

    /// First ISO-8601 `timestamp` field in the transcript.
    static func firstTimestamp(in lines: [Substring]) -> Date? {
        for line in lines.prefix(30) {
            if let date = timestamp(in: line) { return date }
        }
        return nil
    }

    /// Last ISO-8601 `timestamp` field. Used instead of file modification time,
    /// which a resumed session rewrites days after the work actually happened.
    static func lastTimestamp(in lines: [Substring]) -> Date? {
        for line in lines.reversed().prefix(30) {
            if let date = timestamp(in: line) { return date }
        }
        return nil
    }

    private static func timestamp(in line: Substring) -> Date? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["timestamp"] as? String
        else {
            return nil
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
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
