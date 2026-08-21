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

    @State private var feed = AgentFeed()

    /// Transcripts are appended to constantly; this is a cheap tail-and-parse,
    /// not a file watcher. Two seconds is well inside the rate a person reads.
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        // Measured rather than "maxWidth: .infinity". A row containing a Spacer
        // and a Text with an ideal width can size ITSELF wider than the parent,
        // and SwiftUI then centres the overflow -- which clipped both edges at
        // once and cut "Opus 5" and "running" in half on the real panel.
        // Pinning every band to the measured width removes the ambiguity.
        GeometryReader { geo in
            VStack(spacing: 0) {
                header.frame(width: geo.size.width, alignment: .leading)
                Divider().overlay(FeedPalette.hairline)
                body(for: feed).frame(width: geo.size.width, alignment: .leading)
                Divider().overlay(FeedPalette.hairline)
                footer.frame(width: geo.size.width, alignment: .leading)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .clipped()
        }
        .background(V6Palette.ink)
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
                    .foregroundStyle(FeedPalette.text)
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
                        .fill(IslandDesignPalette.Status.tint(for: session.phase))
                        .frame(width: 5, height: 5)
                    Text(session.phase.displayName.lowercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(IslandDesignPalette.Status.tint(for: session.phase))
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
                        .foregroundStyle(IslandDesignPalette.Status.completed)
                    Text("−\(feed.summary.linesRemoved)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(IslandDesignPalette.Status.waitingForApproval)
                    stat("\(feed.summary.filesTouched) files")
                }
            }
        }
        .padding(.horizontal, 13)
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
                    .foregroundStyle(FeedPalette.dim)
                if !session.supportsFeed {
                    Text("Only Claude Code transcripts are read so far")
                        .font(.system(size: 10))
                        .foregroundStyle(FeedPalette.faint)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(feed.entries) { entry in
                        row(for: entry)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
            }
            .defaultScrollAnchor(.bottom)
        }
    }

    @ViewBuilder
    private func row(for entry: AgentFeedEntry) -> some View {
        switch entry.kind {
        case .said(let text):
            HStack(alignment: .top, spacing: 8) {
                stamp(entry.timestamp)
                Text(FeedText.plain(text))
                    .font(.system(size: 11.5))
                    .foregroundStyle(FeedPalette.text.opacity(0.92))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .ran(let tool, let argument):
            indented {
                Text(tool.lowercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(toolTint(tool))
                    .frame(width: 34, alignment: .leading)
                Text(argument)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(FeedPalette.dim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

        case .edited(let file, let added, let removed):
            indented {
                Text("edit")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(IslandDesignPalette.Status.completed)
                    .frame(width: 34, alignment: .leading)
                Text(file)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(FeedPalette.dim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if added > 0 {
                    Text("+\(added)")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(IslandDesignPalette.Status.completed)
                }
                if removed > 0 {
                    Text("−\(removed)")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(IslandDesignPalette.Status.waitingForApproval)
                }
            }

        case .thought:
            HStack(alignment: .top, spacing: 8) {
                stamp(entry.timestamp)
                Text("thinking")
                    .font(.system(size: 11))
                    .foregroundStyle(FeedPalette.faint)
            }
        }
    }

    /// Tool rows hang off a rule under the prose that prompted them, so a turn
    /// reads as one block rather than a flat list of unrelated lines.
    private func indented<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6, content: content)
            .padding(.leading, 42)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(FeedPalette.hairline)
                    .frame(width: 1)
                    .padding(.leading, 34)
            }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 7) {
            if others.isEmpty {
                Text("No other agents")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(FeedPalette.faint)
            } else {
                Text("\(others.count) other\(others.count == 1 ? "" : "s")")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(FeedPalette.dim)
                ForEach(others.prefix(3), id: \.id) { other in
                    let attention = other.phase.requiresAttention
                    Text(other.jumpTarget?.workspaceName ?? other.title)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(attention
                            ? IslandDesignPalette.Status.waitingForApproval
                            : FeedPalette.dim)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            (attention
                                ? IslandDesignPalette.Status.waitingForApproval.opacity(0.14)
                                : FeedPalette.text.opacity(0.08)),
                            in: RoundedRectangle(cornerRadius: 3)
                        )
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
    }

    // MARK: Bits

    private func stamp(_ date: Date) -> some View {
        Text(date, format: .dateTime.hour().minute())
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(FeedPalette.faint)
            .frame(width: 34, alignment: .leading)
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(FeedPalette.dim)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(FeedPalette.text.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private func stat(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .foregroundStyle(FeedPalette.faint)
    }

    /// Bash and Read dominate a feed, so they get the quietest treatment and
    /// the rarer tools stand out.
    private func toolTint(_ tool: String) -> Color {
        switch tool {
        case "Bash": IslandDesignPalette.Status.running
        case "Read", "Glob", "Grep": FeedPalette.dim
        case "Task", "Agent": Color(red: 0.5, green: 0.83, blue: 0.83)
        default: IslandDesignPalette.Status.waitingForAnswer
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

enum FeedPalette {
    static let text = V6Palette.paper
    static let dim = V6Palette.paper.opacity(0.58)
    static let faint = V6Palette.paper.opacity(0.34)
    static let hairline = V6Palette.paper.opacity(0.07)
}
