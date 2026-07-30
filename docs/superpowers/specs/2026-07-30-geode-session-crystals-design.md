# Geode — Ambient Session Crystals

**Date:** 2026-07-30
**Status:** Design approved, not yet implemented
**Scope:** One feature inside Open Island. Phase 0 is a kill gate.

## Summary

While an agent session runs, a procedurally-generated crystal grows in the island pill.
Its growth tracks real elapsed run time. When a session blocks on the human the crystal
freezes and desaturates — **the stop is the notification**. On a clean completion it "sets"
and is eligible for the day's shelf. On an interrupt it fractures.

There is no input. Nothing to click, tend, or decide. The user's agents work; the user gets
a rock. Over weeks they accumulate a shelf.

## Why this shape

Three independent design passes converged on exactly one mechanic surviving all criticism:
**freeze-and-desaturate as the notification channel**. It is useful whether or not the
collection layer ever ships, because it replaces a badge with a state change the user is
already glancing at.

Honest record of what is and isn't validated:

- **Validated externally:** demand for ambient always-visible companions during agent work
  (TBH: Task Bar Hero, ~43k Steam reviews in 2 months), and that macOS supply is zero because
  Wine renders such overlays' transparency opaque.
- **Not validated:** that this specific non-game form retains. TBH's evidence covers an idle
  *game*; Geode is not a game. This is a design bet, deliberately sized so being wrong costs
  weeks, not quarters.
- **Retracted:** an earlier framing claimed developers lose "dozens of dead 30-second windows
  a day" that this would fill. That figure was invented and the premise is rejected. Anything
  absorbing enough to fill a wait is a distraction with better branding. Geode targets the
  involuntary two-second glance instead.

## Non-goals

Explicitly out of scope. None of these are implied by shipping this feature:

- Any git or `gh`/forge watcher; no commit, PR, CI, or release signals
- Pets, creature rosters, evolution ladders, shareable badges, public profiles
- Any server, account, sync, or leaderboard
- Any paid tier, analytics tier, or telemetry SDK (forbidden by project guidelines)
- Live-wallpaper placement, Dock rendering, watch complication
- Token or usage-window consumption as a progression input (see Incentives)

## Design

### Live crystal

Every running session grows its own crystal in state. The pill **displays one at a time**.
Selection rule, in order:

1. If any session is stalled (`waitingForApproval` or `waitingForAnswer`), show that
   session's crystal. Stalls win because the freeze carries the alert.
2. Otherwise show the running session whose state changed most recently.
3. If no session is running, show nothing.

### Event mapping

| Source | Crystal behaviour | Audio |
|---|---|---|
| `sessionStarted` | Seed appears; growth begins | none |
| phase `.running` | A facet accretes every ~2s, up to the size cap | optional soft accrete tick, default off |
| `waitingForApproval` / `waitingForAnswer` | Growth halts; desaturates to matte grey | one `stall` cue |
| `actionableStateResolved` | Colour and growth resume | none |
| `sessionCompleted`, `isInterrupt != true` | 900ms "set" animation; becomes a specimen | `set` cue |
| `sessionCompleted`, `isInterrupt == true` | Fractures; still a valid specimen | `fracture` cue |
| habit awarded on set | Brief shimmer over the set animation | `rare` cue |

A fractured specimen is a legitimate, attractive collectible. It is a record, not a penalty.
Nothing in this feature may present a sad, dying, decaying, or reproachful state.

### Crystal form

All geometry is derived, never authored and never stored:

- **Seed** — stable hash of `sessionID`. Same session always yields the same crystal.
- **Hue** — the session's `AgentTool` brand colour, already defined in the app.
- **Size stage** — `clamp(floor(log2(1 + durationSeconds / 30)), 0, 6)`, giving 7 stages
  where stage 6 is reached around 32 minutes. Growth is asymptotic so long runs do not
  produce unbounded crystals.
- **Clarity** — reduced by stall count and by mean gate latency (see Quality).
- **Habit** — at most one rare variant, from the rule table below.

### Quality, and why it is not runtime

Size tracks runtime because size is the progress indicator. **Quality must not**, or the
feature rewards agents that flail: a developer who writes a tight prompt and gets a clean
result in 40 seconds would otherwise earn less than one who lets an agent thrash for 20
minutes. This is the same defect as rewarding token spend, and it is rejected for the same
reason.

`qualityScore` is computed per session from exactly two inputs:

- `stallCount` — count of `permissionRequested` + `questionAsked` events.
- `meanGateLatency` — mean seconds from each gate event to its matching
  `actionableStateResolved`.

Score falls as either rises. **Duration does not contribute at all.**

Two further facts are captured per session but feed the rarity rules rather than the score:
`completedCleanly` (`sessionCompleted` with `isInterrupt != true`, required for any
non-fractured specimen) and `maxConcurrency` (greatest number of simultaneously running
sessions during this session's lifetime).

### Rationing: live growth, scarce keepsakes

Every session grows a crystal live. **Only one specimen per calendar day is kept
permanently** — continuous accumulation is what turns ambient features into wallpaper, and
scarcity does the work that authored content otherwise would.

Selection for the day's shelf slot, in order: any specimen with a habit outranks any
without; then highest `qualityScore`; then longest duration; then earliest start.

"Day" means the local calendar day of the session's **start**. The expanded panel shows the
current day's specimens until that day closes, then collapses to the single kept one.
Hovering a specimen reveals repo, agent, and duration.

A 52-week "vein" strip renders kept specimens as silhouettes — the contribution-graph
pattern, in crystal.

### Rarity rules (v1 set)

Ordered; first match wins; at most one habit per specimen. All are computable from
`AgentEvent` plus timestamps and workspace name.

| Habit | Condition |
|---|---|
| Twinned | Two sessions of different agents complete cleanly within 60s of each other |
| Iridescent | Three or more sessions running concurrently at any point |
| Hollow | Clean completion, zero stalls, duration > 15 min |
| Deep | Clean completion, duration > 45 min |
| Flawless | Clean completion, zero stalls, duration < 60s |
| Rapid | Every gate in the session answered under 15s, minimum two gates |
| Inclusion | First session ever recorded in this workspace |
| Midnight vein | Session spans local midnight |
| Dawn | First session of the day, started before 06:00 local |
| Revenant | Clean completion immediately following an interrupted session in the same workspace |
| Chorus | Sessions from four or more distinct agents on the same calendar day (awarded to the last) |
| Marathon | Eight or more clean completions in one calendar day (awarded to the eighth) |

Habits are also computed for back-filled historical sessions, so a first launch honours
past firsts and populates the vein strip.

Frequency is strongly user-dependent by design — a developer who habitually starts before
06:00 earns Dawn most days, and that is correct, because the habit describes something true
about them. Roughly one specimen in forty is the target for a median user, not a guarantee.
Thresholds are tuning values, adjustable after Phase 3 observation without invalidating
stored records, because habits are recomputed rather than persisted.

## Architecture

### Placement

- **`OpenIslandCore`** — `GeodeState`, a pure reducer over `AgentEvent`, plus
  `CrystalForm` (seed → geometry parameters) and `GeodeRecord` (the persisted per-session
  fact row). No AppKit, no rendering, `Sendable` + `Codable` per project convention.
- **`OpenIslandApp`** — SwiftUI rendering of the live crystal in the pill, the shelf and vein
  views in the expanded panel, and audio cues.

Crystal state is derived from the event stream, never mutated independently. This mirrors the
existing rule that `SessionState.apply(_:)` is the single source of truth for session
mutations.

### Persistence and recomputability

Persisted per completed session, as JSON under Application Support: `sessionID`, `tool`,
workspace name, start, end, `isInterrupt`, `stallCount`, `meanGateLatency`,
`maxConcurrency`.

Geometry and habits are **never** persisted — always recomputed from the seed and the record.
Consequences: retuning form or rarity in a later version does not invalidate anyone's shelf,
there is no save-file to corrupt, and on first launch the shelf **back-fills from transcripts
already on disk**, so a new user opens a populated shelf rather than an empty one.

### Audio

Five cues — `stall`, `set`, `rare`, `fracture`, and an accrete tick that defaults to off —
synthesized via `AVAudioEngine`. No audio asset files ship. All cues respect the app's
existing mute toggle.

## Build order

**Phase 0 — legibility spike (kill gate).** A throwaway view rendering ~20 crystals at true
notch scale, roughly 22pt. If procedural variety does not read as visibly distinct at that
size, the live view degrades into a progress bar with extra steps and half the concept is
gone. **Stop and reconsider rather than proceeding.** One day of work to de-risk three weeks.

**Phase 1 — the mechanic.** Live growth, freeze-and-desaturate on stall, resume, set on clean
completion, fracture on interrupt. Three cues — `stall`, `set`, `fracture` — plus the
default-off accrete tick; the `rare` cue arrives with habits in Phase 3. Ships useful on its
own even if no collection layer follows.

**Phase 2 — the shelf.** `GeodeRecord` persistence, transcript back-fill, day's specimens and
kept-specimen selection, hover detail.

**Phase 3 — rarity and vein.** The twelve habit rules, shimmer treatment, 52-week vein strip.

## Testing

`GeodeState` and `CrystalForm` are pure, so they are unit-testable with Swift Testing:

- Size-stage boundaries, including the stage-6 cap
- `qualityScore` falls with stall count and with gate latency, and is invariant to duration
- Each of the twelve rarity rules fires on a minimal event sequence, and rule precedence
  holds when several match
- Day-slot selection, including all three tie-breaks
- Fracture on `isInterrupt == true`; freeze on both stall phases; resume on
  `actionableStateResolved`
- Same `sessionID` yields identical geometry across runs
- Records survive a save/load round trip

Phase 0 is judged visually, not by test.

## Risks

- **Legibility at 22pt** — the Phase 0 kill gate. Highest-severity risk.
- **Wallpaper decay.** Ambient desktop companions (Desktop Goose, Shimeji, Bonzi) are
  screenshotted, installed once, and abandoned within weeks. Rationing and unfakeable rarity
  are the intended mitigations; neither is proven.
- **Runtime-adjacent incentive.** Quality is decoupled from duration, but size is not, so
  long runs still look more impressive. Partially mitigated, not eliminated.
- **No external validation.** Cutting the game also cut the only outside evidence. Accepted
  deliberately, with scope sized to match.

## Process notes

- Work proceeds in a git worktree branched off `main`; never the primary checkout.
- Open Island's roadmap marks product ideas of this kind **"Conditionally Open — open an
  issue first."** An issue describing this feature must be filed and accepted before a PR
  lands. That decision belongs to the maintainer.
- Conventional commits; PR targets `main`; project is GPL-3.0.
