# Island Panel — Feature-Loop Backlog (spec items 5–9)

> **For the loop:** one task per iteration. Build via
> `superpowers:subagent-driven-development`. Gate is `zsh scripts/harness.sh ci`
> (lint → docs → test → build). Never weaken the gate to pass it.
>
> **Integration strategy — read this first.** Tasks land as commits on
> `feat/island-creature`, not as one PR each. The usual one-PR-per-task rule assumes a
> human merges between iterations; running unattended overnight nobody does, and every
> task here depends on the previous one being `[done]` — so a strict PR gate would open
> one PR and stall for eight hours.
>
> The safety property is preserved where it actually lives: **`main` is never touched, and
> a human still merges.** `feat/island-creature` is itself an unmerged topic branch; the
> whole run becomes a single reviewable PR to `main` at the end. Per task the loop must
> still: keep the gate green, commit surgically, and mark status in this file. A task that
> cannot go green honestly flips to `[blocked — reason]` and the loop moves to the next
> eligible task rather than grinding.

**Goal:** finish the island reward layer inside Open Island. The pill half ships already
(`206d5bb`); this backlog is the opened panel, the receipt, collection, and customisation.

**Spec:** `docs/superpowers/specs/2026-08-01-island-reward-mechanics-design.md`
**Branch base:** `feat/island-creature`
**Gate:** `zsh scripts/harness.sh ci` — currently green at 482 tests.

---

## ASSUMPTIONS (override any of these)

These are my calls, not yours. Each is cheap to reverse if wrong — say so and the loop adjusts.

1. **Panel ground is the island scene, not warm paper.** The reference uses paper; we have a
   painted island that measured well. Creatures at L 16% clear 3:1 on both, so either works.
   I chose the island because it is ours rather than borrowed.
2. **Everything stays behind the existing preference.** No default changes. A user who never
   opens Personalization sees exactly today's app.
3. **Collected objects persist in the existing session log**, not a new store. One append-only
   file already survives relaunch and is back-filled; a second store would need its own
   migration story for no gain.
4. **Rarity is computed, never stored.** It is a pure function of facts the log already has
   (duration, stalls, interrupts), so a rule change re-rates history instead of stranding it.
5. **Voice lines ship English-only in this pass.** The app is bilingual (en + zh-Hans/Hant);
   flavour text is a large translation surface and should not block the mechanic. Task 10
   wires them through `LanguageManager` so translation is additive later.
6. **No git/PR watcher.** ★★★★ rarity and the "shipped" reward stay unimplemented — the spec
   already records them as depending on collection we do not do.
7. **Panel scene is a fixed band, not scrollable.** Measured ceiling is five visible stations;
   beyond that overflow collapses to counted dots.
8. **Structures resolve from the existing jump target**, which already knows the terminal.
   No new detection.

---

## [done] 1 — Structure mapping: terminal/IDE → structure asset

Pure model, no UI. The panel needs to know which building a session's terminal maps to, the
same way `CreatureSpecies` maps ten agents onto six bodies.

**Acceptance criteria (this becomes the test):**
- `CreatureStructure` enum with exactly 5 cases: `terminal`, `multiplexer`, `editor`, `tower`, `workshop`
- An initialiser from whatever the app already uses to identify a terminal/IDE — find it,
  do not invent a parallel type
- Terminal.app, Ghostty, iTerm2, WezTerm, Kaku, cmux → `.terminal`
- tmux, Zellij, Orca → `.multiplexer`
- VS Code, Cursor, Windsurf, Trae → `.editor`
- JetBrains family → `.tower`
- Anything unrecognised → `.workshop` (never nil, never a crash)
- Every case has shipped artwork in `Resources/World/` — assert it resolves, because a
  missing sprite fails silently
**Build with:** `superpowers:test-driven-development`  **Review with:** `swift-testing-pro`
**Likely files:** `Sources/OpenIslandCore/CreatureStructure.swift`, tests
**Depends on:** nothing

## [done] 2 — IslandSceneView: the panel scene band

The painted island with creatures standing at stations. Rendering only — no interaction yet.

**Acceptance criteria:**
- New file, not added to `IslandPanelView.swift` (already 2776 lines)
- Renders the island background from `Resources/World/`
- Up to 5 sessions as `CreatureView` at evenly spaced stations; station pitch ~118pt at 540 wide
- 6th and beyond collapse to a counted overflow indicator, not a 6th creature
- Each creature's structure drawn behind/beside it
- Deterministic: same sessions in the same order produce the same layout
- Renders with zero sessions without crashing or looking broken
**Build with:** `swiftui-design`  **Review with:** `swiftui-pro` + `hig-foundations`
**Likely files:** `Sources/OpenIslandApp/Views/IslandSceneView.swift`
**Depends on:** 1
**Known from task 1:** `terminalApp` lives on **`JumpTarget`**, not `AgentSession` — reach it
as `session.jumpTarget?.terminalApp`, and handle the nil case (a session with no known jump
target still has to render; it falls to `.workshop`). `tmux` never appears in `terminalApp`;
it is carried separately on `JumpTarget.tmuxTarget`, so a tmux session currently draws as its
outer host. Showing it as `.multiplexer` would be a call-site change, deliberately out of
scope here — note it, do not silently add it.

## [done] 3 — Identity strip

The text band under the scene. The picture carries state; this carries identity — that
split is the design's core clarity rule and must not blur.

**Acceptance criteria:**
- One cell per visible session: agent name, terminal, workspace, elapsed
- Cell for a session needing attention is visually distinct
- Truncates gracefully at 540pt; never wraps to two lines
- Contains no mood/state colour language beyond the attention highlight
- Empty state reads as deliberate, not broken
**Build with:** `swiftui-design`  **Review with:** `swiftui-pro` + `hig-foundations`
**Likely files:** `Sources/OpenIslandApp/Views/IslandSceneView.swift` or a sibling
**Depends on:** 2

## [done — with a recorded limitation] 4 — Selection and detail band

Clicking a creature selects its session and fills a detail row.

**Acceptance criteria:**
- Tapping a creature selects that session; tapping again deselects
- Detail band shows the pending question (if any), wait time, runtime, stall count
- Reuses the app's existing selected-session state — do not add a second source of truth
- Keyboard accessible; not mouse-only
**Build with:** `swiftui-design`  **Review with:** `swiftui-pro` + `hig-foundations`
**Depends on:** 3

## [todo] 4b — DECISION NEEDED: should a deselect survive an agent event?

Task 4 built the toggle and it is correct and tested. But `AppModel.synchronizeSelection()`
owns `selectedSessionID`, runs from **10 call sites** including every bridge event, and:

- re-populates `nil` with `surfacedSessions.first` — so **a deselect lasts until the next
  agent event**, then silently undoes itself
- gives selection to any session needing attention **unconditionally**, overriding whatever
  the user picked

So "tap again to deselect" is half-implemented through no fault of the implementation. Making
it durable means changing which session the whole panel focuses on after every event — a
behaviour change well beyond the island, and not something to make unattended at 4am.

**This task is a human decision, not a build.** Options: (a) accept it and document the
deselect as transient; (b) let an explicit user deselect suppress re-population until the next
attention event; (c) leave selection alone entirely and have the island read `focusedSession`.
The loop must NOT pick one. Skip this task and continue.

Also found: `AppModel.select(sessionID:)` (`:1393`) has zero callers — pre-existing dead code,
left alone per the surgical-scope rail.

## [done] 5 — Click-to-jump

The payoff that makes this a tool rather than decoration: the gesture *is* the notification
and the click *is* the jump-back the app already implements.

**Acceptance criteria:**
- Clicking a creature in `waiting` pose invokes the existing jump-back for that session
- Uses `TerminalJumpService` as-is; no reimplementation
- Falls back safely when no jump target is known
- Existing jump tests still pass untouched
**Build with:** `superpowers:test-driven-development`  **Review with:** `swift-concurrency-pro`
**Depends on:** 4

## [done] 6 — Reward objects: model and rarity

Pure model. What a finished session yields and how good it is.

**Acceptance criteria:**
- `RewardObject` enum covering the 13 shipped object assets
- `rarity(for:)` computed from session facts only — never stored
- ★ any clean completion; ★★ clean + zero stalls + all gates answered inside the grace
  window; ★★★ clean + ≥30min + zero stalls; a session with no gates satisfies ★★ vacuously
- Interrupted sessions yield `scrap`, never an object
- Deterministic: the same session always yields the same object
- ★★★★ deliberately unreachable (needs the unbuilt git watcher) and that is asserted
**Build with:** `superpowers:test-driven-development`  **Review with:** `swift-testing-pro`
**Depends on:** nothing

## [done] 7 — Collection: earning and persisting objects

**Acceptance criteria:**
- A clean completion yields its object; an interrupt yields scrap
- Collected objects survive relaunch via the existing session log — no new store
- Back-filled historical sessions rate correctly rather than being skipped
- No double-award if a session is reconciled twice
- **Carried from task 6:** consider recording the **worst** gate latency alongside `meanGateLatency`.
  ★★ currently measures "no gate past grace" by the mean, which is a one-sided approximation — it
  never denies a qualifying session, but 1s + 59s averages to exactly 30s and slips through. This
  task owns what gets written to the log, so it is the only place that can close it. If you add it,
  update `RewardRarity` to use it and delete the approximation test; if you do not, say why.
**Build with:** `superpowers:test-driven-development`  **Review with:** `swift-testing-pro`
**Depends on:** 6

## [done] 8 — The receipt

`Open Island Inc.` Cheapest high-charm item in the spec: pure typography over numbers that
already exist.

**Acceptance criteria:**
- Reads `SessionStats` — no new computation, no new storage
- Line items: sessions run, clean finishes, answers inside grace, interrupted, time kept
  waiting, best run, TOTAL
- Positive lines and negative lines visually distinct
- Torn-paper treatment, monospaced figures
- Correct for a day with zero sessions
**Build with:** `swiftui-design`  **Review with:** `swiftui-pro` + `hig-foundations`
**Depends on:** 7
**Known from task 5:** `lastActionMessage` is never rendered — its only readers are
`OpenIslandApp.swift:22` and `HarnessRuntimeMonitor`. Any failure the island needs a user to
actually *see* has to surface in the detail band, not that property.

## [done] 9 — Customisation surface

**Acceptance criteria:**
- Island on/off in `AppearanceSettingsPane`, off by default
- Scene height: compact / standard / tall
- Honours existing `sessionGroup` for station ordering rather than inventing a parallel one
- Reuses `staleThreshold`; does not add a second staleness concept
- With the island off, panel behaviour is identical to today — assert it
- A preference write must not change the active appearance profile (see `e79a005`)
- **Localization debt from task 3:** the identity strip ships English literals
  (`emptyMessage`, `hostLabel`, the accessibility sentence). The app is bilingual
  (en + zh-Hans/Hant). Nothing is user-visible until the strip is composed into the
  panel — which happens here — so this task must run the localization pass rather
  than shipping untranslated UI.
**Build with:** `swiftui-design`  **Review with:** `swiftui-pro` + `hig-foundations`
**Depends on:** 8
**Known from task 9, for 10–12:**
- The island is now composed into the panel. `AppModel.islandBandLayout(width:now:)` is the
  single entry point — it returns `nil` when the island is off and owns which sessions stand
  where. `IslandPanelView` renders whatever it returns and decides nothing, so island
  behaviour is testable without a view.
- **Profile trap for any test that enables the island.** `loadDebugSnapshot` calls
  `overlay.applyOverlayState`, which can re-resolve placement and therefore flip
  `activeAppearanceProfile`. A preference written *before* the snapshot lands in one profile
  and is read back from the other, and the island silently stays off. Write the preference
  **after** `loadDebugSnapshot`, or write both profiles via
  `updateAppearancePreferences(for:)`. This is by design, not the `e79a005` bug.
- Localization is done for the strip, the detail band and the receipt, and
  `LanguageManager(language:)` gives a pinned manager that neither reads nor writes the
  stored preference — use it for any test asserting on text. Task 10's voice lines can
  therefore be additive rather than needing their own pass.
- `LocalizationTests.everyLocaleDefinesTheSameKeys` now enforces key parity across en /
  zh-Hans / zh-Hant. Any new key must be added to all three or the gate fails.

## [done] 10 — Voice lines

**Acceptance criteria:**
- ~12 lines per species, shown on clean completion
- Routed through `LanguageManager` so translation is additive
- Deterministic per session; not random on every render
- Never shown for an interrupt
**Build with:** `swiftui-design`  **Review with:** `swiftui-pro`
**Depends on:** 9
**Known from task 10, for 11–13:**
- **ASSUMPTION 5 above is now dead and should be read as overridden.** It says voice
  lines "ship English-only in this pass" and that task 10 only wires them up for
  translation later. Task 9 added `LocalizationTests.everyLocaleDefinesTheSameKeys`,
  which fails the gate on any key missing from zh-Hans or zh-Hant — so "English-only"
  and "routed through `LanguageManager`" cannot both hold. All 72 lines ship in all
  three locales; 216 strings.
- `CreatureVoice` (Core) picks the line and returns a **key**; the app resolves it.
  `CreatureVoice.lineKey(for: shard)` returns `nil` for anything that is not the
  `holding` pose, so "never for an interrupt" is a property of the function rather
  than of its callers. `CreatureVoice.allLineKeys` is what the localization gate
  iterates — add species there and the gate demands their translations.
- Seeded `ShardSeed.value(for: "voice:" + sessionID)`. The salt is load-bearing:
  `RewardObject.yield` takes the *same* first `SplitMix64` draw from the *unsalted*
  seed and reduces it mod 4, so without the prefix the object index would be exactly
  the line index mod 4 and a coin would only ever pair with three of twelve lines.
- The line is drawn as an **overlay on the scene band**, not as a fourth band, so it
  costs no height — `IslandBandLayout.height` is unchanged and the session list does
  not move when a session finishes. It lives for `GeodeState.lingerWindow` (45s) and
  the newest clean completion takes it from any older one.
- The scene band is `accessibilityHidden(true)` on the grounds that everything in it
  is also carried in words by the identity strip. The caption is the first exception:
  it is applied by `IslandBandView` from *outside* `IslandSceneView`, so it stays
  reachable by VoiceOver, and its label names the speaker because position — the
  whole of the visible attribution — is not available to a screen reader. Anything
  else added to the scene has to keep that promise or move the words into the strip.
- Task 12's demo pass has something real to look at here that no test can check:
  whether a 180pt plate above a creature's head reads well at each scene height, and
  whether it collides with the overflow badge in the top-right corner at `compact`.

## [in-progress] 11 — Pin creature rendering in debug scenarios

Carried over from the pill plan, never done.

**Acceptance criteria:**
- `@MainActor` test driving `AppModel.loadDebugSnapshot`, mirroring `GeodeDebugScenarioTests`
- Every live session in a scenario yields a renderable creature
- Must not write `islandRightSlot` — that writes shared `UserDefaults` and is the known
  source of flakiness in this target
**Build with:** `superpowers:test-driven-development`  **Review with:** `swift-testing-pro`
**Depends on:** nothing

## [todo] 12 — Demo readiness: prove it actually runs

The backlog is not "done" when tests pass — it is done when the feature works in the real
app. Tests prove the parts; this proves the whole.

**Acceptance criteria:**
- `swift build -c release` succeeds
- The app launches without crashing and stays up for at least 20 seconds
- With the island preference ON, loading each `IslandDebugScenario` renders the panel
  without crashing — assert via the debug-snapshot path, not by driving the UI
- With the island preference OFF, every existing panel test still passes untouched
- `zsh scripts/harness.sh ci` green, and `zsh scripts/creature-gate.sh` still exits 0
- Writes `docs/DEMO-READINESS.md` stating what was verified mechanically and what still
  needs a human eye — being explicit that "it renders without crashing" is not the same
  claim as "it looks right in the notch", which no automated check here can make
**Build with:** `superpowers:verification-before-completion`  **Review with:** none
**Depends on:** 11

## [todo] 13 — Reconcile the spec with what was actually built

The spec still describes decisions the build overtook.

**Acceptance criteria:**
- Records the L 11.2–22.7% two-ground band and that the luminance ladder is gone
- Records that Task 7's window overhang was skipped and why
- Records the `.process` flattening and the `rawValue` filename coupling
- Removes dead `panelColor(for:)` / old `panelGround` if still unused
- `zsh scripts/check-docs.sh` passes
**Build with:** none  **Review with:** none
**Depends on:** 11
