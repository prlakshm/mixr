---
name: dj-remix-planning
description: >-
  Plan Auto Remix club rewrites and mashups using Mixr’s locked two-deck DJ
  mix grammar (Xirex pivot wallpaper, hook-replace, one kick). Use when
  designing remix recipes, selecting cut/transition/SFX/pulse opportunities,
  auditing remix decisions, or implementing Auto Remix planning.
---

> **Join / mix-window grammar (locked):** this skill. It wins over root
> `AGENTS.md` on two-deck joins, pivot wallpaper, hook-replace, Drop 1 timing,
> and mix-window SFX.
>
> **Still in `AGENTS.md`:** tempo pockets, one-kick pulse, gain/DSP, analysis
> confidence, testing, and the completion standard. Keep those locks.

# DJ Remix Planning

## Club rewrite, not preservation (product lock)

Auto is a **festival club rewrite** (Diplo / Guetta / Snake energy) — not a
polite preservation edit and not a shuffled highlight reel. Hype lives **on
the drop**. Verses stay one record. Pivot join is short and loud (default
**8× / 2 bars**, clip volume up, HPF/blur — not a volume duck). No quiet hole
just to switch songs (overlap or hard cut at full clip volume). Festival SFX
on the mix window / drop (riser + snare + tape-stop + impact). Drop 1 after
**one complete A hook**.

Preservation constrains **identity** (familiar hook on drop 1; important
lines uncut). It is not a ban on arrangement. SFX alone do not count as
transformation. Maximalist flavors put festival SFX density **on the mix
window / drop** (riser + snare roll + tape-stop take-out + impact). Verses
stay one record.

## Important lines uncut (product lock)

Never cut the best / most identifiable lines. Opening titles and hook lines
**finish**. Do not chop the first “Oops”. Do not chop the first “baby”.

- Pivot grain is the **LAST identifiable word** of a completed line, after it
  has played once — never the first syllable of the title and never a silent
  tail rest.
- Incoming hook starts on the **downbeat of a real line**, not mid-word.
  Bed title-hook copies start on the **previous downbeat before**
  `titleHookStart` so the title token is fully inside the clip. Drop 1 guest
  stays one beat before the lyric. Hard cut, no fade-in.
- If phrase confidence cannot support a last-word grain, **skip the loop**
  rather than slicing the title. Keep playing through the window so the join
  does not go quiet.

A first Deck A hook that is a 2–4 bar teaser of the opening title is a fail.

## Locked gold-standard join (DJ Xirex)

Reference mix: **Oops I Did It Again → …Baby One More Time** (Instagram reel).
Future Auto Remix work copies this *grammar*, not 1/8 stutter spam or a quiet fade-in.

1. **Deck A chorus plays complete.** Do not chop the opening title. Do not
   slice the first “Oops” or the first “baby”. The outgoing line finishes
   (e.g. “Oops I did it again / I played with your heart / Got lost in the
   game / Oh baby, baby”).
2. **Pivot grain = last word of that completed line**, one quarter-note
   (1 beat) on the downbeat. Loop it **8× = 2 bars** (4–8 repeats / 1–2 bars
   is the general range). This is the **wallpaper chop**: one grain, steady,
   predictable. **Not** 1/8 or 1/16 stutters, tape stops, echo throws, or chops
   scattered on the drop or in verses. **Not** 16× / 4-bar wallpaper — that
   is too long.
3. **Over those 1–2 bars:** high-pass / Sound Color (blur) the loop so kick
   and lows leave. Thin, tinny vocal stutter. Builds tension. Kick out on this
   window (`buildOut`). **Volume stays loud** (at least as loud as the bed
   verse). Blur thins; it does not duck. A quiet wallpaper hole is a failed join.
4. **Hard cut** (no echo, no crossfade, **no fade-in**, no volume ramp from
   silence, no gentle EQ bloom) into Deck B’s hook that **starts on the same
   word** (“baby, baby, one more time” / “hit me baby one more time”) at
   **full clip volume** (at least as loud as the bed verse), full-frequency
   kick. Then the rest of B’s chorus rides.
   A renderer anti-click microfade is fine; an audible quiet join is a fail.
5. **Phrase math:** 2 bars of loop, incoming vocal on the downbeat of bar 3
   of the mix window. First drop lands **~bar 16–24** after intro + one
   complete Deck A hook + pivot — **earlier than it feels safe**. Do not wait
   until bar 28 if the completed hook was available at bar 16–24. A shorter
   pivot can land Drop 1 earlier (~bar 18).
6. **Hook-replace:** guest vocal IN, bed vocal OUT (HPF/blur the bed under
   the drop). One melody, **one kick**. Call-and-response is optional ≤8 bars,
   not the default.
7. **Festival SFX on the mix window / drop** (maximalist flavors: Diplo /
   Guetta / Snake): take-out (riser + snare roll + tape stop) **ends on the
   last pivot beat**, not on the guest’s first syllable and not on title-hook
   onsets. After the attack, extra impacts / air sweep / clap fill **ride the
   drop bars** on extra SFX rows. Playback and export must mix every SFX row.
   Sparse flavors (Calvin) stay impact-only, still off the downbeat. Verses
   stay one record — no riser wallpaper in grooves.
8. **No 1-beat void on this join.** Pivot Drop 1 is loop + hard cut at full
   clip volume. A pre-drop void next to the wallpaper is the old quiet hole.
   Do not emit `allowedPredropVoid` on the same plan as `pivotWallpaperLoop`
   — crate bounce treats that pair as a Drop 1 hole. Drop 2 is a hard cut /
   impact at full clip volume — not a quiet pause and not an equal-power
   fade-in on the same-song hook return.

If the join is quiet, it failed.

### Song-switch energy (product lock)

No choppy transitions that go quiet just to switch songs. **Dead air**,
**fade-to-silence**, and **both-sides ducking** as a handoff are fails.
Switch songs by **overlapping** (equal-power with real temporal overlap) or
by a **hard cut at full clip volume**. The mix must keep energy through the
join. Pivot still thins with HPF/blur, not by turning volume down.

### Clip-wise volume (product lock)

Auto must set **per-clip volume** on every Auto-placed song clip (pivot grains,
bed under hook, guest hook-replace, verse). Mixr already has clip volume —
write it in the planner/applier. Do not only ride track faders or blur.

Typical:

- completed Deck A hook / verses: ~full
- pivot grains: **at least as loud as the bed verse** (not ducked); HPF/blur does the thin, volume stays up
- incoming Drop 1 vocal / bed kick: **at least as loud as the bed verse**
  (hard cut; no fade-in). If the clip is a quieter stem, apply RMS makeup
  (clip volume may exceed 1.0). Volume=1.0 alone is not enough.
- bed under hook: audible (don’t mute) with HPF/blur carving the bed vocal
- never fade both sides toward silence at a pivot join

### Generalize (any pair / solo)

- **Pivot grain** = last 1-beat of a **completed** chorus/hook line of Deck A,
  preferably a short word that also starts Deck B’s hook (title/hook token
  overlap, e.g. “baby”). Without lyrics, use title/hook tokens
  (`AutoPivotWord`); grain is the last identifiable vocal beat of that phrase.
- Loop that grain 4–8× (1–2 bars; default **8× = 2 bars**) on extra vocal/SFX
  rows, grid-snapped, with HPF sweep / duck the bed kick on that window.
  Pivot **clip volume stays loud** — HPF/blur does the thin.
- Incoming hook-replace on the next downbeat, same-word attack, **full clip
  volume** (no fade-in). Bed title-hook copies start on the previous
  downbeat before the lyric word so ASR hears the title token.
- Pivot grain is the last **identifiable** pivot token / vocal beat of the
  completed line — not a silent tail rest.
- Wallpaper chops are **this mix-window loop**, not verse decoration and not
  1/8 spam on the drop.
- **Pulse Drop 1** = that hard cut after the loop — never a fake drop on the
  bed’s completed chorus (e.g. bar 16 of Oops playing through is still the
  record, not Drop 1).

## Product intent

Auto Remix rewrites a song as a **streaming-length club mix** using a
**two-deck DJ mind**: Deck A is NOW PLAYING, Deck B is COMING NEXT.
Full-volume stacking is illegal except inside a **mix window**. See
**Club rewrite, not preservation** and **Important lines uncut** above —
those locks win over any urge to leave the record untouched.

Accidental silence is forbidden.

**No 1-beat pre-drop void on a pivoted plan.** Pivot Drop 1 is a hard cut,
not a hole. Do not emit `allowedPredropVoid` next to `pivotWallpaperLoop`.
Drop 2 is also a hard cut / impact — not a quiet pause to “make the drop,”
and not an equal-power fade-in on the same-song hook return. Do not emit
`allowedPredropVoid` and do not rewrite Drop 2 masking to equal-power.

## Two-deck model

- **Deck A** = current phrase (bed or solo source). **Deck B** = next hook.
- **Mix window** = completed A hook tail + 1–2 bar pivot loop + first bars of
  the drop. Extra layers (pivot grains, HPF sweep, festival SFX stack) are
  legal ONLY there. Verses/grooves stay one deck.
- **Verses / grooves** = the source, maybe light HPF. No wallpaper chops, no
  riser spam, no guest vocal, no echo throws.
- **Semantic joins**: wait until a phrase finishes. Important lines uncut.
  Incoming hook starts on a real downbeat of a real line, not mid-word.
- **Drop 2** = a flip (different song’s hook or bed chorus back), not the
  same stack louder. Hard cut / impact at full clip volume — no 1-beat void
  and no equal-power fade-in on a pivoted plan.
- Diplo / festival energy lives **on the drop**, not on verses.

## On-device Mixr (no Demucs runtime)

- Swift / AVFoundation only on device. **No Python, no Demucs, no PyTorch
  in the app.** Do not add a Demucs runtime.
- Mashability uses Swift role proxies from vocal/bass/drum **curves**
  (AutoMashup 2025 idea; no stems required).
- **Optional offline Demucs sidecars** (vocals / drums / bass / other) may
  already exist next to a song (`…/Songs/<file>` →
  `…/Stems/htdemucs_ft/<basename>/{vocals,drums,bass,other}.wav`). If present:
  - pivot grains come from the **vocal** stem (HPF as already planned);
  - hook-replace uses Deck B **vocal** over bed **drums+bass+other**;
  - dual-vocal islands use the guest vocal stem over the bed instrumental
    (duck/HPF the bed vocal — do not stack two full mixes);
  - kick ownership / pulse gating may read the **drums** stem (one kick).
  If absent, keep today’s proxies: last 1-beat of the completed phrase +
  HPF/blur for hook-replace. Never block planning on missing stems.

## Planning hierarchy

1. Analyze musical structure (sections, beats, phrases, drum/bass density).
2. Decide tempo pocket (keep strong pockets; stretch/double-time only within gates).
3. Decide pulse policy (one-kick rule).
4. Build the club phrase-grid recipe (or mashup hook/bed slots) using the
   locked join above.
5. Score and place sections; record structured cut / void / pulse / pivot decisions.
6. Validate musical and audio integrity.
7. Render and report every decision.

## Club shape (one song)

Phrase-grid only — drops land on downbeats, never mid-bar.

**Locked Drop 1 shape (Xirex):**

1. Intro 8 — filtered identity / kick tease (opening title uncut; source near t=0)
2. First complete hook/chorus 8 — still the record (no early chops)
3. Pivot wallpaper 2 — 1-beat last-word loop ×4–8 (default 8× = 2 bars), HPF, kick out; **loud clip volume**
4. Drop 1 = 16 — hook-replace / familiar hook, **hard cut**, full pulse, one lead idea (~bar 16–24)
5. Breakdown 8–16 — pulse out, breathe
6. Build 2 — denser than the pivot window (may carry snare/riser into Drop 2)
7. Drop 2 = 16 — drop 1 + exactly one extra idea (flip). 1-beat void OK if no pivot.
8. Outro — hook fragment + drums

Do not pad a long groove runway after the first hook just to hit bar 28.

Recipe flavors (instincts, not sound-alikes): Calvin sparse (rare — clear piano ballads only), Guetta vocal+electronic drop, Avicii 4-bar loop + airy drop 2, Marshmello hummable chops, DJ Snake chant / aggressive low end / half-time OK, **Diplo / Major Lazer / Jack Ü** maximalist festival hype. Default toward Diplo/Guetta/Snake — not a polite Calvin radio edit. Maximalist on the **mix window / drop**; verses stay the record.

## Club pulse

**Only new Auto sound** — thin songs only. **Keep this lock.**

- Four-on-the-floor kick + bass weight; duck/HPF original low end.
- Slamming or moderate kits → **no pulse**. Use existing SFX-row one-shots.
- Mute kick+bass in build-out, breakdown, void, **and the pivot wallpaper window**.
- Pulse kick/bass are first-class SFX menu items (same library Auto places).
- **ONE kick and ONE bass at a time.** Two kicks = hard fail.

Sound sources: clip effects (reverb/echo/pitch/flanger/blur only) + SFX menu one-shots (including Club Kick / Club Bass) + arrangement.

## Tempo

**Keep this lock.**

- Keep midtempo (~90–100), house (~124–130), festival (~140–150) pockets.
- Double-time only when 2× lands in a pocket; check half/double before stretch.
- Vocal stretch ≤ ~8%; bed/instrumental ≤ ~15%.
- If stretch wrecks the vocal → keep BPM, club-ify with arrangement + energy.
- Britney-class mashups stay ~94 (Oops bed / BOMT vocal). Paramore-class stays ~144.

## Mashup (2…5 songs)

**Keep role locks.** N-song club mashups use the same locked Drop 1 join.

- ONE club bed (drums / pocket / simple harmony); others = vocal-hook candidates.
- **Oops × BOMT:** Oops = bed, BOMT = Drop 1 vocal, Oops chorus may return as Drop 2 flip.
  Title/groove lock wins over stem kick-energy and vocal-density skew — in duo **and**
  N-song crates when both Britney tracks are present.
- First complete **bed** hook before the pivot must source the bed's **title
  chorus** (measured **first-title window**: capped before verse 2, local
  energy floor, title-token vocal boost). Pick the **first downbeat** of the
  title lift (~46s), not prechorus @40.4s, chorus tail @50.5s, or verse 2
  @65.7s / @78s. When a Demucs **vocals** sidecar is present, title-chorus
  detection prefers **stem vocal onset** in the title window over full-mix
  energy that peaks on the chorus tail (“got lost in the game / oh baby”).
  Bounce score dumps `chorusOrDrop`, measured entrance, catalog pool, and
  raw qualifying downbeats. A 16-bar Deck A **timeline** before Drop 1
  repeats the same **~8-bar title island** (hold), never walking source
  linearly into verse 2. Guest Drop 1 **places** the title-chorus downbeat
  (BOMT “hit me” ~43s on vocals.wav), not AutoMashUpper’s best-score island
  when that island is a prechorus pickup (confess ~32s / @47.1s). Bounce
  dumps `Drop 1 guest placed @Xs (titleEntrance= mashability= chorusOrDrop=)`.
  Guest Drop 1 uses the same first-title window (BOMT “hit me”
  ~43s), not loneliness verse.
- Drop 1 = strongest full hook (**hook-replace**: guest in, bed vocal carved out).
  When stretch gate fails, **cameoChop** guests still own Drop 1 as phrase-aligned
  islands at native tempo — do not demote them to post-drop groove slots only.
- Drop 2 = a different song’s hook (duo may flip to bed chorus) — not louder stack.
- Dual vocals are NOT the default. Optional call-and-response ≤ 8 bars, then back to one voice.
- Still ONE kick and ONE bass — reject dual full-mix kick/sub stacks.
- Remaining songs: 8–16 bar cameos (verse/breakdown/outro) **after** Drop 1 so the join stays early, or short chops if gates fail.
- Pitch the bed (≤ ~2 st); never force a star vocal through illegal stretch.
- Prefer Camelot same → ±1 → relative. Skip or cameo-only when song 4/5 fails.
- Minimum stay 8 bars; prefer 16 on choruses. No 4-bar ping-pong (pivot grains are supporting, not identity stays).
- Ballad on a peak-time bed → breakdown runway, not a slam.
- Cap at 5 songs.

Ported heuristics (Swift reimplementations — cite in code):
- **AutoMashUpper (Davies 2014):** mashability is LOCAL per 8–16 bar island (harmonic / rhythmic / spectral); search beat offsets; asymmetric vocal-over-bed.
- **AutoMashup 2025 (BSD-3):** stem *role proxies* from vocalPresence vs bass/drum curves (no Demucs runtime); directional compatibility. Optional Demucs **sidecars** may refine pivot grain + kick ownership if already on disk.
- **Mixxx AutoDJ phrase match:** transition = outro∩intro; delay long intros so endings meet; far BPM → tape-stop on **non-pivot** joins, not vocal wreck. Pivot joins stay hard-cut.

## Opportunity evidence

Propose phrase-aligned opportunities when measured:

- repeated or highly similar section
- energy rise or fall
- instrumentation / drum density change
- temporary reduction in vocal activity
- chorus, bridge, breakdown, pre-chorus, intro, or outro boundary
- 8-, 16-, or 32-bar structural completion
- low-information repeated material
- strong novelty event
- shared title/hook token between Deck A’s last word and Deck B’s attack

## Transformation families

### Arrangement
- rebuild onto the club phrase grid
- play one complete A hook, then pivot, then Drop 1 — do not skip the title
- return to the hook for drop 1 / drop 2
- shorten redundant bars **after** the first join (cut earlier, not later)
- compress or replace the outro

### Transition
- **Xirex pivot wallpaper (default Drop 1):** 1-beat last-word loop 4–8×
  (default 8× = 2 bars) + HPF → hard cut at **full clip volume**
- intentional pre-drop void **only** when there is no pivot loop (plain Drop 2)
- reverse lead-in (non-pivot)
- equal-power overlap (verse→groove / non-pivot handoffs only)
- hard hype cut: **no fade-in**. Anti-click is a tiny sample microfade at the
  splice if required by the renderer — never an audible volume ramp

### Energy shaping
- remove kick/bass on the pivot window / build-out
- restore the full spectrum on the incoming downbeat (the slam)
- HPF/blur sweep across the 1–2 bar loop only (volume stays up)
- use contrast rather than a gradual fade-in into the new vocal

### Pulse / SFX
- thin-song club kick / bass weight (first-class SFX menu items; one at a time)
- **Mix-window stack (maximalist):** riser + snare + tape-stop take-out end
  on the last pivot beat (not the guest downbeat, not title-hook onsets).
  Then extra impacts / air sweep / clap fill ride the **drop bars** on extra
  SFX rows. Drop 1 mix windows keep this stack even when flavor would have
  been sparse; verses stay one record. Sparse Drop 2 stays impact-only.
- Extra one-shots (crash, reverse cymbal, …) may dress **later** builds /
  Drop 2 — not verses
- cymbal punctuation ≤ 2 total; no mid-drop wallpaper; no verse wallpaper
- clip FX in the mix window: pivot HPF/blur; not echo-throw spam

Pulse and SFX must support an underlying musical transformation. Hype is
the join and the drop, never a second kick or verse wallpaper.

## High-confidence behavior

With reliable section, beat, and phrase analysis:

- emit intro → complete hook → pivot → Drop 1 (~bar 16–24) → break → Drop 2
- include non-SFX arrangement transformations (the pivot loop + hook-replace)
- land the familiar hook on drop 1 **on a real line downbeat**
- add exactly one extra idea on drop 2
- keep any non-pivot voids phrase/beat aligned

These are planning targets, not unconditional quotas. Explain fewer edits.
Never invent 1/8 spam to look busy.

## Low-confidence behavior

When structure, phrase, or beat confidence is low:

- do not invent structural cuts **through titles**
- still impose filter + pulse + SFX energy curve
- prefer the same earlier Drop 1 shape if a complete hook island exists
- permit edge trimming; 1-beat void only on plain (non-pivot) drops
- degrade non-pivot mashup handoffs to clean phrase-aligned crossfades
- if phrase confidence cannot support a last-word grain, **skip the loop**
  rather than chopping the title — then Drop 1 may use a plain hard cut or void

## Cut rules

- Cuts must land on verified beat and phrase boundaries.
- **Cut none of the important lines.** Opening title/chorus of Deck A finishes.
  Incoming hook starts on the downbeat of a real line, not mid-word.
- Do not cut through an active vocal phrase without explicit masking (the
  pivot grain is the *last beat after* the line completed).
- Each cut requires a structured AutoCutRecord.
- Reordering requires stronger evidence than shortening.
- Prefer removing or repeating complete phrase units.
- Mask non-pivot cuts with overlap, dropout, impact, echo, void, or another
  justified transition. Pivot Drop 1 is masked by the loop + slam, not a fade-in.
- Accidental silence is invalid. Pivot joins must not go quiet.

## Variation

Do not apply the same flavor to every song.

Choose from measured texture + seed (hype-biased):

- sparse piano/vocal/bass (Calvin-class) — only clear ballads
- vocal + electronic drop (Guetta-class)
- four-bar harmonic loop (Avicii-class)
- hummable chop drop (Marshmello-class)
- chant / aggressive low end (Snake-class)
- maximalist festival / global-bass (Diplo-class) — default for pop-over-club and dancehall midtempo

Avoid stacking two dense midrange leads on the drop. Hype is density of FX/SFX
layers **on the mix window / drop** — still one kick and one bass — not on verses.

## Decision audit

Before declaring success, report:

- **First Deck A hook is a complete phrase (≥8 bars), not a title teaser**
  (no first-“Oops” / first-“baby” chop). If the loop was skipped, say why.
- **Club flavor is festival (Diplo / Guetta / Snake), not a polite
  preservation / Calvin radio edit** — unless the song is a clear piano ballad.
- tempo pocket decision and stretch/pitch gates
- pulse policy (wrote kick vs skipped second kick)
- club flavor
- mashup vocal vs bed assignment (or refusal)
- whether Drop 1 used **pivot wallpaper + hard cut** (and token, repeat count, bar)
- whether a 1-beat void was used (must be a non-pivot drop)
- incoming Drop 1 fade-in (must be none / inaudible microfade) and volume (~full)
- mix-window RMS before incoming (must not drop into a hole; dead air / fade-to-silence is a fail)
- pivot grain count (4–8× / 1–2 bars) and pivot clip volume (loud, not ducked)
- mix-window placement volumes (every song clip has an explicit volume)
- mix-window SFX (take-out ends before Drop 1 attack; air/clap/impact ride the drop; title-hook onsets uncovered)
- all opportunities considered
- why each selected opportunity was chosen
- why rejected opportunities were rejected
- confidence in each decision
- whether a test passes because an operation was avoided
- which decisions were based on measured evidence versus a heuristic
- stem sidecar use (vocal grain / drum kick) vs curve proxies
