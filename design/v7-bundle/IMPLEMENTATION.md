# v7 collage panel — implementation notes

The Claude Design handoff in this directory is implemented in
`Sources/OpenIslandApp/Views/V7/`, behind the **"Use the v7 collage panel
(preview)"** toggle in Settings → General (`appearance.island.v7.collagePanel`,
off by default).

## Structure

The board explores five turns. The shipped structure is **5a** — the inbox
folds back into Sessions, and the freed corner becomes Usage:

| Board | Swift |
| --- | --- |
| 5a Sessions, merged | `V7SessionsTab.swift` |
| 5c Usage | `V7UsageTab.swift` |
| 03 Pet | `V7PetTab.swift` |
| 04 Rules | `V7RulesTab.swift` |
| 05 Critical escalation | `V7Escalation.swift` |
| 06 / 07 Empty states | `V7SessionsEmptyState`, per-tab empty states |
| 08 The pill | `V7ClosedPill.swift` |
| 10 The companion | `V7Companion.swift` |
| 11 Weekly recap | `V7Recap.swift` |
| 12 Token sheet | `V7Tokens.swift` |
| 3a–3c, 4a–4b | Not code — the asset pipeline and generation spec; see below |
| 2a–2c, 01–02 | Superseded by 5a |

`V7PanelView` composes the tabs; `V7TabChrome` draws the four hand-lettered
corner labels and holds the fixed 46pt side inset.

## Two rules that govern everything

1. **The collage is content, not chrome.** Art — the companion, the room, the
   recap slip — is torn paper and crayon. Functional UI — session rows, rules,
   meters — is plain, light and unremarkable. Grain rides art fills only; it
   must never appear inside a list.
2. **The seat is the contrast device.** The companion never reads against the
   wall or the floor. Anything that must be read gets a saturated block with a
   contour in a *clashing* hue (`V7Seat`). A fill never ships without its
   contour — matched borders read as UI and break the reference.

## Known gaps

**The torn edge is a stand-in.** The reference's edge is ragged, fibrous and
semi-transparent — a material, not a filter. The board's own verdict (3c, 4a)
is that shipping quality needs painted, scanned and matted raster plates.
`V7TornEdge` displaces the outline with seed-locked noise as a developer
stand-in; it keeps the same layer contract (tan core → mass → marks), so
plates can be swapped in without touching layout. The generation spec for
those plates is board 4a in `project/Open Island.dc.html`.

**Three faces, two of them stand-ins.** `V7Tokens.Typeface` asks for
`Patrick Hand` and `Caveat` — the board's own stand-ins for a licensed
textured hand — and falls back to the rounded system face when they are
absent. Bundling the real display face is outstanding.

**New product state has no store.** The board designs several things the app
does not record: the concierge's handled counter, leash-per-repo persistence,
auto-approve patterns, quiet hours and batching, the ship ledger that drives
the room's floor objects, and the earned shelf. These are gathered in
`V7BoardState`, which **defaults to empty**, and every surface reading it
degrades to an honest empty state.

That is deliberate. A hard-coded "214 interruptions handled this week" would
undermine exactly the trust these screens exist to earn. The board's sample
figures appear only in `V7BoardState.preview`, which is for design review.

Wiring each of those to a real store is follow-up work, and each is
independently shippable.
