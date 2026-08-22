import SwiftUI
import OpenIslandCore

/// What an agent is actually saying and doing, read from its transcript.
///
/// The app has always stored `transcriptPath` and never opened the file. It
/// holds the agent's prose verbatim, every tool call with its full input, and
/// per-turn token usage — so the panel can show the work rather than a status
/// string summarising it.
///
/// The diff here comes from the transcript's own `Edit` and `Write` records,
/// not from git. That is deliberately narrower and more accurate: it counts
/// only what this agent changed, excluding unrelated edits sitting in the same
/// worktree.
struct AgentFeedView: View {
    let session: AgentSession
    let others: [AgentSession]

    /// Distance from the opened surface's own edge to the first glyph.
    ///
    /// This is not a style choice. `OpenedIslandSurfaceShape` in notch mode is
    /// a `NotchShape`, whose straight sides sit at `rect.minX + topR` and
    /// `rect.maxX - topR` — 22pt inside the rect on each side. The panel clips
    /// its content to that path while framing it at the full opened width, so
    /// anything closer than 22pt to the edge is masked away. Every other
    /// surface in the panel already passes the same notch-aware inset; the feed
    /// had a hardcoded 13 and lost nine points of glyphs off *both* sides,
    /// which is what rendered `Opus 5` as `us 5` and `running` as `runnir`.
    let sideInset: CGFloat

    /// Resolved once by the panel and passed down, so the whole feed renders
    /// from one value rather than reaching for globals.
    let theme: FeedTheme

    @State private var feed = AgentFeed()

    /// Transcripts are appended to constantly; this is a cheap tail-and-parse,
    /// not a file watcher. Two seconds is well inside the rate a person reads.
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    /// Where the turn spine hangs, and where an action row's text begins.
    private let spineIndent: CGFloat = 12
    private let actionIndent: CGFloat = 21
    /// Wide enough for the long tool names Claude Code actually emits
    /// (`todowrite`, `webfetch`) without truncating them to initials.
    private let labelWidth: CGFloat = 52
    private let stampWidth: CGFloat = 30

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.hairline.color)
            body(for: feed)
            Divider().overlay(theme.hairline.color)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.ground.color)
        .onAppear(perform: reload)
        .onReceive(refresh) { _ in reload() }
    }

    private func reload() {
        guard let url = session.feedTranscriptURL else { return }
        feed = ClaudeTranscriptFeedReader.read(contentsOf: url, limit: 24)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                AgentMark(tool: session.tool, size: 13)
                Text(session.jumpTarget?.workspaceName ?? session.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.text.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                if let branch = session.jumpTarget?.workingDirectory.flatMap(
                    WorkspaceNameResolver.worktreeBranch(for:)
                ) {
                    tag(branch)
                }
                Spacer(minLength: 6)
                HStack(spacing: 4) {
                    Circle()
                        .fill(theme.headerColor(for: session.phase))
                        .frame(width: 5, height: 5)
                    Text(session.phase.displayName.lowercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.headerColor(for: session.phase))
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            HStack(spacing: 9) {
                if let model = feed.summary.model {
                    stat(shortModel(model))
                }
                if feed.summary.outputTokens > 0 {
                    stat("\(compact(feed.summary.outputTokens)) out")
                }
                Spacer(minLength: 4)
                if feed.summary.linesAdded > 0 || feed.summary.linesRemoved > 0 {
                    Text("+\(feed.summary.linesAdded)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.color(for: .completed))
                    Text("−\(feed.summary.linesRemoved)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.color(for: .waitingForApproval))
                    stat("\(feed.summary.filesTouched) file\(feed.summary.filesTouched == 1 ? "" : "s")")
                }
            }
        }
        .padding(.horizontal, sideInset)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Body

    @ViewBuilder
    private func body(for feed: AgentFeed) -> some View {
        if feed.entries.isEmpty {
            VStack(spacing: 5) {
                Text(session.supportsFeed ? "Waiting for output" : "No transcript for this agent")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(theme.dim.color)
                if !session.supportsFeed {
                    Text("Only Claude Code transcripts are read so far")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.faint.color)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical) {
                // Turns are the unit of separation. Inside one, rows sit close
                // together under a shared spine; between two, the gap is wide
                // enough to read as a break without needing a box.
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(FeedTurns.grouped(feed.entries)) { turn in
                        turnView(turn)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, sideInset)
                .padding(.vertical, 10)
            }
            .defaultScrollAnchor(.bottom)
        }
    }

    /// One turn: the prose the agent wrote, and the tool calls it triggered
    /// hanging off a single continuous rule beneath it.
    ///
    /// The clock prints once, on the turn's first row. Repeating it made every
    /// row look like a separate event; printed once it marks where each turn
    /// starts, so the gutter alone tells the reader how many turns are on
    /// screen.
    private func turnView(_ turn: FeedTurn) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(turn.lead.enumerated()), id: \.element.id) { index, entry in
                row(for: entry, showsStamp: index == 0)
            }

            if !turn.actions.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(turn.actions) { row(for: $0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, actionIndent)
                .padding(.top, turn.lead.isEmpty ? 0 : 2)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(theme.hairline.color)
                        .frame(width: 1)
                        .padding(.leading, spineIndent)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for entry: AgentFeedEntry, showsStamp: Bool = false) -> some View {
        switch entry.kind {
        case .said(let text):
            HStack(alignment: .top, spacing: 8) {
                stamp(entry.timestamp, visible: showsStamp)
                Text(FeedText.plain(text))
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.text.color)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .ran(let tool, let argument):
            actionRow {
                label(tool.lowercased(), tint: toolTint(tool))
                Text(argument)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(theme.dim.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }

        case .edited(let file, let added, let removed):
            actionRow {
                label("edit", tint: theme.color(for: .completed))
                Text(file)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(theme.dim.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if added > 0 {
                    Text("+\(added)")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.color(for: .completed))
                        .fixedSize()
                }
                if removed > 0 {
                    Text("−\(removed)")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.color(for: .waitingForApproval))
                        .fixedSize()
                }
            }

        case .thought:
            HStack(alignment: .top, spacing: 8) {
                stamp(entry.timestamp, visible: showsStamp)
                Text("thinking")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.faint.color)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
    }

    /// Every action row is exactly one line. A tool name long enough to wrap
    /// used to break mid-word and cost the row a second line.
    private func actionRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6, content: content)
            .lineLimit(1)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 7) {
            if others.isEmpty {
                Text("No other agents")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(theme.faint.color)
            } else {
                Text("\(others.count) other\(others.count == 1 ? "" : "s")")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(theme.dim.color)
                    .fixedSize()
                ForEach(others.prefix(3), id: \.id) { other in
                    let attention = other.phase.requiresAttention
                    Text(other.jumpTarget?.workspaceName ?? other.title)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(attention
                            ? theme.color(for: .waitingForApproval)
                            : theme.dim.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            (attention
                                ? theme.color(for: .waitingForApproval).opacity(0.14)
                                : theme.text.color.opacity(0.08)),
                            in: RoundedRectangle(cornerRadius: 3)
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, sideInset)
        .padding(.vertical, 8)
    }

    // MARK: Bits

    private func stamp(_ date: Date, visible: Bool) -> some View {
        Text(FeedClock.stamp(date))
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(theme.faint.color)
            .opacity(visible ? 1 : 0)
            .frame(width: stampWidth, alignment: .leading)
    }

    private func label(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: labelWidth, alignment: .leading)
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(theme.dim.color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(theme.text.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private func stat(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .foregroundStyle(theme.faint.color)
            .lineLimit(1)
            .fixedSize()
    }

    /// Bash and Read dominate a feed, so they get the quietest treatment and
    /// the rarer tools stand out.
    private func toolTint(_ tool: String) -> Color {
        switch tool {
        case "Bash": theme.color(for: .running)
        case "Read", "Glob", "Grep": theme.dim.color
        case "Task", "Agent": Color(red: 0.5, green: 0.83, blue: 0.83)
        default: theme.color(for: .waitingForAnswer)
        }
    }

    private func shortModel(_ id: String) -> String {
        id.replacingOccurrences(of: "claude-", with: "")
            .split(separator: "-").prefix(2).joined(separator: " ")
    }

    private func compact(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }
}

/// A geometric mark per agent in that tool's own brand colour. Deliberately not
/// a replica of any vendor's logo — it identifies the tool, nothing more.
struct AgentMark: View {
    let tool: AgentTool
    var size: CGFloat = 13

    var body: some View {
        let tint = Color(hex: tool.brandColorHex) ?? V6Palette.paper
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            var path = Path()
            let r = min(rect.width, rect.height) / 2
            let c = CGPoint(x: rect.midX, y: rect.midY)
            switch tool {
            case .claudeCode:
                for angle in stride(from: 0.0, to: 180.0, by: 60.0) {
                    let rad = angle * .pi / 180
                    path.move(to: CGPoint(x: c.x - cos(rad) * r, y: c.y - sin(rad) * r))
                    path.addLine(to: CGPoint(x: c.x + cos(rad) * r, y: c.y + sin(rad) * r))
                }
            case .codex:
                path.addRoundedRect(in: rect.insetBy(dx: 1, dy: 1), cornerSize: .init(width: 3, height: 3))
            case .cursor:
                path.move(to: CGPoint(x: rect.minX + 1, y: rect.minY + 1))
                path.addLine(to: CGPoint(x: rect.maxX - 1, y: c.y))
                path.addLine(to: CGPoint(x: c.x, y: rect.maxY - 1))
                path.closeSubpath()
            case .geminiCLI:
                path.move(to: CGPoint(x: c.x, y: rect.minY))
                path.addQuadCurve(to: CGPoint(x: rect.maxX, y: c.y), control: c)
                path.addQuadCurve(to: CGPoint(x: c.x, y: rect.maxY), control: c)
                path.addQuadCurve(to: CGPoint(x: rect.minX, y: c.y), control: c)
                path.addQuadCurve(to: CGPoint(x: c.x, y: rect.minY), control: c)
            default:
                path.addEllipse(in: rect.insetBy(dx: 1, dy: 1))
            }
            context.stroke(path, with: .color(tint), lineWidth: 1.6)
        }
        .frame(width: size, height: size)
    }
}

/// Agent prose is markdown. The transcript stores it verbatim, so raw
/// asterisks and backticks show up as literal characters unless they are taken
/// out — which is exactly how the first live run looked.
///
/// Deliberately a strip, not a renderer: the feed wants one readable line, not
/// formatted rich text. Lives outside the view because it is pure text work and
/// a MainActor-isolated helper cannot be called from a plain test.
enum FeedText {
    static func plain(_ text: String) -> String {
        var out = text
        for token in ["**", "`", "__"] {
            out = out.replacingOccurrences(of: token, with: "")
        }
        out = out.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var l = String(line)
                while l.hasPrefix("#") { l.removeFirst() }
                if l.hasPrefix("- ") { l.removeFirst(2) }
                return l.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A fixed-width 24-hour stamp.
///
/// `.dateTime.hour().minute()` respects the locale's hour cycle, so a 12-hour
/// locale renders `12:57 AM` — eight characters into a column sized for five,
/// which truncated every timestamp in the feed. There is no room for a meridiem
/// marker at this size and no reading of the feed needs one, so the cycle is
/// pinned rather than the column widened.
enum FeedClock {
    static func stamp(_ date: Date, in timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// Prose the agent wrote, plus the tool calls it triggered.
///
/// A turn is what the reader is actually scanning for — "it said this, so it
/// did that". Without it the feed is one undifferentiated column of lines.
struct FeedTurn: Identifiable, Equatable {
    let id: String
    var lead: [AgentFeedEntry]
    var actions: [AgentFeedEntry]
}

/// Groups a flat feed into turns.
///
/// Pure, and outside the view, for the same reason `FeedText` is: a
/// MainActor-isolated helper cannot be called from a plain test.
enum FeedTurns {
    static func grouped(_ entries: [AgentFeedEntry]) -> [FeedTurn] {
        var turns: [FeedTurn] = []

        for entry in entries {
            let isProse = isProse(entry.kind)
            // A turn breaks when prose arrives after work has been done — that
            // is the agent starting a new thought. Consecutive prose rows
            // (thinking, then text, as one record writes them) stay together.
            let breaksTurn = turns.isEmpty || (isProse && !turns[turns.count - 1].actions.isEmpty)
            if breaksTurn {
                turns.append(FeedTurn(id: entry.id, lead: [], actions: []))
            }
            if isProse {
                turns[turns.count - 1].lead.append(entry)
            } else {
                turns[turns.count - 1].actions.append(entry)
            }
        }

        return turns
    }

    private static func isProse(_ kind: AgentFeedEntry.Kind) -> Bool {
        switch kind {
        case .said, .thought: true
        case .ran, .edited: false
        }
    }
}
