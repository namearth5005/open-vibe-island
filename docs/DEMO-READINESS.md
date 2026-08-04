# Island reward layer — demo readiness

Written 2026-08-04 at the end of the `feat/island-creature` feature loop, on commit `6808a78`.

This document exists because a passing test suite is not the same claim as "this works". Everything
below is split into what was **verified mechanically** and what **still needs a human eye**. The
second list is the more useful one.

**One-line summary:** the code is demo-ready as far as any automated check on this machine can
establish. Nobody has yet looked at it running in a real notch, and there is one hazard (below) that
will bite a live demo if it is not known about.

---

## Verified mechanically

| Criterion | Verdict | Evidence |
|---|---|---|
| `swift build -c release` succeeds | **proven** | `Build complete!`, exit 0 |
| `zsh scripts/harness.sh ci` green | **proven, with a caveat** | 708 tests / 73 suites; see *flaky test* below |
| `zsh scripts/creature-gate.sh` exits 0 | **proven** | exit 0 |
| Island **ON** renders every debug scenario without crashing | **proven** | `IslandDebugScenarioCreatureTests` drives `AppModel.loadDebugSnapshot` over `IslandDebugScenario.allCases` with `islandScene = .on`, three assertions per scenario |
| Island **OFF** leaves the panel as it was | **proven** | `IslandCustomisationTests`: layout returns `nil` and height returns `0` at *every* scene height, plus grouping and ordering asserted byte-identical across off → on → off |
| Off by default | **proven** | asserted in both appearance profiles *and* against the struct default, which is a separate source of truth |
| App launches and stays up ≥20s | **NOT PROVEN — deliberately not attempted** | see below |

### Why the launch test was not run

**This is the most important finding in this document.**

`BridgeServer.bindListener` (`Sources/OpenIslandCore/BridgeServer.swift:117`) unconditionally deletes
any existing socket file before binding:

```swift
try? FileManager.default.removeItem(at: url)
```

There is **no single-instance guard** anywhere in the app.

So a second Open Island instance does not fail to start, and does not warn. It deletes the socket the
first instance is listening on, binds its own at the same path, and **silently takes over the
bridge**. The first instance keeps its file descriptor and carries on looking healthy, but no new
agent hook connection will ever reach it again. `stop()` deliberately does not unlink the socket
(there is a comment explaining the race that motivated this), so the takeover is not cleaned up on
exit either.

At the time of verification a developer instance had been running from this worktree for 3 days 17
hours. Launching a second one would have silently broken it, so the launch criterion was left
unproven rather than bought at that price.

**This is a live demo hazard, not just a testing inconvenience.** If you have the dev app running and
then launch the release build to demo it, the demo instance steals the bridge and the other goes deaf
— with no error in either. Before demoing, confirm exactly one Open Island is running:

```sh
pgrep -fl OpenIslandApp
```

Whether this is worth fixing (a single-instance check, or an explicit takeover message) is a product
decision, not a loop decision. It is pre-existing behaviour, not something this branch introduced.

### The flaky test

`completionNotificationHoverCancelsPendingTimedCollapse`
(`Tests/OpenIslandAppTests/AppModelSessionListTests.swift:836`) failed **twice in ~20 full-suite
runs** and passed 5 out of 5 when run in isolation.

The failing assertion is the *positive* one: `hasPendingNotificationAutoCollapse` was `false`
immediately after `notchOpen(reason: .notification, …)`, i.e. the auto-collapse had not been
scheduled yet when the test looked. That points at a scheduling race in the notification
auto-collapse path, not at a wrong result.

**It is load-correlated.** Both failures happened while the machine's load average was ~290 (a
normal-but-busy desktop: browsers, CoreSimulator, other tooling — nothing to do with this branch).
The same suite that completes in ~2s idle took 30s during a failing run. No leftover build or test
processes were involved. So this is a race that widens under contention, which means **CI and a busy
demo machine are exactly where it will show up**, and a green run on an idle machine is weak evidence
that it is fine.

It is **pre-existing and unrelated to the island** — this branch does not touch notification
collapse. It is recorded here rather than fixed because fixing it is out of this loop's scope, and
because it touches notification behaviour, which *is* part of a demo: if the pending-collapse
scheduling can lose a race in a test, it can plausibly do so in the app.

### An environment side effect that was cleaned up

During verification, launching the app persisted `appearance.island.v8.{notch,topBar}.scene = on`
into the real `OpenIslandApp` user defaults domain. Those four keys (`scene` and `sceneHeight`, both
profiles) were deleted, restoring the shipped default — absent key resolves to `.off` / `.standard`,
so deletion restores the exact prior state rather than guessing a value. All other preferences in
that domain were left untouched.

Worth knowing: **running the app writes the island preference to your real defaults.** A demo machine
that has ever had the island switched on will keep it on.

---

## Needs a human eye

Nothing in this section is a defect. These are claims no automated check on this machine can make.

### 1. Nobody has seen the creature in a real notch

The pill artwork was gated on **measured contrast**, not on looking at it. The two-ground constraint
(near-black pill at L 0.4%, light paper at L 78.2%) was solved numerically and every species sits in
the viable band at ≥3.7:1 against both. That is a proof the creature *can* be distinguished from its
background. It is not a proof it looks good at 28pt on a physical display, at your screen brightness,
at arm's length.

**Look at:** whether the creature reads as a creature or as a smudge; whether the waving frame is
noticeable enough to function as a notification without being annoying; whether the two wave frames
alternating at 0.45s looks like a wave or a twitch.

### 2. The voice-line plate is unverified visually

Task 10 flagged this explicitly. A ~180pt caption plate is drawn as an overlay above the speaking
creature's head for 45 seconds. Its geometry is asserted (it costs the band no height; it fits inside
both panel widths; one line was shortened after a fit test caught it overflowing 170pt into 164pt).

**Its appearance is not asserted at all.** Specifically unknown:
- whether it reads well at each of the three scene heights
- whether it **collides with the overflow badge** in the top-right corner at `compact`
- whether a plate hanging over a neighbouring creature is charming or confusing

### 3. The profile trap is untested, not absent

`loadDebugSnapshot` calls `overlay.applyOverlayState`, which can re-resolve placement and therefore
flip `activeAppearanceProfile`. A preference written *before* the snapshot can land in one profile
and be read back from the other, leaving the island silently off.

Task 11 instrumented this and found it **does not manifest headlessly** — there are no overlay
placement diagnostics in a test process, so `activeAppearanceProfile` stayed `topBar` throughout for
all six scenarios. The defensive write-ordering is therefore *untested*, not *proven safe*. On a
notch Mac it may well be live.

**Watch for:** switching the island on in Settings and having it appear not to take effect, or
appearing to work on the built-in display but not on an external one (or vice versa).

### 4. Two open decisions ship with defaults, not answers

Both are recorded in the backlog and were deliberately not decided unattended.

**`4b` — a deselect does not survive an agent event.** `AppModel.synchronizeSelection()` runs from 10
call sites including every bridge event, re-populates `nil` with `surfacedSessions.first`, and gives
selection to any session needing attention unconditionally. So "tap again to deselect" works and then
silently undoes itself at the next event.

*What a demo shows today:* tapping a creature selects it and the detail band follows. Tapping again
deselects. If any agent event arrives in between, selection comes back on its own. Don't build a demo
beat around deselection.

**`11b` — a blocked session can be pushed off the island under `.project` grouping.** The scene caps
at five plots. Under the shipped default (`sessionGroup == .none`) ranking puts attention first, so a
blocked session always gets a plot. Under `.project`, sections sort alphabetically by workspace, so a
session that is asking for you can be pushed into the `+N` badge while the closed pill is still
signalling for it.

*What a demo shows today:* the shipped default is safe. **Do not demo `.project` grouping** with more
than five sessions and a blocked one, or the notch will say someone needs you while the panel does
not show them.

### 5. What was never built

- **★★★★ rarity and the "shipped" receipt line** both depend on a git watcher that does not exist.
  The receipt deliberately omits a `shipped` line rather than printing a permanent `0` — a line that
  always reads zero teaches the reader the receipt lies.
- **The island is composed but its bands were built standalone.** Tasks 5–8 (click-to-jump, reward
  objects, collection, receipt) each landed as views wired to real data, and task 9 composed them.
  The receipt lives in the **Stats pane gated on `range == .today`**, not the panel — a deviation
  from the spec, which put it in the panel. It is a record, not live state, and `Receipt` is
  hard-wired to `StatsRange.today`, so showing it beside a seven-day grid would let the paper
  contradict the numbers under it.

---

## Suggested demo path

1. `pgrep -fl OpenIslandApp` — confirm **exactly one** instance, per the bridge hazard above.
2. Settings → Appearance → turn the island on. Leave grouping at the default.
3. Open the panel with a few live sessions. Check the creatures stand on structures matching their
   terminal/IDE, and that the identity strip names line up with the stations above them.
4. Let a session finish cleanly — watch for the voice-line plate and the reward object.
5. Settings → Stats, range = Today, for the receipt.
6. Click a creature to jump to its terminal.

Steps 3 and 4 are the ones carrying unverified visual risk.
