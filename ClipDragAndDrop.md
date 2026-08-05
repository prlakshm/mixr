# Clip drag-and-drop — behavioural spec

How moving a clip on the Mixr timeline behaves, written so it can be rebuilt on
another stack. Every number is the value the app actually ships; source
references are to `Mixr/TimelineScreen.swift` and `Mixr/Models/MixrTimeline.swift`.

Scope: dragging a clip **horizontally within its own track**. A clip never
changes track by dragging — vertical cursor movement lifts the clip visually but
the drop always commits to the track it started on. (Reordering *tracks* is a
separate gesture on the row gripper.)

---

## 1. Coordinate model

Two coordinate systems, and the separation matters:

| | |
|---|---|
| **Timeline units** | The model's time axis. `130 units = 240 s`, so **1 unit ≈ 1.846 s**. Clip `start` and `length` are in units. |
| **Screen px** | Rendering. `contentW` px spans `contentUnits`, so `px = (units / contentUnits) × contentW`. |

All drag positions are tracked in a coordinate space anchored to the **outer
container of the track area — outside every scroll view**. This is the single
most important structural decision: it means the drag maths does not change
meaning when the timeline scrolls underneath the finger.

Two derived positions are computed each frame, and they are *not*
interchangeable:

```
proposedStart = (proposedLeadingEdgePx / contentW) × contentUnits   // clip's leading edge
pointerUnit   = proposedStart + (grabOffsetPx / contentW) × contentUnits  // the finger
```

`grabOffsetPx` is the distance from the clip's leading edge to the finger at
grab time, captured once. Rule of thumb:

- **Placement** is expressed in terms of the *leading edge* (`proposedStart`).
- **Intent** — which edge you mean to snap to, which clip you mean to cut — is
  read from the *finger* (`pointerUnit`).

Getting this backwards is the classic bug: grab a long clip near its right end,
and edge decisions made from the leading edge will target a clip several seconds
away from where you are actually pointing.

---

## 2. Gesture lifecycle

```
idle → armed → dragging → committed
           ↘ cancelled
```

**Arm** — long press **0.50 s**, allowing at most **8 pt** of movement. On arm:

- capture an undo snapshot ("Move Clip") — one snapshot, not one per frame;
- the clip lifts *in place*: scale **1.05**, offset **−6 pt** vertically;
- shadows: black at 55% opacity, radius **18**, y **+10**; plus a coloured glow
  in the track's colour at 44%, radius 14;
- every **other** track dims under a **52% black scrim**, faded over **0.13 s**;
- the drop line appears immediately, seeded at the clip's current start so it
  fades in *in place* rather than flying in from elsewhere.

**Settle** — movement is ignored for a further **0.09 s** after arming. Without
this, the finger jitter that accumulates during a long press snaps the clip
sideways the instant it lifts.

**Drag** — each cursor update recomputes the proposed leading edge, re-resolves
the drop, re-targets the drop line, and feeds the auto-scroll loop.

**Commit** — on release, the drop is re-resolved **with hysteresis disabled**
(see §4) so the committed answer reflects where the clip actually is, not a
sticky earlier decision. Then: apply the drop, animate with a spring
(response **0.38**, damping **0.80**), select the moved clip, move the playhead
to the committed start, and close the undo step.

**Cancel** — releasing before the settle completes discards the undo snapshot
and springs back (response 0.32, damping 0.82).

---

## 3. The three visual elements

### 3.1 The coloured drop line

- **2 pt** wide, **full row height**, corner radius 1.
- Painted in **the track's own colour** at **0.85** opacity, with a glow shadow
  in the same colour at 0.60 opacity, radius 6.
- Drawn at `screenX − 1` so the 2 pt line straddles the boundary rather than
  sitting to one side of it.
- Rendered in screen space **outside the scroll views**, like the lifted clip,
  so it is never clipped by the lane or dragged by scrolling.

**Its motion is the whole trick.** The line eases to its target with
`easeOut 0.10 s` **only when a snap is involved** — that is, when the previous
frame was snapped or the new frame is snapped. In free space it tracks the
finger 1:1 with no animation at all.

That conditional is what produces the "magnetic" feel: the line glides the last
few points onto an edge and releases smoothly when you pull away, but never lags
behind your finger when you are placing freely. Animating it unconditionally
makes the whole drag feel soft and laggy; animating it never makes snapping feel
like a glitch.

### 3.2 The shadow of the original location (ghost)

The clip keeps rendering **in its original lane, at its original start and
length, at 0.28 opacity**, for the entire drag. It never moves and never
animates.

It does two jobs:

1. It answers "where did this come from?" while the lifted copy is under the
   finger.
2. It is the **restore target** — see rule 1 of the ladder below. Drop back onto
   the ghost and nothing happens at all.

The lifted clip is a *separate* view drawn in screen space; the ghost is the
in-lane render. They are two different things on screen at once, which is what
makes the gesture legible.

### 3.3 Neighbour shift preview

When the line is snapped to an edge, the two clips forming that seam separate to
show the slot opening:

- the clip whose **end** equals the snap point shifts **−20 pt**;
- the clip whose **start** equals the snap point shifts **+20 pt**.

This is a render-only offset — no model change, no reflow. It reads as the
timeline making room.

---

## 4. Drop resolution — the priority ladder

Resolved every frame. First rule that matches wins.

```
0. Hysteresis: if |pointerUnit − lastPointerUnit| < 8 pt (in units)
                → return the previous result unchanged
1. Ghost restore:  |proposedStart − originalStart| ≤ snapZone
                → place(originalStart)                          // no-op drop
2. Edge snap BEFORE: pointer within snapZone of some clip's START
                → place(target.start − movingLength),
                  clamped so it cannot overlap the preceding clip
3. Edge snap AFTER:  pointer within snapZone of some clip's END
                → place(target.start + target.length)
4. Literal gap:    the leading edge does not land inside any clip body
                → place(proposedStart)  — exactly where released
5. Insert into body: pointer strictly inside a clip, outside both edge zones,
                     and that clip is longer than 2 × minClipLength
                → insertIntoClip(target, splitUnit, insertStart)
6. Fallback      → place(proposedStart)
```

Constants: **snapZone = 10 pt**, **hysteresis = 8 pt**, both converted from px
to units against the current zoom, so they stay a constant *visual* distance at
any zoom level rather than a constant musical distance.

Notes on the ladder that are easy to get wrong:

- **Rule 1 must come first.** Without an explicit no-op case, releasing a clip
  where you found it still runs a ripple and writes an undo entry, so a
  cancelled-in-spirit drag becomes an edit.
- **Rule 2 places by the trailing edge.** Snapping "before" a clip means the
  dragged clip should *end* where that clip begins, so its start is
  `target.start − movingLength` — then clamped forward so it cannot back over
  whatever precedes it.
- **Rule 4 is deliberately permissive.** If the leading edge is in open space,
  the clip drops exactly there even if its *tail* overlaps a later clip; that
  overlap is resolved by the ripple pass at commit. Forcing an insert here makes
  free placement feel like it fights you.
- **Hysteresis is disabled at commit.** During the drag it stops the result
  flickering between two candidates on the boundary; at drop it would mean
  committing a stale decision.

### Two resolvers, on purpose

The **drop line** and the **drop decision** run different logic:

- the line snaps to the nearest **clip edge** within the snap zone, with a
  sticky `activeSnapStart` that holds until the raw start leaves the zone —
  purely visual magnetism;
- the **decision** runs the ladder above off the pointer.

They agree in the common cases and are allowed to differ mid-gesture; the
committed result always comes from the ladder. Recreating this with a single
shared resolver is possible but loses the sticky-line feel.

---

## 5. Split and insert

When rule 5 fires, the drop cuts the target clip in two and drops the moving
clip into the gap.

```
splitUnit = clamp(pointerUnit,
                  target.start + minClipLength,
                  target.end   − minClipLength)
```

`minClipLength = 2 units ≈ 3.7 s`. If either resulting half would be shorter
than that, **the split is refused** and the drop falls back to plain placement
with a ripple. Silent refusal is correct here: the alternative is producing
slivers of audio that cannot be selected or trimmed.

On commit the target becomes two clips:

| | left half (A1) | right half (A2) |
|---|---|---|
| id | keeps the original | **new id** |
| start | unchanged | `splitUnit + movingLength` |
| length | `splitUnit − start` | remainder |
| transitionIn | unchanged | **cleared** |
| transitionOut | **cleared** | inherits the original's |
| source offset | unchanged | `+ leftLength × playbackSpeed` |

Two details carry the audio correctness:

- **The source offset must advance.** A2 is a later window into the same file;
  without offsetting into the source by the left half's duration (scaled by
  playback speed) the right half restarts the song instead of continuing it.
- **Transitions are cleared at the new seams** and preserved at the outer edges,
  so a crossfade that belonged to the end of the original clip stays at the end
  of A2 rather than being duplicated at the cut.

The moving clip lands at `splitUnit` with its own transitions cleared.

**Known gap:** the model supports an animated preview of this — the two halves
separating by the moving clip's length as `insertPreviewProgress` goes 0→1 — but
the live drag currently pins that progress to `0`, so while hovering a clip body
you see only the line, and the split appears on release. If you are rebuilding
this, driving that progress (spring, response ≈ 0.22) is the missing piece that
would make body-insert as legible as edge-snap.

---

## 6. Edge auto-scroll

A 60 fps loop (16 ms tick) runs for the duration of the drag.

- It triggers off **the lifted clip's edges**, not the cursor — you scroll when
  the *clip* presses into the viewport edge, which is what you are actually
  aiming with.
- Ramp is **quadratic**: `t = min(overshoot / 120 pt, 1)`, `delta = 10 pt × t²`.
  Peak ≈ 600 pt/s. The square is what makes the start imperceptible; a linear
  ramp lurches the moment you touch the boundary.
- The loop keeps **its own scroll offset** and recomputes the proposed leading
  edge from it, rather than reading the scroll view's reported offset. The
  platform's scroll-geometry callback lags by a frame or two, and trusting it
  makes the clip drift away from the finger while auto-scrolling.
- Content width is allowed to **grow during the drag** (proposed edge + clip
  width + 35% of the viewport), so a clip can be dragged past the current end of
  the arrangement.

---

## 7. Constant reference

| Constant | Value | Role |
|---|---|---|
| long-press duration | 0.50 s | arm the drag |
| long-press max movement | 8 pt | cancel arming if exceeded |
| armed settle | 0.09 s | ignore movement after arming |
| ghost opacity | 0.28 | original location |
| lift scale / offset | 1.05 / −6 pt | lifted clip |
| lift shadow | black 55%, r18, y+10 | lifted clip |
| lift glow | track colour 44%, r14 | lifted clip |
| scrim | black 52%, 0.13 s | non-active tracks |
| indicator | 2 pt × row height, colour 85%, glow r6 @60% | drop line |
| indicator ease | easeOut 0.10 s (snap transitions only) | magnetism |
| neighbour shift | ±20 pt | seam preview |
| snap zone | 10 pt | edge capture |
| hysteresis | 8 pt | anti-flicker, drag only |
| min clip length | 2 units ≈ 3.7 s | split refusal threshold |
| auto-scroll zone | 120 pt | ramp distance |
| auto-scroll speed | 10 pt/frame ≈ 600 pt/s | quadratic peak |
| drop spring | response 0.38, damping 0.80 | settle |
| cancel spring | response 0.32, damping 0.82 | spring back |

---

## 8. Rebuild checklist

1. Track drag positions in a space that is stable under scrolling.
2. Keep leading-edge and pointer positions separate; use the pointer for intent.
3. Long press to arm, then a short settle before honouring movement.
4. Keep the source ghost visible and immobile for the whole drag.
5. Resolve the drop through an ordered ladder, ghost-restore first.
6. Apply hysteresis during the drag; drop it at commit.
7. Animate the drop line only across snap transitions.
8. Refuse splits that would create sub-minimum clips; advance the source offset
   on the right half; clear transitions at new seams only.
9. Auto-scroll from the dragged clip's edges, on a quadratic ramp, with a
   locally-maintained scroll offset.
10. One undo entry per completed drag; none for a ghost-restore or a cancel.
