# Companion feed — handoff

Date: 2026-08-22
Branch: `worktree-feat+companion-pill` (worktree at `.claude/worktrees/feat+companion-pill`)

You are picking up a feature that **works but does not yet look right**. The
data layer is sound and tested; the layout has defects that are visible only in
the running app. Your job is to close them, and to *prove* you closed them with
screenshots rather than by reasoning about SwiftUI.

Read this whole file before touching code. The environment traps in §6 have
each cost an hour already.

---

## 1. What exists

**`Sources/OpenIslandCore/AgentFeed.swift`** — parses Claude Code's JSONL
transcript into a feed. Ten tests in
`Tests/OpenIslandCoreTests/AgentFeedTests.swift`, all passing.

- `AgentFeedEntry.Kind` is `said` / `ran(tool:argument:)` / `edited(file:added:removed:)` / `thought`
- `AgentFeedSummary` carries model, output tokens, cache reads, files touched, ±lines
- `ClaudeTranscriptFeedReader.read(contentsOf:limit:)` tails the file and parses
- `AgentSession.feedTranscriptURL` / `.supportsFeed` are the public doors

**`Sources/OpenIslandApp/Views/AgentFeedView.swift`** — renders it. Also holds
`AgentMark` (a geometric glyph per agent in that tool's `brandColorHex`) and
`FeedText.plain` (markdown stripper, 5 tests in
`Tests/OpenIslandAppTests/FeedTextTests.swift`).

**Wiring** — `AppModel.feedFocusSession` picks the session to show (attention
first, then running). `IslandPanelView.openedContent` shows the feed when
`showCompanion` is on and a feed-capable session exists; otherwise
`CompanionRoomView`; otherwise the standard list.

Enable with **Settings → Behavior → "Show companion in the island"**.

### Facts about the data, established by reading a real transcript

- Each `assistant` record has `message.content[]` of `text`, `tool_use` (with
  the **full** input) and `thinking`, plus `message.model`, `message.usage`,
  `timestamp`, `cwd`, `isSidechain`.
- **The diff comes from the transcript, not git.** `Edit` records carry
  `old_string` and `new_string`; `Write` carries `content`. This counts only
  what *this agent* changed and excludes unrelated edits in the same worktree —
  strictly better than `git diff --stat` here. Do not replace it with git.
- **The tail must be large.** A single `Write` carries an entire file, so a
  256 KB tail reached only *two* assistant records on a live file. It is 2 MB.
- A tail can begin mid-line. Unparseable lines are skipped, not fatal. There is
  a test for this; keep it.
- **Only Claude Code's shape is parsed.** Codex, Gemini and Cursor each write
  their own format. Sessions without a readable transcript fall through to the
  room. Adding those parsers is out of scope here.

---

## 2. The defects you are fixing

All four are visible in a screenshot of the running app. None reproduce in a
SwiftUI preview, which is why §4 exists.

**D1 — Both edges clip.** `Opus 5` renders as `us 5`; `running` renders as
`runnir`. Content is lost symmetrically off *both* sides.

*Diagnosis so far:* a row containing a `Spacer` next to a `Text` with an ideal
width can size itself wider than its parent, and SwiftUI centres the overflow.
`.frame(maxWidth: .infinity)` does **not** prevent this — that was tried and
changed nothing. A `GeometryReader` with each band pinned to `geo.size.width`
was tried second and **also did not fix it**; do not simply retry either.

Untested hypotheses worth checking, in order: the panel's own
`.clipShape(surfaceShape)` in `IslandPanelView.openedSurface` may be narrower
than `openedWidth`; the feed may be receiving a width larger than the visible
surface; a `fixedSize` somewhere may be defeating the frame.

**D2 — Timestamp column overflows.** `AgentFeedView.swift:247` uses
`.dateTime.hour().minute()`, which renders `12:57 AM` in a 12-hour locale into
a **34pt** column, so it shows as `:57 a`. Either force a narrow 24-hour format
or widen the column. This is the one defect with a certain fix.

**D3 — Tool rows can wrap.** A long tool name or argument wrapped to two lines
mid-word (`listage` / `nts`). Tool name and argument should each be one line
with truncation.

**D4 — The feed reads as a wall.** No visual separation between turns. Prose,
its tool calls, and the next prose block run together. Grouping a turn (prose +
the tools it triggered) with spacing or a subtle container would fix it.

---

## 3. The design targets

Canvas: **https://claude.ai/code/artifact/58c28032-6f9a-4ffa-a04a-9eebfbf4fa93**

The artboard called **"THE OUTPUT — live feed"** is the target for this work.
Others are earlier explorations; ignore them unless you are asked to change
direction.

Design decisions already settled, with the reasons, so you do not relitigate:

- **The panel is informative; the companion is not on it.** Charm lives in the
  pill, the empty state, the completion card and a footer signature. A
  character sharing a frame with a list read under time pressure is what
  produced an empty box with a small dog in it.
- **Dark ground, not cream.** Every status tint in `IslandDesignPalette` is
  tuned for ink: approval 9.89:1, answer 13.99:1, running 7.98:1, done 8.26:1.
  On cream those become 1.64, 1.16, 2.03, 1.96 — all unusable. A cream panel
  means redesigning the whole status system.
- **Two text tiers only.** A third tier lands on the elapsed-time column and
  measures around 3:1.
- **Agent marks are geometric glyphs in each tool's own brand hex**, not
  replicas of vendor logos.

---

## 4. The validation loop — use this, do not skip to reasoning

Every defect above survived a clean build, a passing test suite and my own
reading of the code. The only thing that catches them is looking.

**Each iteration:**

1. Make one change.
2. `swift build 2>&1 | grep -E "error:|warning:"` — must be empty. This project
   is Swift 6 strict concurrency; a warning is a defect.
3. `swift test 2>&1 | grep "Test run with"` — expect **5 issues**, no more.
   Those five are pre-existing on this branch, in `AppModelSessionListTests`
   and `AgentsGridRightSlotTests`, verified by stashing all changes and
   re-running. More than five means you broke something.
4. Relaunch and screenshot (recipe below).
5. **Open the PNG and look at it.** Check each defect explicitly by name.
6. If a defect persists, say so and try a different hypothesis. Do not retry a
   fix that already failed.

**Screenshot recipe.** This is fiddly and the timings matter:

```bash
# One-time: the launch script needs a python3 with PIL. Homebrew's lacks it.
mkdir -p /tmp/pyshim && ln -sf /usr/bin/python3 /tmp/pyshim/python3
printf '#!/bin/zsh\nexport PATH="/tmp/pyshim:$PATH"\nexec zsh scripts/launch-dev-app.sh\n' > run-dev.sh

# Each round:
pkill -f "Open Island Dev"; zsh run-dev.sh >/dev/null 2>&1
# Session discovery takes ~20-30s after launch. Without the wait you get
# "Nothing running" and the empty room, not the feed.
cliclick w:30000 m:700,6 w:600 m:756,10 w:600 m:756,22
screencapture -x /tmp/feed.png
magick /tmp/feed.png -crop 1400x1300+780+0 +repage -resize 700x /tmp/feed-crop.png
```

Then **Read `/tmp/feed-crop.png`** and inspect it.

Known annoyances: the island collapses if the pointer drifts, so re-hover and
recapture rather than assuming a blank result means a bug. A foreground browser
window can cover the panel. If the capture shows the closed pill (a small dog
and `×N`), the hover did not take — try again.

**Enable the feature first**, or you will screenshot the old list:

```bash
defaults write app.openisland.dev app.showCompanion -bool true
```

---

## 5. Acceptance criteria

Done when a single screenshot of the running app shows all of:

- [ ] `Opus 5` reads in full at the left edge; the status word reads in full at
      the right edge (D1)
- [ ] Every timestamp shows complete, no leading digits cut (D2)
- [ ] No tool row wraps to a second line (D3)
- [ ] Turns are visually separable at a glance (D4)
- [ ] Build clean, zero warnings
- [ ] `swift test` at 5 issues, no more

Attach the screenshot to your final report. A claim that a layout defect is
fixed without a picture of it fixed is not accepted — three such claims have
already been wrong in this feature.

---

## 6. Environment traps

- **Never edit in the main worktree.** Work in
  `.claude/worktrees/feat+companion-pill`. The shell cwd has silently reverted
  to the main repo mid-session; `pwd` before building, or you will build code
  you did not change and see phantom passes.
- **`scripts/launch-dev-app.sh` rewrites 28 tracked brand icon files** as a
  side effect of launching, because it regenerates them with whatever Pillow is
  on PATH. Run `git checkout -- Assets/Brand` before staging, every time.
- **Worktree-isolated sessions refuse compound shell commands.** Split them, or
  write a script file and run that.
- **A MainActor-isolated helper called from a plain test crashes the runner
  with signal 5**, which looks like a build failure rather than an isolation
  error. Pure helpers belong outside the view — `FeedText` is out there for
  exactly this reason.

---

## 7. Out of scope

Parsers for Codex, Gemini and Cursor transcripts. Wiring the companion pose to
the feed. The completion card. Gifts, collection or any reward economy. Do not
start these without being asked.
