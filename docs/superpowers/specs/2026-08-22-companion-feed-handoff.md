# Companion feed — handoff

Date: 2026-08-22
Branch: `worktree-feat+companion-pill` (worktree at `.claude/worktrees/feat+companion-pill`)

> **Status: §2's four defects are closed.** D1's cause was not the one guessed
> below — see §2.1. §3, §4 and §6 still stand and are still the right way to
> work on this view; §6 has one more trap in it now.

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

## 2.1 How they were closed

**D1 was the clip mask, not the content.** `OpenedIslandSurfaceShape` in notch
mode is a `NotchShape`, and that path does not span its rect: below the concave
top curve its straight sides sit at `rect.minX + topR` and `rect.maxX - topR`,
with `topR = 22`. `IslandPanelView.openedSurface` frames content at the full
`openedWidth` and then clips it to that path, so 22pt is masked off each side —
symmetrically, which is exactly what the screenshot showed. Nothing was ever
overflowing, which is why `.frame(maxWidth: .infinity)` and the `GeometryReader`
both changed nothing.

Every other surface in the panel already compensates: `sessionListSideInset` is
46 in notch mode (22 clip + 24 visual) and `notchHeaderHorizontalPadding` is 46
too. The feed had a hardcoded 13 and lost nine points of glyphs per side. It now
takes `sideInset` from the panel like everything else. The `GeometryReader`
wrapper is gone with it — it was load-bearing for a diagnosis that was wrong.

**D2** — `FeedClock.stamp` pins a 24-hour `%02d:%02d`. There is no room for a
meridiem marker at 9pt and no reading of the feed needs one.

**D3** — action rows carry `.lineLimit(1)`, and the tool-name column widened to
52 so `todowrite` is not truncated to initials.

**D4** — `FeedTurns.grouped` splits the flat feed into turns (prose, plus the
tools it triggered). Within a turn rows sit 3–4pt apart under one continuous
spine; between turns the gap is 16pt. The clock prints **once per turn**, on its
first row — repeating it made every row look like a separate event, and printed
once it turns the left gutter into a turn counter you can read at a glance.

Both new helpers are pure and live outside the view, next to `FeedText`, for the
reason §6 gives. Tests in `Tests/OpenIslandAppTests/FeedTurnsTests.swift`.

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
3. `swift test 2>&1 | grep "Test run with"` — expect **0 issues**.
   This used to say five, and those five were never a property of the branch:
   `AppModelSessionListTests` and `AgentsGridRightSlotTests` now pass untouched,
   over repeated runs, with no change to their code. They were order- or
   environment-dependent. Treat any non-zero count as a real failure and read
   it, rather than subtracting an expected number from it.
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
- [ ] `swift test` green — 0 issues

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
- **The launch script fails silently and leaves you on the old binary.** It is
  `set -e`, and the brand-icon step runs before the step that copies the new
  build into the bundle. Homebrew's python3 has no Pillow, so `run-dev.sh` puts
  a shim for the system one first on PATH — and that shim lives in `/tmp`, which
  gets cleared. When it vanishes the brand step dies, the script aborts *before*
  the copy, and the app you relaunch is whatever was in the bundle before. If
  you also redirect the output to `/dev/null` you will screenshot a day-old
  build and disbelieve your own code. `run-dev.sh` now rebuilds the shim on
  every run; check the bundle's mtime if a change refuses to appear.
- **More than one Open Island can own the notch.** `swift run OpenIslandApp`
  from the main checkout and `~/Applications/Open Island Dev.app` both draw an
  overlay, and whichever is on top answers the hover. `ps aux | grep
  OpenIslandApp` before concluding anything about what you are looking at.
- **Worktree-isolated sessions refuse compound shell commands.** Split them, or
  write a script file and run that.
- **A MainActor-isolated helper called from a plain test crashes the runner
  with signal 5**, which looks like a build failure rather than an isolation
  error. Pure helpers belong outside the view — `FeedText` is out there for
  exactly this reason.
- **Move the pointer off the notch before running `swift test`.** The screenshot
  recipe parks it there, and `OverlayUICoordinator.updateNotificationAutoCollapse`
  reads `NSEvent.mouseLocation`: with the pointer inside the expanded area it
  takes the "pointer is already here" branch and schedules no timer, so
  `completionNotificationHoverCancelsPendingTimedCollapse` fails and you count 6
  issues instead of 5. `cliclick m:400,900` first, and the sixth goes away.

---

## 7. Out of scope

Parsers for Codex, Gemini and Cursor transcripts. Wiring the companion pose to
the feed. The completion card. Gifts, collection or any reward economy. Do not
start these without being asked.
