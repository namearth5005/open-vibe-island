<!-- Research note. Produced 2026-08-02 by an 11-agent evaluation (7 research, 3 adversarial,
1 synthesis) on Fable 5, plus local verification. Legal sections are a researched landscape summary,
not legal advice — verify the cited cases and terms before acting on them. -->

# Open Island Art Production — Decision Document

*(Synthesized 2026-08-02 from five research tracks + three adversarial verification passes. Legal points are researched summary, not legal advice.)*

## 1. The Answer in Three Sentences

Do not screenshot Cat on Chair and feed it to Lovart — the plan was independently refuted on technical, legal, and reputational grounds, and even a perfect style clone contains no solution to your actual hardest problem (28×32pt legibility), because Cat on Chair never renders its cat below iOS widget scale. Instead, commission a human illustrator (realistic cost $4,000–8,000, 6–12 weeks, with a ~$1k style-guide kill-gate milestone first) to execute a **two-tier style system**: full watercolour for the 540pt panel scene, and flat, silhouette-first, 2–4-value creatures for the pill — sharing one palette and line language. This is literally the route Cat on Chair took (one human with a distinctive style), it is the only route that produces copyrightable, GPL-compatible assets, and the "illustrated by a human" credit is itself the marketing asset the reference app went viral on.

## 2. Why Lovart, or Why Not

**Not.** Lovart is real and its demo capabilities all verified (ChatCanvas multi-asset packs Jul 2025, Brand Kit Apr 2026, Touch Edit Dec 2025, PSD export Apr 2026), but it is an orchestration wrapper over public models (Nano Banana 2/Pro, GPT Image, Flux, Seedream) — it adds zero unique style capability. It fails this project's four hard requirements specifically:

- **Consistency**: Brand Kit is soft context injection, not style enforcement. Trustpilot ~1.8/5 with dominant complaints about inconsistent multi-asset output and near-identical regenerations burning credits — failure modes that land exactly on a style-locked 6-species × 4-pose matrix. Lovart's own "93% consistency across 30 assets" claim (vendor blog, unbenchmarked) means ~2 off-style assets per batch even at face value.
- **Alpha**: transparency is generate-then-matte, not native. Matting wobbly painterly dark outlines is the documented halo/fringe failure mode; every sprite composites over your painted island.
- **Small size**: nothing in Lovart's docs, features, or reviews addresses sprite-scale output. Its envelope is posters and brand collateral.
- **Cost predictability**: $19–32/mo, non-rollover credits; reviewers report iterate-until-it-matches workflows (yours) burning 500+ credits per project.

The one genuinely useful capability — Touch Edit's Cmd-click localized regeneration — does not outweigh the rest. If you want AI intermediates at all, driving **Nano Banana Pro** (best multi-pose character consistency, flat RGB only) or **Recraft V4 paid** (only major generator with reliable *native* transparent PNG + 20-asset style lock; pricing figures conflict between sources — verify) directly is strictly better than paying Lovart's markup and second ToS layer.

## 3. The Screenshot Plan

**It's a bad idea and you should drop it entirely: it starts with verbatim reproduction of a named living illustrator's copyrighted work, facially breaches Lovart's own ToS (§5.4 rights warranty + AUP + §11 indemnity, verified verbatim 2026-08-02), and would sit forever as public evidence in your GPL repo — while destroying the exact "not vibe coded" quality that makes the style valuable.** Image-conditioned generation is the legally weakest variant of style copying (USCO Jan 2025 "expressive inputs" analysis; Andersen v. Stability, trial Sept 2026), and your audience — developers — is the demographic most likely to notice and care.

**The nearest good idea, immediately actionable:** you already extracted what you actually need. The measured palette (#7bc9a4 sky, #97b76a/#94ab5a hills, #b4de6f foreground, #c4ae8e/#856a47 objects, #211e12 line), the line character rules (wobbly, variable-width), and the texture placement rules (dry-brush on midground only) are **unprotectable ideas** — style-as-such is not copyrightable. Write them into an original `STYLE-SPEC.md` and hand *that* to a human illustrator (or, for throwaway placeholders only, a generator). Never upload her images anywhere, never name "Cat on Chair" or the artist in prompts, asset metadata, or marketing — the latter tracks the surviving Lanham Act theory in Andersen.

## 4. The 28pt Problem

**The painterly direction as stated — watercolour creatures at 28×32pt — is optically impossible, and this was verified three independent ways**, including an empirical downscale test of Cat on Chair's actual screenshots this session:

- **Optics**: 56×64px at ~254ppi is 5.6×6.4mm ≈ 35×40 arcminutes at 55cm. Human acuity is ~1 arcmin; features under ~2px are unresolvable. Everything that makes watercolour read *as* watercolour (granulation, dry-brush grain, soft wet edges, line wobble) lives below that floor.
- **Contrast**: the signature #211e12 outline against the black pill is **1.26:1 — invisible**. Only light washes carry (#b4de6f is 13.6:1). Pill creatures must be light masses read by silhouette, with dark line used only *inside* the shape.
- **Empirical**: downscaling the actual painted cat to pill budget kept it recognizable as a cat — via flat white-on-dark silhouette only — while every stylistic marker (fur strokes, crayon grain, soft edges) died. The result is indistinguishable from flat vector sprite art.
- **Precedent**: every shipped menu-bar/notch pet (RunCat, Mac Pet, Dockling, CozyPet) is pixel or bold-flat; zero watercolour counterexamples found. And Cat on Chair itself never renders below widget scale (~155pt, ~100× the pill's pixel area) — **there is no small-size solution in the source material to copy.**

**What replaces it — not a compromise, the tradition's own grammar** (cel-over-watercolour: Ghibli, Hollow Knight, Child of Light): one style *system*, two detail tiers.

- **Tier A** (540pt panel scene, backgrounds, receipt, seasonal art): full watercolour treatment. This is where the Cat on Chair magic pays off.
- **Tier B** (creatures ≤64px, structures, reward objects): "reduced painterly" — flat 2–4 value washes from the measured palette, exaggerated pose-differentiated silhouettes, ≥2px (1pt) wobbly line, zero interior texture at 28pt, light-mass-on-dark design. Note the palette's midtones (#97b76a, #94ab5a, #c4ae8e) cluster around the same luminance and will merge at pill size — values must be deliberately spread per creature.
- **Kill gate** (mirroring your existing 20pt geode gate): every creature is approved as a 32×32 silhouette block, squint-tested on black at 1×, before any painting happens. "Knocked-over" reads via rotation; "hand-raised" needs a ≥2–3px gap between arm and head. These are silhouette moves, and no generator performs this design task.

Pill variants and panel variants are **separate authored drawings** (optical sizes, per icon-design practice), not one master scaled down.

## 5. Ranked Options

| # | Route | Cost | Time | Quality ceiling | Licensing/reputation risk | Who it suits |
|---|-------|------|------|-----------------|---------------------------|--------------|
| 1 | **Commission human illustrator, full set** (CC-BY 4.0 assets beside GPL code; LPC/Krita precedent) | $4–8k realistic ($1.5–3.5k budget tier, $8–16k senior) | 6–12 wks part-time | Highest — coherent, unique, copyrightable, and a marketable "illustrated by ___" credit | **Near zero** with written assignment/sublicensable license + modification rights | This project. The reference app's actual route. |
| 2 | **Hybrid B: human bases + mechanical variants** (recolors, tier glows — mostly programmatic, not even AI) | $3.5–6k | 5–10 wks | Same as #1 for everything visible | Low, IF the contract has an explicit AI/derivative clause and the repo discloses it (Fedora-style) | Same as #1 if budget is tight; saves only ~$1.5–3.5k because variants are the cheap half anyway |
| 3 | **Hybrid A: commission style guide + species masters, AI-extend poses** (e.g. Qwen-Image-Edit pose derivation, or Scenario LoRA $45/mo trained on *owned* commissioned refs) | $2–4k + ~$50 | 4–8 wks | Medium-high for panel art; pill sprites still need human optical redraw regardless | Medium: contractually negotiable, but 2025-26 standard illustration contracts *prohibit* style-replicating AI by default; backlash precedent (Clair Obscur awards DQ) | Budget-forced fallback only, with full disclosure in ASSETS.md |
| 4 | **Pure AI from an original style spec** (no screenshots ever; Nano Banana Pro for poses + Recraft for objects, or klein-4B/Qwen LoRA locally) | $50–150 | 1–2 wks | Low-medium: gloss/saturation drift fights the flat low-sat target; uncopyrightable output = unenforceable de-facto public domain in the repo | Legal: OK if inputs are clean. Reputational: high for final art in *this* audience | **Placeholders to unblock development now** — clearly labeled, replaced before release |
| 5 | **CC0/CC-BY adaptation** (Glitch 10k-asset corpus, itch.io watercolour texture packs) | $0 | days | Textures/background underpainting only — no expressive creatures exist in any pack | Zero (Glitch is also the only risk-free LoRA training corpus, if ever needed) | Scope-shaving supplement to #1, not a route |
| 6 | ~~Screenshot Cat on Chair → Lovart~~ | $19–32 | days | Low at pill scale (no small-size info in source; matte fringing; consistency drift) | **Disqualifying**: ToS breach + indemnity, derivative-work exposure, permanent public provenance, targets a named living artist | No one. Rejected on three independent axes. |

Eliminate outright: Midjourney (no alpha, perpetual license-back, active Disney/Universal litigation), FLUX.2-dev weights (non-commercial), all free tiers (Recraft/Leonardo free-tier output is owned by the platform), 3D tools, pixel-art-only sprite tools (PixelLab, SpriteCook — wrong style).

## 6. The Recommended Pipeline

**This week:**
1. **Write `docs/STYLE-SPEC.md`** — the measured palette hexes, value-spread rules per creature, line character ("wobbly, variable-width, ≥1pt at pill scale, interior-only on pill"), texture placement (midground masses only, Tier A only), the two-tier architecture from §4, and the 28pt-on-black kill gate. This document is your original, unprotectable-ideas style source; it also becomes the artist brief. No Cat on Chair imagery in it or the repo, ever.
2. **Cut placeholder sprites yourself** (option 4: flat SwiftUI shapes or Recraft from the spec) so app development on poses/states isn't blocked. Mark them `PLACEHOLDER` in an `ASSETS.md`.
3. **Post the commission** on Cara's jobs board first (human-verified no-AI artists — the exact credential you want to advertise), plus ArtStation and r/gameDevClassifieds. Search terms: watercolour/gouache, children's-book illustrator, cozy game, emote/sticker artists (emote artists are the closest analog to 28pt expressive characters — comparables ~$230/set of 10). Brief states up front: public GPL-3.0 repo, assets dual-licensed CC-BY 4.0 (GNU explicitly blesses separately-licensed art; Liberated Pixel Cup is the paid-open-commission precedent), layered files required, attribution credit given.

**Weeks 1–3 — Milestone 1 (~$500–1,500, capped downside):**
4. One species × 4 poses (both pill and panel variants) + one background + palette sheet. **Approve only at actual render size: 28×32pt on a black pill and 64px in the panel.** Silhouette blocks approved before painting.
5. **Contract** before bulk work: assignment (work-for-hire language *plus* fallback assignment clause — commissioned art rarely fits the WFH statutory categories) or irrevocable sublicensable license; modification/derivative rights (needed for seasonal recolors and CC/GPL); moral-rights waiver to extent permitted; artist attribution + portfolio rights; named revision rounds; layered PSD/Procreate delivery at 1×/2×/3×; an explicit AI clause **only if** you want option-2 variant automation later — the 2025-26 industry default prohibits it.

**Weeks 3–12 — bulk production:**
6. Remaining 5 species × 4 poses (pill + panel variants as separate optical drawings), 5 structures, 12 objects × 3 tiers (tier variants priced as variants, 30–50% of base), receipt, 2–4 seasonal backgrounds. Optionally shave background hours with CC0 texture packs.
7. **Ship**: `LICENSE-ASSETS` (CC-BY 4.0), `ASSETS.md` with full provenance ("all final art by <name>; placeholders during development were AI-generated from our original style spec and are removed"), credit in README and the app's about panel. This matches Fedora-style disclosure norms and turns provenance into a feature.

## 7. What Would Change My Mind

**The cheapest falsifying test (~$32, one weekend):** one Lovart Basic or Scenario/Recraft month, using *only* the original `STYLE-SPEC.md` as input (no screenshots — that variable is settled regardless). Generate one species × 4 poses, matte to alpha, downscale to 56×64px, composite on a black pill, and run a blind review: style-coherent across the 4 poses, squint-test legible at 28×32pt, clean edges, **zero hand touch-up**. No such demonstration exists anywhere as of Aug 2026 — if you produce one, the economics flip toward option 3/4 and the commission shrinks to a style-guide-plus-QC role. Secondary triggers to revisit: commissioned quotes all landing above ~$16k, or no acceptable artist willing to sign open licensing (some decline over scrapeability — real risk, plan for it).

Two things no test result changes, because they're physics and law rather than tooling: the two-tier architecture with a 28pt-on-black kill gate stands under every route, and purely AI-generated finals remain uncopyrightable (Thaler, cert denied Mar 2026) — so only human-authored or human-substantially-repainted assets ever give this repo art it can actually defend.

---

## Appendix — locally verified numbers

Computed here rather than taken from the research, using WCAG relative luminance against the closed
pill fill `#0c0d0f` (`V6Palette.ink`):

| Colour | Role | Contrast on pill |
|---|---|---|
| `#211e12` | line work | **1.17:1 — invisible** |
| `#b73b3a` | accent / interrupted | 3.43:1 — weak |
| `#856a47` | structure dark | 3.84:1 — weak |
| `#739f8a` | teal object | 6.53:1 |
| `#94ab5a` | hill olive | 7.62:1 |
| `#97b76a` | hill mid | 8.61:1 |
| `#c4ae8e` | wood light | 9.07:1 |
| `#7bc9a4` | sky | 9.94:1 |
| `#b4de6f` | foreground | 12.61:1 |

Confirms the synthesis: the signature dark outline cannot carry the silhouette against the pill. On the
pill, creatures must be **light masses read by silhouette**, with dark line used only *inside* the shape.

### The species palette fails its own greyscale test — worse than the research found

Luminance of the six proposed species hues, sorted:

| Species | Hue | Luminance | Δ to next |
|---|---|---|---|
| Cursor | `#82c2a4` | 46.0 | — |
| OpenCode | `#c9b06a` | 44.5 | 1.5 |
| Claude | `#e0a05c` | 41.8 | 2.7 |
| Codex | `#7fa8d8` | 37.5 | 4.3 |
| Kimi | `#d98aa8` | 35.8 | 1.7 |
| Gemini | `#9b8fd8` | 31.6 | 4.2 |

All six sit inside a **14.4-point luminance band**, and no adjacent pair separates by more than 4.3.
In greyscale they are one colour. The species are therefore distinguishable by **hue alone**, which
fails the greyscale test proposed in the design and is unsafe for colour-blind users.

**Consequence:** species identity cannot rest on hue. It must rest on **silhouette**, with hue as
reinforcement only — which raises the stakes on the silhouette kill gate and argues for deliberately
spreading the six species across the luminance range as well.
