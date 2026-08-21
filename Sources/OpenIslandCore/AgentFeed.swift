import Foundation

/// One thing an agent said or did, in order.
///
/// The app has always known where each agent's transcript lives — every
/// metadata payload carries a `transcriptPath` — but has only ever used it to
/// backfill history. The transcript holds the agent's actual prose, every tool
/// call with its full input, and per-turn token usage. This is that file read
/// as a feed rather than summarised into a status string.
public struct AgentFeedEntry: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        /// Prose the agent wrote, verbatim.
        case said(String)
        /// A tool call: the tool's name plus the one argument worth showing.
        case ran(tool: String, argument: String)
        /// A file the agent changed, with lines added and removed.
        case edited(file: String, added: Int, removed: Int)
        /// A thinking block, with its token cost when the record reports one.
        case thought(tokens: Int?)
    }

    public let id: String
    public let timestamp: Date
    public let kind: Kind
    /// True when the record came from a subagent rather than the main thread.
    public let isSidechain: Bool

    public init(id: String, timestamp: Date, kind: Kind, isSidechain: Bool = false) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.isSidechain = isSidechain
    }
}

/// A running tally over a feed, for the header.
public struct AgentFeedSummary: Equatable, Sendable {
    public var model: String?
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var filesTouched: Int
    public var linesAdded: Int
    public var linesRemoved: Int

    public init(
        model: String? = nil,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        filesTouched: Int = 0,
        linesAdded: Int = 0,
        linesRemoved: Int = 0
    ) {
        self.model = model
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.filesTouched = filesTouched
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
    }
}

public struct AgentFeed: Equatable, Sendable {
    public var entries: [AgentFeedEntry]
    public var summary: AgentFeedSummary

    public init(entries: [AgentFeedEntry] = [], summary: AgentFeedSummary = .init()) {
        self.entries = entries
        self.summary = summary
    }
}

/// Parses Claude Code's JSONL transcript into a feed.
///
/// Only Claude Code's shape is handled here. Codex, Gemini and Cursor each
/// write their own format; each needs its own parser conforming to the same
/// output. Verified against a real 3,882-line transcript.
public enum ClaudeTranscriptFeedReader {
    /// Tail size. A transcript grows without bound and only the recent end is
    /// ever shown, so the whole file is never read.
    ///
    /// Sized from a real file rather than guessed: single records are often
    /// enormous — a `Write` tool_use carries the entire file content, and
    /// attachment records are larger still — so 256 KB covered only two
    /// assistant records on a live transcript. 2 MB reliably reaches a few
    /// dozen, which is more than the feed ever displays.
    public static let tailBytes = 2 * 1024 * 1024

    /// Tools whose interesting argument is a path; the feed shows the basename.
    private static let pathArgumentTools: Set<String> = ["Read", "Write", "Edit", "NotebookEdit"]

    public static func read(contentsOf url: URL, limit: Int = 60) -> AgentFeed {
        guard let data = tail(of: url, bytes: tailBytes) else { return AgentFeed() }
        return parse(data, limit: limit)
    }

    /// Reads the last `bytes` of a file without loading the whole thing.
    static func tail(of url: URL, bytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let start = end > UInt64(bytes) ? end - UInt64(bytes) : 0
        try? handle.seek(toOffset: start)
        return try? handle.readToEnd()
    }

    public static func parse(_ data: Data, limit: Int = 60) -> AgentFeed {
        var entries: [AgentFeedEntry] = []
        var summary = AgentFeedSummary()
        var touched = Set<String>()

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()

        // A tail can begin mid-line; a record that fails to parse is skipped
        // rather than treated as an error.
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  record["type"] as? String == "assistant",
                  let message = record["message"] as? [String: Any]
            else { continue }

            let stamp = record["timestamp"] as? String ?? ""
            let date = iso.date(from: stamp) ?? isoPlain.date(from: stamp) ?? Date()
            let sidechain = record["isSidechain"] as? Bool ?? false
            let uuid = record["uuid"] as? String ?? UUID().uuidString

            if let model = message["model"] as? String { summary.model = model }
            if let usage = message["usage"] as? [String: Any] {
                summary.outputTokens += usage["output_tokens"] as? Int ?? 0
                summary.cacheReadTokens = usage["cache_read_input_tokens"] as? Int ?? summary.cacheReadTokens
            }

            for (index, raw) in ((message["content"] as? [[String: Any]]) ?? []).enumerated() {
                let id = "\(uuid)-\(index)"
                switch raw["type"] as? String {
                case "text":
                    let text = (raw["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    entries.append(.init(id: id, timestamp: date, kind: .said(text), isSidechain: sidechain))

                case "thinking":
                    entries.append(.init(id: id, timestamp: date, kind: .thought(tokens: nil), isSidechain: sidechain))

                case "tool_use":
                    let name = raw["name"] as? String ?? "tool"
                    let input = raw["input"] as? [String: Any] ?? [:]

                    // Edit and Write carry the before/after text, so the diff
                    // comes straight out of the transcript. That is better than
                    // asking git: it counts only what THIS agent changed, not
                    // unrelated edits sitting in the same worktree.
                    if let path = input["file_path"] as? String, name == "Edit" || name == "Write" {
                        let before = input["old_string"] as? String ?? ""
                        let after = input["new_string"] as? String ?? (input["content"] as? String ?? "")
                        let added = lineCount(after)
                        let removed = lineCount(before)
                        touched.insert(path)
                        summary.linesAdded += added
                        summary.linesRemoved += removed
                        entries.append(.init(
                            id: id, timestamp: date,
                            kind: .edited(file: basename(path), added: added, removed: removed),
                            isSidechain: sidechain
                        ))
                        continue
                    }

                    entries.append(.init(
                        id: id, timestamp: date,
                        kind: .ran(tool: name, argument: argument(for: name, input: input)),
                        isSidechain: sidechain
                    ))

                default:
                    continue
                }
            }
        }

        summary.filesTouched = touched.count
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
        return AgentFeed(entries: entries, summary: summary)
    }

    /// The single most useful argument to show per tool, chosen from the real
    /// input shapes Claude Code writes.
    static func argument(for tool: String, input: [String: Any]) -> String {
        if pathArgumentTools.contains(tool), let path = input["file_path"] as? String {
            return basename(path)
        }
        for key in ["description", "command", "query", "skill", "url", "name", "summary"] {
            if let value = input[key] as? String, !value.isEmpty {
                return value
            }
        }
        return ""
    }

    static func basename(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    /// Empty text is zero lines; otherwise newlines plus one.
    static func lineCount(_ text: String) -> Int {
        text.isEmpty ? 0 : text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }
}

public extension AgentSession {
    /// Where this session's transcript lives, if the agent writes one.
    ///
    /// `trackingTranscriptPath` already exists but is internal to the module
    /// and is used for history backfill. This is the public door onto the same
    /// file, for reading it as a feed.
    var feedTranscriptURL: URL? {
        let path = codexMetadata?.transcriptPath
            ?? claudeMetadata?.transcriptPath
            ?? geminiMetadata?.transcriptPath
        guard let path, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Whether a feed can be read for this session at all. Only Claude Code's
    /// transcript shape is parsed today; the other agents each write their own
    /// format and need their own reader.
    var supportsFeed: Bool {
        tool == .claudeCode && feedTranscriptURL != nil
    }
}
