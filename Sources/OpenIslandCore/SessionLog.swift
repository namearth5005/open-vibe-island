import Foundation

/// One finished agent session, as recorded for statistics.
///
/// Deliberately flat and small: this is appended once per finished session and
/// scanned in full to compute stats, so it must stay cheap to encode and safe to
/// evolve. New fields must be optional so old lines keep decoding.
public struct SessionLogRecord: Equatable, Codable, Sendable {
    public var sessionID: String
    public var tool: AgentTool
    public var workspace: String?
    public var startedAt: Date
    public var endedAt: Date
    public var wasInterrupted: Bool
    public var stallCount: Int
    /// Mean seconds the human took to answer this session's gates.
    /// `nil` when the session had no gates — distinct from zero, which would
    /// otherwise drag the median toward an answer time nobody achieved.
    public var meanGateLatency: Double?
    /// Seconds the human took to answer this session's *slowest* gate.
    ///
    /// Recorded alongside the mean because the mean cannot answer "was any gate
    /// left past the grace window": 1s and 59s average to exactly 30s. No
    /// threshold on a mean can close that — enough fast answers drag any single
    /// slow gate under any bound — so the fact has to be captured at the source.
    /// `nil` means unrecorded, which covers both a session with no gates and
    /// every record written before this field existed.
    public var worstGateLatency: Double?
    /// True when this record was derived from a transcript rather than observed
    /// live.
    ///
    /// For an inferred record every field but the timestamps is an assertion:
    /// back-fill cannot see interrupts, gates or answer times, so it writes the
    /// conservative value and moves on. Read at face value those assertions earn
    /// the top tier for every transcript on disk, which is the opposite of what
    /// they mean. Storing the provenance keeps the rating honest without storing
    /// the rating itself. `nil` means observed: every record written before this
    /// field existed came from the live event path.
    public var isInferred: Bool?

    public init(
        sessionID: String,
        tool: AgentTool,
        workspace: String? = nil,
        startedAt: Date,
        endedAt: Date,
        wasInterrupted: Bool,
        stallCount: Int,
        meanGateLatency: Double? = nil,
        worstGateLatency: Double? = nil,
        isInferred: Bool? = nil
    ) {
        self.sessionID = sessionID
        self.tool = tool
        self.workspace = workspace
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.wasInterrupted = wasInterrupted
        self.stallCount = stallCount
        self.meanGateLatency = meanGateLatency
        self.worstGateLatency = worstGateLatency
        self.isInferred = isInferred
    }

    /// Wall-clock duration. Clamped at zero so a clock adjustment mid-session
    /// cannot produce negative runtime that silently subtracts from a total.
    public var duration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }

    public var isCleanFinish: Bool {
        !wasInterrupted
    }
}

/// Append-only JSON Lines store for finished sessions.
///
/// Append-only on purpose. A session can legitimately complete more than once —
/// Claude Code emits a turn-level `Stop` and a separate `SessionEnd` — so
/// deduplication happens at *read* time instead of by rewriting the file. That
/// makes a duplicate append harmless rather than corrupting, and means an append
/// is a single atomic write with no read-modify-write window.
/// Not `Sendable`: it holds a `FileManager`, and the store is meant to be used
/// from one place (the main-actor `AppModel`) rather than shared across actors.
/// The values it produces — `SessionLogRecord` — are `Sendable`, which is what
/// actually needs to cross boundaries.
public struct SessionLogStore {
    public let fileURL: URL
    private let fileManager: FileManager

    public static var defaultDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/open-island", isDirectory: true)
    }

    public static var defaultFileURL: URL {
        defaultDirectoryURL.appendingPathComponent("session-log.jsonl")
    }

    public init(
        fileURL: URL = SessionLogStore.defaultFileURL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // One line per record: newlines inside a record would corrupt the format.
        encoder.outputFormatting = []
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Append one record. Best-effort by contract: statistics must never be able
    /// to break agent monitoring, so a failure here is swallowed and reported as
    /// `false` rather than thrown at the caller.
    @discardableResult
    public func append(_ record: SessionLogRecord) -> Bool {
        guard let data = try? Self.encoder.encode(record) else { return false }
        var line = data
        line.append(0x0A)

        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if fileManager.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: fileURL, options: .atomic)
            }
            return true
        } catch {
            return false
        }
    }

    /// Load every record, deduplicated.
    ///
    /// Malformed lines are skipped rather than aborting the load: one bad write
    /// must not be able to destroy a year of history.
    public func load() -> [SessionLogRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8)
        else {
            return []
        }

        let records = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> SessionLogRecord? in
                guard let lineData = line.data(using: .utf8) else { return nil }
                return try? Self.decoder.decode(SessionLogRecord.self, from: lineData)
            }

        return Self.deduplicated(records)
    }

    /// Collapse repeats by session ID, keeping the latest `endedAt`.
    ///
    /// Pure and public so the back-fill path and tests can reuse the exact rule
    /// the store applies, rather than reimplementing it slightly differently.
    public static func deduplicated(_ records: [SessionLogRecord]) -> [SessionLogRecord] {
        var latest: [String: SessionLogRecord] = [:]
        for record in records {
            if let existing = latest[record.sessionID], existing.endedAt >= record.endedAt {
                continue
            }
            latest[record.sessionID] = record
        }
        return latest.values.sorted { $0.endedAt < $1.endedAt }
    }

    /// Session IDs already present, so back-fill can skip what it has seen
    /// without loading and re-appending the whole history.
    public func knownSessionIDs() -> Set<String> {
        Set(load().map(\.sessionID))
    }
}
