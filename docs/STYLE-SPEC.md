# Open Island — Visual Style Specification

**Status:** draft, pending sign-off on the open questions in §11.
**Audience:** the illustrator commissioned for the creature and scene art, plus anyone
implementing `CreatureView`.
**Role:** this document is the artist brief and the acceptance standard. Art is approved
against it, not against taste.

This is an original specification. Every value in it was measured against this app's own
surfaces, and every rule is derived from those measurements. It describes a style we are
defining, not one we are reproducing. Do not add reference imagery from other products to
this repository, and do not name other products or illustrators in prompts, asset metadata,
or marketing.

---

## 1. The two surfaces

Everything in this document follows from the fact that creatures appear at two sizes on two
different grounds, and the difference between them is extreme.

| | Pill (closed) | Panel (opened) |
|---|---|---|
| Creature budget | **28 × 32 pt** | **~56 × 64 px** |
| Ground | `#0d0d0f` — near black, L 0.4% | `#b4de6f` — light wash, L 63.1% |
| Pixel area at 2× | ~3,600 px | ~14,300 px |
| What it is | a menu-bar glyph | a small illustration |

Two consequences that are not negotiable:

**The pill is width-constrained.** 28pt wide against 32pt tall. Bodies are tall and slim
with tucked limbs. A wide pose collides with the lane edge.

**The pill cannot draw above itself.** Its top edge *is* the physical top edge of the
display — anything drawn above it is off-screen, not clipped. Every gesture that breaks the
silhouette must extend **downward or sideways**, never up.

---

## 2. Two-tier style system

One style *system*, two detail tiers. This is the cel-over-watercolour tradition's own
grammar, not a compromise.

**Tier A — the panel scene** (540pt, backgrounds, structures, reward objects, receipt,
seasonal art). Full painterly treatment. Granulation, dry-brush grain, soft wet edges, line
wobble. This is where the craft is visible and where it should be spent.

**Tier B — pill creatures** (≤64px). "Reduced painterly": flat 2–4 value washes, exaggerated
pose-differentiated silhouettes, **zero interior texture at 28pt**. Everything that makes a
painterly mark read *as* painterly lives below the resolution floor here — at ~254ppi a 56×64px
sprite subtends roughly 35×40 arcminutes, and features under ~2px are simply unresolvable.

**Pill and panel variants are separate authored drawings**, at their own optical sizes. Never
one master scaled down. This is standard icon-design practice and it is a hard requirement,
not a preference.

---

## 3. Palette

### 3.1 Scene palette

Measured contrast is against the closed pill fill `#0d0d0f`.

| Hex | Role | On pill |
|---|---|---|
| `#211e12` | line work | **1.16:1 — invisible** |
| `#b73b3a` | accent / interrupted | 3.43:1 — weak |
| `#856a47` | structure dark | 3.84:1 — weak |
| `#739f8a` | teal object | 6.53:1 |
| `#94ab5a` | hill olive | 7.62:1 |
| `#97b76a` | hill mid | 8.61:1 |
| `#c4ae8e` | wood light | 9.07:1 |
| `#7bc9a4` | sky | 9.94:1 |
| `#b4de6f` | foreground wash | 12.61:1 |

Note the midtones `#94ab5a`, `#97b76a` and `#c4ae8e` sit between L 36.2% and 44.0% — a
7.8-point span with the closest pair only 2.5 points apart, against the species ladder's
8.5-point minimum gap. They will merge at pill size. They are scene colours, not creature
colours.

### 3.2 Species values — the pill ladder

Six bodies serve ten agents; four agents share one body because they share a hook format.
They look alike because they are alike.

| Species | Hex | Luminance | On pill |
|---|---|---|---|
| Claude | `#f8d7b7` | 72.0% | 14.23:1 |
| Codex | `#b2cbe8` | 58.0% | 11.65:1 |
| Cursor | `#7dc3a2` | 46.0% | 9.43:1 |
| Gemini | `#aa99bd` | 35.0% | 7.40:1 |
| Kimi | `#ba7492` | 25.0% | 5.55:1 |
| OpenCode | `#797153` | 16.5% | 3.98:1 |

This is a deliberate **luminance ladder**, not a hue wheel: a 55.5-point spread with a
minimum adjacent gap of 8.5 points. An earlier palette placed all six inside a 14.4-point
band with gaps as small as 1.5 points — in greyscale it was one colour, and it failed both
the greyscale test and colour-blind safety. Any revision must preserve the spread.

**Rule: species values may be re-hued but not re-valued.** Hue is free. Luminance rank and
spacing are load-bearing.

### 3.3 The two-ground rule

This is the most consequential finding in this document.

To clear 3:1 against the **lightest** species, a ground must sit at L ≤ 20.7%. To clear 3:1
against the **darkest**, it must sit at L ≤ 2.2% or L ≥ 59.5%. The only single ground that
serves the whole ladder is **L ≤ 2.2%** — which is essentially the pill itself.

The panel ground is L 63.1%. Measured, the species colours score **1.08:1 to 3.17:1** on it;
the three brightest fall under 1.34:1. Dropped straight onto the panel they are invisible,
and desaturating confirms it — hue alone is holding them together.

Therefore identity is carried differently on each surface:

- **On the pill, identity is value.** The ladder, on near-black. Silhouette here carries
  *state*, not species — there are not enough pixels for it to do both.
- **On the panel, identity is silhouette and hue.** Value is free to serve the composition
  and must simply clear 3:1 against whatever the creature actually stands on.

This is principled rather than a workaround: the surface with pixels enough for silhouette
does not need value to carry identity, and the surface without them does.

### 3.4 Panel species values

The ladder is **restated, not reused** — same order, same hues, compressed into a dark band
the panel can actually show. Values are derived by scaling each pill colour in *linear* light,
so chromaticity is untouched and only brightness moves; a species stays recognisable when the
same session is seen on both surfaces.

| Species | Pill value | On panel ground | Panel value | On panel ground |
|---|---|---|---|---|
| Claude | `#f8d7b7` | 1.13:1 ✗ | **`#766656`** | 3.58:1 |
| Codex | `#b2cbe8` | 1.08:1 ✗ | **`#535f6e`** | 4.22:1 |
| Cursor | `#7dc3a2` | 1.34:1 ✗ | **`#385b4b`** | 4.92:1 |
| Gemini | `#aa99bd` | 1.70:1 ✗ | **`#4e4658`** | 5.82:1 |
| Kimi | `#ba7492` | 2.27:1 ✗ | **`#563342`** | 6.99:1 |
| OpenCode | `#797153` | 3.17:1 | **`#343022`** | 8.56:1 |

Generated by `CreaturePalette.panelColor(for:)` rather than hand-picked, so the 3:1 property
holds by construction and cannot drift. The band is bounded at L 3–14%, held below the 17.7%
that 3:1 against `#b4de6f` allows so 8-bit rounding cannot push the lightest species under
the bar. Verified desaturated as well as in colour.

**Never apply the pill ladder to panel art, or the reverse.** Each surface has its own column
above.

---

## 4. Line

- **Wobbly and variable-width.** Hand-drawn character, not a uniform stroke.
- **Minimum 1pt (2px at 2×) at pill scale.** Anything finer disappears.
- **Interior only on the pill.** `#211e12` measures 1.16:1 against the pill fill — it cannot
  carry a silhouette edge there and must never be asked to. On the panel ground the same
  colour measures 10.82:1 and carries beautifully, so panel art may outline freely.
- **Pill creatures are light masses read by silhouette.** Dark line lives inside the shape.

This inversion is the single most common way this style fails. A drawing built on
dark-subject-against-light-ground loses roughly 3× its contrast when moved onto the pill.

---

## 5. Texture

- Tier A only. Dry-brush and granulation on **midground masses**, not on foreground subjects
  and not on creatures.
- **Zero interior texture at 28pt.** It is not a stylistic choice at that size; it is
  invisible and costs contrast.
- Flat 2–4 value washes per creature at pill size. Four is a ceiling, not a target.

---

## 6. Silhouette grammar for the pill

At 28 × 32pt, detail is unaffordable, so **state is signalled by breaking the capsule's
outline**. This is the pill's entire visual vocabulary.

Requirements for every pose:

1. **The break must be visible in the outline, not only in the interior.** A gesture that
   stays inside the body's bounding envelope does not read.
2. **The break extends sideways, never up.** The pill cannot draw above itself (§1), and the
   lane leaves only 1.3–4.2pt above the body in any case. The sides carry 4.5–6.7pt each.
   **Sideways is the only axis with room.**
3. **A raised-limb gesture needs a ≥2–3px gap** (1–1.5pt) between the limb and the body at
   pill scale. Below that the gap closes under antialiasing and the limb merges into the mass.
4. **The three attention states must be mutually distinguishable at true size**, judged on
   the worst procedural roll, not the best.
5. **State is signalled by how many limbs are out, not how far.** See below — this is the
   rule that the gate was failed and then re-passed on.

### The asymmetry rule

The three pill-legible states separate by **count and symmetry**, not by degree:

| State | Arms | Silhouette character |
|---|---|---|
| `working` | none out | compact, symmetric |
| `waiting` | **one** out | **lopsided** — this is the notification |
| `holding` | **both** out | wide, symmetric |

This is not a stylistic preference, it is what the measurements forced. An earlier version
graded a single arm-lift scalar 0 → 0.78 → 1.0 and the gate found *waiting* and *holding*
indistinguishable at true size: 22% of a range that itself has only about 5pt to travel in,
with **0.00pt** of vertical break available. Asymmetry survives at 28 × 32pt where a
difference of degree does not, and it maps cleanly onto meaning — one limb raised reads as
*asking*, two as *presenting*.

Measured after the fix, on the reference body: `working` breaks the outline by +2.20pt on
both sides, `waiting` by +5.18pt and +2.20pt, `holding` by +5.18pt on both. On the **worst
roll** — the widest body, which has the least room to put an arm into — *waiting* still holds
2.43pt of asymmetry and *holding*'s weaker arm still breaks by 4.74pt.

Whoever draws these inherits the rule, not the geometry: the placeholder proves the signal
exists at this size, and the drawing has to preserve it.

### Where individuality comes from

Per-session variation must not be bought out of the lane's width — that is the budget the
gesture above spends, and the two compete directly. Variation is carried by **silhouette
shape** instead: bodies range from boxy to fully capsule at constant width. Shape costs no
horizontal room, so it is free in the only currency this lane is short of.

For art, the same rule applies: if species need to differ, differ them by *outline*, not by
footprint. A wider creature is a less legible one.

---

## 7. The four poses

| Pose | Meaning | Pill legibility |
|---|---|---|
| `working` | agent is running; ambient, should be ignorable | required |
| `waiting` | blocked on the human — **this is the notification** | required |
| `holding` | clean completion, reward held, waiting to be collected | required |
| `fallen` | interrupted | **exempt** |

`fallen` is deliberately exempt: an interrupted session is not competing for attention, so it
may read as calm. It is still drawn, and it still must not read as *broken art*.

Note that the pill therefore has **three** legible states, not four.

---

## 8. Acceptance — the kill gate

Art is approved by measurement and by squint test at true size, in that order. Taste is the
last gate, not the first.

Run `zsh scripts/creature-gate.sh <outdir>`. It renders every species × pose at true 28 × 32pt
composited on the real pill fill, plus a colour-removed pass, panel-size renders, and 20
procedural individuals, and prints measured contrast. It links the shipped palette directly,
so it cannot drift from what the app draws.

**Pass conditions:**

1. At true pill size on the real pill colour, `working` / `waiting` / `holding` are mutually
   distinguishable at a glance — judged on the worst roll.
2. Every species and pose clears **≥3:1** against `#0d0d0f`, as a measured number.
3. At panel size, all four poses are distinguishable.
4. With colour removed, the six species remain tellable apart.
5. The six species are distinguishable **from shape alone**.
6. No procedural individual reads as a dud or as a different species.

Conditions 1, 2 and 4 already pass on placeholder geometry — they gate the *mechanism*.
Conditions 3, 5 and 6 gate the *art* and are unanswerable until real sprites exist. Running
the gate twice is the intent.

**Silhouette blocks are approved before any painting begins.** A 32 × 32 block, squint-tested
on black at 1×, per species and per pose. This is the cheapest possible place to discover that
a pose does not read.

---

## 9. Deliverables

Per species (six species):

- **Pill variant**, 4 poses, authored at 28 × 32pt, delivered at 1× / 2× / 3×.
- **Panel variant**, 4 poses, authored at ~56 × 64px, delivered at 1× / 2× / 3×.
- Layered source files.

Plus, Tier A: scene backgrounds, structures, reward objects across tiers, the receipt, and
seasonal variants. Scope these separately — they are a different problem from the creatures
and should not gate them.

Silhouette blocks precede all of the above and are approved separately.

---

## 10. Provenance and licensing

- Assets are dual-licensed **CC-BY 4.0** alongside GPL-3.0 code. GNU explicitly blesses
  separately-licensed art.
- The contract needs: assignment or irrevocable sublicensable license, modification and
  derivative rights (required for seasonal recolours), moral-rights waiver where permitted,
  artist attribution and portfolio rights, named revision rounds, and layered delivery.
- Any placeholder art shipped during development is marked `PLACEHOLDER` in `ASSETS.md` and
  removed before release. The current placeholders are procedural shapes in
  `Sources/OpenIslandCore/CreatureForm.swift`, not image assets.
- Purely machine-generated finals are not copyrightable and would leave this repository with
  art it cannot defend. Final art is human-authored or human-substantially-repainted.

---

## 11. Open questions requiring sign-off

1. ~~**Panel species values.**~~ **Resolved** — see §3.4. Values are derived from the pill
   ladder by linear-light scaling into an L 3–14% band, preserving hue and rank. Worst case
   3.58:1 against the panel ground, verified in colour and desaturated.

2. ~~**The `waiting` / `holding` gesture pair.**~~ **Resolved** — see §6. Separated by arm
   count rather than arm lift, and re-gated on the worst roll.

3. ~~**Procedural variation range.**~~ **Resolved** — but not by widening the proportions.
   Width is the lane's binding constraint and the raised-arm gesture needs the side room, so
   widening it would have bought individuality by spending legibility. Variation moved to a
   `roundness` channel instead: silhouette shape from boxy to fully capsule, which costs no
   lane width. Re-gated — pose separations are unchanged at 2.43pt and 4.74pt, and no roll
   reads as a dud or as a different species.

4. **Target aesthetic.** Whether the pill creature should read as a small painterly figure or
   as a bold flat glyph with strong silhouette character. At 28 × 32pt the second is more
   achievable and more defensible; the first is closer to the panel's world. This is a
   deliberate choice and should not be made by default.

5. **Which arm is raised.** `waiting` always lifts the leading arm. Alternating it by session
   seed would add individuality at no legibility cost, but it also makes two sessions in the
   same state look different, which may read as meaning something. Currently fixed.
