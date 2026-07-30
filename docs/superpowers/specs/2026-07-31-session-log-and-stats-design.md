# Session Log and Stats

**Date:** 2026-07-31
**Status:** Implemented — see the Implementation notes at the end
**Depends on:** the Geode shard shipped in `docs/geode-spec` (its in-memory tally is rewired to read from this log)

## Summary

An append-only log of finished agent sessions, and a Stats view built on it.

Open Island currently has **live gauges but no history**. `ClaudeUsageSnapshot` holds the
current 5-hour and 7-day percentages; the session registries persist *current* sessions so
they can be restored at launch; `GeodeState` deliberately never persists. Nothing records
what happened yesterday, so there is no trend, no record, and nothing to compare against.

Every property that makes stats worth returning to — personal bests, "ahead of last week",
the "I didn't realise I shipped that much" moment — is downstream of one small missing
thing: a durable record of finished work.

## Motivation, and what this deliberately is not

The mechanisms that make Strava and Wrapped genuinely sticky are **self-comparison**: you
against your own history. The mechanisms that spike and then churn are guilt-based —
streaks you can break, nagging, loss framing. They share a vocabulary and produce opposite
outcomes.

This design uses only the first kind. **There are no streaks in this spec**, and adding one
later should be treated as a product decision with a churn cost, not a free win.

## Non-goals

Explicitly out of scope. None is implied by shipping this:

- Cost or spend estimation in currency
- Per-repository or per-branch breakdowns
- Charts beyond a single sparkline
- Export, sync, sharing, or any server
- Streaks, goals, targets, or notifications about statistics
- Retroactive back-fill from historical transcripts (see Risks)

## The log

**Location:** `~/Library/Application Support/open-island/session-log.jsonl`
**Format:** JSON Lines — one `SessionLogRecord` per line.

JSON Lines rather than SQLite because the access pattern is append-then-scan, it needs no
schema migration, it is inspectable with `tail`, and it matches the newline-delimited JSON
idiom the bridge already uses. Volume is negligible: 50 sessions a day for a year is ~18k
lines, a few megabytes at most.

### Record

| Field | Type | Notes |
|---|---|---|
| `sessionID` | `String` | Identity for dedupe |
| `tool` | `AgentTool` | Which agent |
| `workspace` | `String?` | Workspace name when known |
| `startedAt` | `Date` | |
| `endedAt` | `Date` | |
| `wasInterrupted` | `Bool` | From `SessionCompleted.isInterrupt` |
| `stallCount` | `Int` | Permission + question events during the session |
| `meanGateLatency` | `Double?` | Seconds; `nil` when the session had no gates |

`Codable` and `Sendable`, per project convention.

### Append rule and dedupe

A record is appended when a session completes. **A session can legitimately complete more
than once** — Claude Code emits a turn-level `Stop` and a separate `SessionEnd` — so writing
blindly would inflate every downstream number.

The file stays strictly append-only; **dedupe happens at read time**. Records are collapsed
by `sessionID`, keeping the one with the latest `endedAt`. This avoids rewriting the file,
keeps appends atomic, and makes a duplicate append harmless rather than corrupting.

### Failure behaviour

Logging is best-effort and must never affect agent monitoring. A failed append is dropped
with a single log line and no user-visible error. A malformed line encountered during read
is skipped rather than aborting the load, so one bad write cannot destroy the history.

### Retention

No pruning in v1. At the volume above this is safe for years. Revisit if the file passes
roughly 100k lines.

## Stats

`SessionStats` — a pure, testable type computing a summary from `[SessionLogRecord]` for a
range. No file access, no `Date()` inside; the caller passes `now`.

**Ranges:** Today, 7 days, All time. "Today" means the local calendar day of `endedAt`.

**Two terms, used precisely throughout:** a **finished** session is any completed session;
a **clean finish** is one with `wasInterrupted == false`. Every metric below states which it
uses, because conflating them is how a "sessions today" number ends up disagreeing with the
shard tally beside it.

**Per range:**

- **Finished** sessions, and **clean finishes**, as two numbers
- Split by agent over **finished** sessions, rendered in the existing
  `AgentTool.brandColorHex` colours
- Total agent runtime, summed `endedAt - startedAt` over **finished** sessions
- **Median of the per-session `meanGateLatency` values**, across sessions that had at least
  one gate. Deliberately a median of per-session means rather than a pooled median over all
  gates, so one session with forty gates cannot dominate the figure.
- Interrupted rate: interrupted ÷ **finished**

**Comparison — the part that makes it worth reopening:**

- **Trailing 7 days versus the prior 7 days**, as a delta on **clean finishes**. Trailing
  windows rather than calendar weeks, so the comparison is meaningful on every day of the
  week rather than degenerate on a Monday.
- **Personal best day** — the highest count of **clean finishes** in a single local calendar
  day — and how today stands against it.
- A **7-day sparkline** of daily **clean finish** counts.

Comparison metrics use clean finishes throughout, so the headline number matches the shard
tally in the pill and an interrupted session can never inflate a personal best.

## Architecture

- **`OpenIslandCore`**
  - `SessionLogRecord` — the row. `Codable`, `Sendable`.
  - `SessionLogStore` — append and load. File IO only; no statistics. Follows the existing
    Application Support pattern used by `CodexSessionTracking`.
  - `SessionStats` — pure computation over records. No IO, no ambient clock.
- **`OpenIslandApp`**
  - `StatsSettingsPane` — a new **Stats** tab in Settings, alongside General and
    Personalization.
  - `AppModel` appends on completion, from the same `applyTrackedEvent` ingress that already
    feeds `SessionState` and `GeodeState`.

Splitting the store from the statistics is the point: `SessionStats` stays a pure function
over values and is fully testable without touching the filesystem.

## Rewiring the shard tally

The Geode tally currently counts clean finishes in memory and resets on restart. It moves to
`SessionStats`, reading the log. That is the difference between a counter and a statistic,
and it is the smallest visible payoff of this work.

## Localization

The Stats tab needs English and Simplified Chinese strings, per the project's bilingual
requirement. New keys under `settings.tab.stats` and `settings.stats.*`.

## Testing

`SessionStats` and dedupe are pure, so they are unit-testable with Swift Testing:

- Duplicate `sessionID` collapses to one record, keeping the latest `endedAt`
- Today counts only the local calendar day of `endedAt`, including a session that started
  yesterday and ended today
- Trailing-7 versus prior-7 deltas, including the boundary day
- Median gate latency ignores sessions with no gates, rather than treating them as zero
- Interrupted rate excludes unfinished sessions
- Personal best is per local calendar day
- Round trip: append then load returns equal records
- A malformed line is skipped and the remaining records still load
- Empty log produces zeroes, not crashes or nils

## Risks

- **No back-fill.** Stats start empty on first launch, so the feature is unimpressive for the
  first few days — exactly when a user decides whether to care. Back-filling from the ~1,249
  existing transcripts on disk would fix that, and is deliberately deferred because
  transcript parsing for historical sessions is a larger job than the log itself. Worth
  reconsidering before release.
- **Timezone and DST.** All day bucketing uses the local calendar. A user crossing timezones
  will see days shift. Accepted.
- **Statistics could feel like surveillance of oneself.** Mitigated by having no targets and
  no notifications: the numbers never ask anything of the user.

## Process

- Work continues in the existing worktree on `docs/geode-spec`, or a fresh branch off `main`
  if the Geode work merges first.
- Open Island's roadmap marks product ideas "Conditionally Open — open an issue first." An
  issue must be filed and accepted before a PR lands. That decision is the maintainer's.
- Conventional commits; PR targets `main`; project is GPL-3.0.


## Implementation notes — 2026-07-31

Shipped on `docs/geode-spec`. Deviations from the design above, all deliberate:

**Back-fill was built, not deferred.** The spec listed it under Risks as "worth
reconsidering before release". It was promoted because empty stats on day one is the
single biggest threat to the feature landing, and the user had ~1,249 transcripts sitting
on disk. Against real data it yields 55 historical sessions.

**Back-fill derives end times from the last in-transcript timestamp, not file mtime.**
Probing real data with mtime produced a "session" of 104 hours, because a resumed session
rewrites its mtime days after the work happened. Spans over 12 hours are now excluded
outright rather than clamped — clamping would be inventing a duration. This moved the
derived count from 115 to 55, all of them true.

**Back-fill reads only the head and tail of each transcript.** Reading all 1,249 files in
full took 27 seconds; head-and-tail takes 0.86.

**Session logging starts from the app entry point, not `AppModel.init`.** Doing filesystem
work in `init` meant every `AppModel` constructed in a test read the real log and walked
every transcript — the suite went from 1.5s to 6.4s and gained failures. It is also skipped
under a harness scenario so smoke runs stay deterministic.

**Stats also appear in the island panel**, not only in Settings: the session-list header
carries today's clean finishes and the week-over-week delta. A statistic nobody sees
motivates nobody. It is hidden entirely at zero, so it never reads as a reproach.

**Observed on real data at time of writing:** 6 finished today, 31 in the last 7 days
against 8 the week before, best day 8, 131 agent-hours all time.

**Still not done:** the `AppModelSessionListTests` and `AgentsGridRightSlotTests` suites
fail with 6 issues, reproduced identically on a pre-change baseline worktree. Those tests
leak real `UserDefaults` and are environment-dependent. Not caused by this work, and worth
a separate fix.
