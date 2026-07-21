# Party Mode visual QA

Reference: `ChatGPT Image Jul 17, 2026, 08_32_17 PM.png`

Viewport: iPhone 17 Pro landscape, populated `My Remix 3` project, 2622×1206 capture.

## Round 1 — `mixr-party-settled-round1.png`

| # | Component | Observed discrepancy from reference | Correction applied |
|---|---|---|---|
| 1 | Transport perimeter | The upper-left edge reads violet; the reference begins cooler blue there. | Replaced angular party rims with directional cool-leading gradients. |
| 2 | Transport perimeter | The upper-right edge finishes cyan; the reference finishes violet/magenta. | Put violet/lavender/magenta at the shared upper-trailing end. |
| 3 | Transport bottom edge | The line is more uniformly saturated than the reference’s light-catching rim. | Reduced major-panel primary opacity and retained layered near/ambient bloom. |
| 4 | Tracks panel | The left cyan edge is too dominant and flat. | Lowered major crisp-rim strength and broadened the low-opacity bloom. |
| 5 | Timeline panel | The lower edge is magenta-heavy; the reference keeps more cool blue on the lower-leading run. | Corrected gradient direction to start at bottom-leading cyan/blue. |
| 6 | Controls panel | Cyan and magenta split too evenly across the perimeter. | Shifted compact/trailing variants toward blue-violet with magenta confined to the trailing catchlight. |
| 7 | Shared panel seams | Adjacent full rims visually stack into harder dividers than surrounding edges. | Reduced major stroke width/opacity so shared seams remain thin at the preserved zero-gap geometry. |
| 8 | Effects tray top edge | The edge is crisp but lacks the reference’s soft nearby lavender reflection. | Increased near-glow contribution while reducing primary saturation. |
| 9 | Effects tray lower edge | The lower perimeter is too strongly magenta. | Rebalanced the shared gradient toward cool lower-leading light. |
| 10 | Play button rings | Four visible rings read busier than the reference. | Removed the innermost extra ring and kept two inset rings plus the perimeter rim. |
| 11 | Play button rim hue | The outer ring picks up cyan; the reference is violet/lavender dominant. | Gave the play perimeter a semantic violet gradient. |
| 12 | Play button glow | The purple halo spreads too far into the transport. | Reduced both play glow radii and ambient opacity. |
| 13 | Play button fill | The center highlight is slightly too pale. | Deepened the violet core and reduced the lavender hotspot. |
| 14 | Export button | The border is crisp but its controlled outer glow is weaker than the reference. | Increased export near and ambient glow without changing the dark interior. |
| 15 | Import Songs button | Its cyan/magenta rim competes with Export. | Reduced normal button rim/glow strength to restore the hierarchy. |
| 16 | SFX footer button | Its perimeter is as bright as the wider Import action. | Applied the same compact button hierarchy with a smaller glow scale. |
| 17 | S/M controls | The lower-right magenta is too prominent; the reference reads mostly cool blue/violet. | Removed magenta from compact-control gradients. |
| 18 | Song artwork chips | Semantic edge color is not consistently dominant over pearl reflections. | Added a dedicated track-chip role using only the track color plus a restrained pearl catchlight. |
| 19 | SFX song chip | The white perimeter is too strong around the newer pearl/lavender chip. | Kept the new SFX body and reduced its dedicated semantic rim to pearl-lavender. |
| 20 | SFX row card | The row perimeter reads white instead of reflected lavender. | Removed the broad white semantic stop and reduced semantic-surface opacity. |
| 21 | Timeline clips | Party edges add too much brightness to already luminous semantic clips. | Added a dedicated low-opacity timeline-clip role with minimal glow. |
| 22 | Effect cards | Shared Party light is slightly too uniform across all identity colors. | Kept each effect color dominant and limited the shared lavender reflection to one narrow transition. |
| 23 | Logo waveform | It does not catch the same subtle lavender light as the reference. | Added a conditional, small-radius icon glow that is absent in normal mode. |
| 24 | Inner pearl edge | A full white inner rim makes large panels feel outlined rather than glass-lit. | Masked the inner pearl highlight to a faint directional catchlight. |

All Round 1 corrections are implemented before the Round 2 capture.

## Round 2 — `mixr-party-round2-a-upright.png`

Compared the corrected populated-project capture against the reference and
reviewed the activation recording plus app-owned overlays.

| Component/state | Observation | Correction or result |
|---|---|---|
| Shared panel lighting | Direction now reads as one environment: cool lower-leading light and violet/magenta upper-trailing light. | Kept the shared token gradient and varied only the documented lighting phase per surface. |
| Panel seams | Zero-gap panel geometry no longer creates muddy blocks, but the line was still slightly more cyan and crisp than the reference. | Shifted the first stop to electric blue, reduced cyan span, and increased layered near/ambient bloom. |
| Play control | Violet hierarchy and white symbol were correct, but the rings still read too far inside the 40×40 control. | Moved the primary rim to a 0.45 pt inset, retained one restrained inner ring, and removed the generic crisp play stroke. |
| Export | Dark interior, white content, and shared blue-violet-magenta perimeter match the intended hierarchy. | No geometry or fill change. |
| Effect cards | Identity colors remain dominant and the shared Party reflection stays subordinate. | No global rainbow replacement; semantic gradients remain card-specific. |
| Timeline clips | Music clips keep pink and violet semantic borders with no indiscriminate shared outline. | Kept the low-opacity semantic clip role. |
| Activation glint | The first implementation coalesced insertion and final trim state, making the traveling light effectively invisible. | Added one render yield plus a 16 ms arming delay, then removed the transient layer after 1.1 seconds. |
| Activation glint intensity | Once visible, the same white width was too broad on small and semantic controls. | Added role-aware glint width/opacity; major chrome and play stay strongest while clips/cards are attenuated. |
| Project menu | Menu perimeter follows the live environment without changing layout. | Verified it remained open while Party Mode was toggled off and back on. |
| Delete confirmation | App-owned confirmation glass received the same shared chrome. | Verified without changing modal geometry. |

## Round 3 — final reference-directed correction

Compared the user-provided current capture directly with the reference,
concentrating on the requested roller-rink-at-night bloom, SFX treatment, and
play-rim placement.

| Component | Remaining discrepancy | Concrete correction | Post-fix result |
|---|---|---|---|
| Shared large-panel rims | Too cyan/magenta and graphically crisp; the reference has more electric-blue/violet light suspended in soft lavender bloom. | Rebuilt the shared gradient with explicit stops, reduced cyan coverage, and tuned 5.4/12 pt near/ambient glow radii. | Latest settled capture has a cooler blue leading edge, violet upper/trailing light, and softer reflected bloom without brightening panel interiors. |
| SFX timeline clips | Resting edges remained predominantly neutral gray. | Added a dedicated `sfxClip` role with pearl-white, lavender, violet, and brief electric-blue transitions plus controlled glow. | The outer capsule/handle edges now read pearl-lavender like the reference while the internal SFX symbol stays silver. |
| Current SFX song row | The new row design retained a neutral outline instead of joining the Party environment. | Applied the dedicated `sfxSurface` role to the existing row shape; the newer SFX icon/body design is unchanged. | The row now carries the same related pearl-lavender/blue edge language as its clips. |
| Play rim | Main rim sat visibly inside the button and competed with extra concentric rings. | Put the specialized rim 0.45 pt from the exact circular edge, kept a single fine inner ring, and made the generic play border glow-only. | The luminous lavender-violet rim now sits at the control edge and the unchanged 40×40 geometry reads closer to the reference. |
| Play fill | Center was slightly pale and flat relative to the reference’s violet depth. | Deepened the violet core with a darker purple trailing stop while preserving the white play/pause symbol. | The play control remains the focal point without becoming pink- or blue-dominant. |
| Static performance | The transient layer had to be demonstrably absent after activation. | `isGlintActive` removes the glint shape after the finite task completes; there is no `TimelineView`, repeat, shimmer, or idle timer. | Settled capture contains only static border/glow layers. |

Prior settled visual evidence: `PartyModeQAArtifacts/party-mode-settled-final.png`.
The old start/mid/end files predate the traced-border renderer and are not
accepted as evidence for the refined activation sequence.

## Round 4 — traced-light and layered-glass refinement

Direct comparison inputs:

- Current implementation supplied by the user:
  `codex-clipboard-23547da6-cb08-49d4-a938-bc18d9fec821.png`
- Visual source of truth:
  `ChatGPT Image Jul 17, 2026, 08_32_17 PM.png`

| # | Component | Concrete discrepancy | Correction applied |
|---|---|---|---|
| 1 | Transport enclosure | The perimeter is a flat one-pixel cyan-to-magenta line with almost no surrounding light. | Replaced the two-layer rim with core, near, medium, ambient, and inner-reflection layers. |
| 2 | Transport corners | Square light turns read like a viewport frame; the reference catches light around continuous curved corners. | Party-only perimeter rendering now uses a deterministic 12 pt clockwise rounded path; normal geometry is unchanged. |
| 3 | Transport core hue | The old core stays uniformly saturated and never reaches the reference's pearl-lavender catchlight. | Added a narrow pearl stop bracketed by lavender within the shared directional gradient. |
| 4 | Tracks panel | The left and bottom outline is crisp but has no cyan-blue atmospheric spill. | Added 3.6/8.8/18 pt scaled bloom layers with screen blending only on bloom. |
| 5 | Timeline panel | The border does not separate from the waveform field except as a hard line. | Added the same external glow stack while leaving the waveform field and grid unwashed. |
| 6 | Controls panel | The panel edge is visually detached from Tracks/Timeline lighting. | Uses the shared palette and the same 40 ms panel start, with only its trailing lighting variant changed. |
| 7 | Panel seams | No light spills into the narrow seams among Tracks, Timeline, and Controls. | Ambient glow now extends 18 pt from the perimeter and is attached after each panel's content clipping. |
| 8 | Effects tray perimeter | The top edge is a saturated divider rather than the reference's violet-magenta illuminated lip. | Increased major-panel near/medium bloom and retained the trailing violet/magenta direction. |
| 9 | Effects tray corners | The old square corners do not collect extra light. | The Party perimeter is rounded and receives localized pearl corner catch layers. |
| 10 | Effects tray interior | The gray glass fill competes with edge lighting. | Added centralized Party-only depth opacity to strong glass; its normal-mode value is exactly zero. |
| 11 | Export button | Border is precise but halo is too narrow and there is no interior edge reflection. | Export now uses stronger near/medium/ambient role values plus the shared inner highlight. |
| 12 | Import Songs | The border reads as a colored outline with no soft falloff. | The shared button role now has three separate outward bloom radii without changing its 8 pt shape. |
| 13 | SFX footer button | The perimeter is bright but flat. | It inherits the same layered system at the quieter button scale. |
| 14 | Effect cards | Semantic rims stop directly at the card edge. | Added subordinate semantic near/medium/ambient bloom while keeping each effect color dominant. |
| 15 | Small circular controls | S/M rings are nearly as graphic as the major chrome. | Compact controls use a 0.88 pt core and roughly half-scale glow, well below play-button intensity. |
| 16 | Play outer rim | The visible rim sits too far inside the 40×40 circle. | Moved the specialized outer rim to a 0.08 pt inset at the exact edge. |
| 17 | Play inner ring | The inner ring lacks the reference's pearl-lavender brightness. | Increased the inner catchlight and moved it to a 2.7 pt inset. |
| 18 | Play aura | Purple light ends abruptly close to the circle. | Added independent 9 pt violet and 16 pt lavender aura layers, plus the shared ambient perimeter glow. |
| 19 | Play hierarchy | Multiple similar rings make the control read as line art instead of violet glass. | Rebalanced three rings from bright edge to faint inner depth over a darker radial violet fill. |
| 20 | SFX row card | The new SFX row outline is present but lacks an illuminated pearl-lavender halo. | The existing new row remains intact and the `sfxSurface` role now receives all five lighting layers. |
| 21 | SFX timeline clips | Neutral outlines do not match the pearl/lavender/blue treatment in the reference. | `sfxClip` keeps the real clip shape and adds a static semantic pearl-lavender core with restrained bloom. |
| 22 | Music timeline clips | A shared rainbow trace would obscure semantic pink/purple track identity. | Music and SFX clips explicitly skip the racecar trace; their real semantic outlines remain static. |
| 23 | Activation entrance | The completed border appears immediately and only a white segment travels over it. | Before the head arrives the perimeter is absent; the trimmed settled glow is left behind by the moving head. |
| 24 | Activation path start | SwiftUI's default trim origin does not guarantee the requested top-left or 11 o'clock start. | Added explicit clockwise rounded and circular paths with deterministic start points. |
| 25 | Trace continuity | A trail crossing path zero can disappear or jump. | Added wrapped trim fragments that split the segment across 0/1. |
| 26 | Reconnection | The old activation has no local circuit-closing event. | Added a 100 ms pearl-core/lavender-violet flare only at the deterministic start point. |
| 27 | Returning glint | The old glint neither returns nor fizzles. | Added a 500 ms second pass covering 80% of the path with nonlinear opacity, blur, and trail decay. |
| 28 | Global coordination | Old delays are tied only to a glint phase and do not reflect the requested hierarchy. | Nav starts at 0 ms, panels at 40 ms, tray at 75 ms, and buttons/cards at 90–100 ms. |
| 29 | Interruption | Disabling mid-animation can allow a stale completion to mutate current chrome. | A single activation task is cancelled and guarded by the activation identifier; the frozen current trace fades out in 240 ms. |
| 30 | Settled resource use | The old transient state needs stronger proof that no work remains. | The temporary 16 ms task ends at 1.64 seconds and transient views are removed; there is no `TimelineView`, repeat, display link, or idle phase. |

All 30 Round 4 corrections are implemented in the shared Party Mode renderer.
The generic iOS Simulator build and source architecture harness pass. A fresh
full-app settled/trace-frame recapture is still required: this Codex command
environment currently receives `CoreSimulatorService connection became
invalid` before device discovery even while the user's GUI Simulator works.
This is recorded as an evidence limitation, not as a passed visual check.

## Round 5 — representative 1×/2×/3× renderer check

Actual production modifiers were rendered with SwiftUI `ImageRenderer` at
420×280, 840×560, and 1260×840 pixels. Evidence:

- `PartyModeQAArtifacts/party-border-scale-1x.png`
- `PartyModeQAArtifacts/party-border-scale-2x.png`
- `PartyModeQAArtifacts/party-border-scale-3x.png`

| Component | Remaining discrepancy | Correction applied |
|---|---|---|
| Major panel halo | The five layers were present, but the medium and ambient falloff remained too quiet around long straight edges. | Raised major near/medium/ambient opacity to 0.42/0.24/0.13, staying within the requested ranges. |
| Export halo | The compact sample retained a crisp outline but still lacked the reference's broader reflected light. | Matched Export's bloom ceiling to 0.42/0.24/0.13 while keeping its dark fill. |
| Pearl transition | The narrow white transition resolved as a small static pinpoint at 3×. | Reduced its core opacity and left broader lavender stops on both sides; corner catchlights remain separate. |
| 1× stroke | The 1.02 pt major core remains continuous through all four curves with no one-pixel dropout. | No width increase. |
| 2×/3× stroke | The perimeter scales to approximately two and three physical pixels without banding in the directional gradient. | No scale-specific rendering branch. |
| Play rings | Outer rim remains on the 40 pt edge and concentric rings remain distinct at all three scales. | No geometry change. |

## Round 6 — frozen activation-frame continuity

The actual production modifier was frozen at normalized global progress 0.12,
0.30, 0.616, 0.695, and 0.878. These correspond to initial trace, mid trace,
major-panel reconnection, early afterglint, and late afterglint.

| State | Observation | Correction or result |
|---|---|---|
| Initial trace | Major rounded path begins just after the top-left radius; the circle begins at 11 o'clock. Unvisited perimeter is absent. | Pass. |
| Mid trace | The settled core and all three bloom layers remain behind the clockwise head without revealing the unfinished lower/leading perimeter. | Pass. |
| Reconnection | The major panel closes exactly at its start and shows a small pearl/lavender flare; smaller controls are already in their faster second pass. | Pass. |
| Early afterglint | Trail wraps and decays correctly, but the gradient did not guarantee a pearl-white leading point on every edge. | Added a dedicated wrap-safe white head segment over the decaying trail. |
| Late afterglint | Trail length, blur, and opacity have nearly disappeared while the settled border remains unchanged. | Pass. |
| Settled | Transient layers are absent and only the static five-layer chrome remains. | Pass in renderer output; full-app paused pixel-identity capture remains pending CoreSimulator access. |

## Implementation notes

- Party Mode state is nonpersistent and separate from every project/audio model.
- App-owned overlays remain in the same environment and update live.
- Document pickers, the system share sheet, and native alerts retain system chrome.
- Screenshot-only activation uses the Debug launch argument `-MixrPartyModeScreenshot`; normal launches remain off.
- Headless normal-mode comparison uses the Debug-only `-MixrVisualQAScreenshot`
  argument. Both QA arguments bypass Simulator audio-graph construction only;
  production and ordinary Debug playback paths are unchanged. This avoids a
  confirmed CoreAudio output-node RPC timeout in the iOS 26.5 Simulator host.

## Round 7 — unclipped main chrome and capture-path correction

Compared the production five-layer renderer again with the reference after
CoreSimulator device discovery returned. The app built and installed, but the
Simulator framebuffer endpoint continued to invalidate its XPC connection.
This round therefore also corrected the QA capture path rather than accepting
the older distorted framebuffer images.

| Component/state | Remaining discrepancy | Correction and evidence |
|---|---|---|
| Transport, Tracks, Timeline, Controls, Effects | Ambient glow was authored inside views that a parent clipped, so medium/ambient bloom could not spill cleanly into seams. | Moved only the Party perimeters into `PartyModeMainChromeOverlay`, rendered after the unchanged clipped application content. Normal layout remains the original `VStack`; the overlay is clear, hit-test disabled, and accessibility hidden. |
| Main panel geometry | Separate internal modifiers could drift from one another as effects height changed. | Centralized the transport, three-column middle row, and effects perimeter in one overlay using the existing live dimensions and shared animation state. |
| Text/icon hierarchy | Panel content needed to retain its existing z-order while the outer halo escaped content masks. | Main Party chrome is below custom floating overlays and never participates in layout or hit testing. |
| Prior full-app captures | The verification wrapper always rotated content, even when the simulator was already landscape, producing distorted evidence. | The wrapper now preserves an existing landscape canvas and rotates only a portrait host. |
| Simulator cutout/volume artifacts | `simctl io screenshot` included device-chrome artifacts and later failed at the framebuffer service. | Added a Debug-only live-window capture that saves the actual app hierarchy to its sandbox without system cutout chrome. It is excluded from Release. |
| Normal-mode pixels | The new shared overlay must be visually inert while Party Mode is off. | Rendered the production modifier at 3× beside an identical unmodified baseline; the PNG pixel data is byte-identical. Evidence: `round7-renderer/party-border-normal-baseline-3x.png` and `round7-renderer/party-border-normal-modifier-off-3x.png`. |
| Play focal treatment | The earlier scale probe used a flat placeholder fill and did not exercise the real violet depth surface. | The probe now renders `PartyModePlayButtonSurface`, the edge rim, concentric rings, white symbol, and both aura layers together. |
| Trace continuity | Needed fresh confirmation after moving the large perimeters outside clipping. | Re-rendered initial, mid, reconnect, early-glint, late-glint, and settled production states at 3× in `PartyModeQAArtifacts/round7-renderer/`; deterministic starts, clockwise travel, reconnection, wrap, and fizzle remain continuous. |

Fresh verification in this round:

- Party Mode architecture/source harness: pass.
- Clip-editing layout harness: pass.
- SFX layout and visual-token harness: pass.
- Debug and Release iOS Simulator builds: pass.
- Auto Remix plan and rendered-PCM regression suites: pass.
- Production Party perimeter renderer at 1×, 2×, and 3×: pass.
- Representative normal-mode modifier comparison at 3×: pixel-identical.

## Round 8 — live full-app glow correction

Fresh app-window evidence (no Simulator cutout or volume overlay):

- `PartyModeQAArtifacts/simulator-normal-round7-landscape.png`
- `PartyModeQAArtifacts/simulator-party-settled-round7-landscape.png`
- `PartyModeQAArtifacts/simulator-party-settled-round8-landscape.png`
- `PartyModeQAArtifacts/round8-animation/initial.png`
- `PartyModeQAArtifacts/round8-renderer/`

| Component/state | Live discrepancy | Correction and post-fix result |
|---|---|---|
| Major perimeter hierarchy | The 1 pt core still dominated at full-app scale even though the isolated renderer contained three blur layers. | Kept the visible core at 1.02 pt and increased only the blurred strokes' light-carrying width through centralized near/medium/ambient scale tokens. The updated live capture shows a precise core inside three readable falloff zones. |
| Tracks/Timeline/Controls seams | The Round 7 capture proved clipping was fixed, but the low-energy blur did not visibly illuminate the narrow seams. | The wider light-only strokes now spill cyan-blue and violet light into seams without a color wash behind the waveform field. |
| Transport enclosure | The live perimeter read as a flat saturated gradient. | Reduced major core opacity, desaturated the cyan/magenta endpoints, and strengthened pearl-lavender corner catches. The enclosure now reads as edge-lit dark glass. |
| Effects tray | Its rim was visible but the top edge and corners lacked the reference's suspended violet/magenta haze. | The shared major-panel bloom now remains visible above the tray while the centralized Party-only black depth overlay keeps the interior dark. |
| Export/Import/SFX buttons | Each had a crisp outline with insufficient outward falloff in the real hierarchy. | The same shared blurred-stroke energy correction produces a broader controlled halo; button interiors remain unchanged dark glass. |
| Effect cards | Semantic colors stopped too abruptly at their rims. | The shared scale tokens increase only their subordinate semantic bloom; Auto, Reverb, Echo, Pitch, Flanger, and Blur identities stay dominant. |
| Play perimeter | `strokeBorder` inset the specialized bright rim from the requested 40 pt edge. | Changed only the overlay rim to an edge-centered `stroke`; frame, icon, fill, and transport spacing are unchanged. |
| Play aura | The live control had visible rings but the glow dropped too quickly into the navigation background. | Wider shared bloom supplements the dedicated 9/16 pt violet-lavender shadows, producing a gradual focal aura without enlarging the control. |
| Activation evidence | Repeated `simctl` launches were invalidating CoreSimulator between frozen frames. | Added a Debug-only one-launch live sequence capture for initial, mid, reconnection, early afterglint, late afterglint, and settled frames. Release and ordinary Debug launches contain no QA behavior. |

The initial live frame confirms that unvisited perimeter sections are absent,
the rounded-rectangle heads start after the top-left radius, the play head
starts near 11 o'clock, and content remains untouched by the light trace.

## Round 9 — capture-clock correction and final deterministic evidence

The first recovered CoreSimulator run produced all six requested live-window
files, but the five files after the initial frame were byte-identical. The
cause was in the Debug QA recorder, not the Party renderer: full-resolution
PNG compression and disk writes ran synchronously on the main actor between
samples, preventing the 16 ms activation task from advancing. Those invalid
duplicate artifacts were removed rather than accepted as animation evidence.

The recorder now snapshots committed UIKit hierarchies into memory at the
requested times, yields to the shared activation clock, and performs PNG
encoding only after every timing-sensitive sample is complete. The
architecture harness covers this ordering, and a fresh Debug Simulator build
passes. A subsequent cooldown retry could not install that build because this
Codex process again lost CoreSimulator XPC before device discovery (`simdiskimaged`
crashed or was not responding). The user's GUI Simulator can remain healthy
while the sandboxed `simctl` client has this host-only failure, so a corrected
second live sequence is not claimed here.

Fresh post-correction deterministic evidence uses the actual production
modifier in `PartyModeQAArtifacts/round9-renderer/`:

- Initial trace, mid trace, reconnection, early afterglint, and late afterglint
  have five distinct SHA-256 hashes.
- Settled 1×, 2×, and 3× renders retain a precise core plus three outward bloom
  falloffs, continuous rounded corners, and the edge-centered play rim.
- The 3× normal baseline and the same view with the inactive Party modifier
  have identical PNG bytes (`2cf1213343de84eaf0f9612f2b37c09f190ff2151da2279399c6f3ed19097027`).
- The final full-app normal-mode recapture remains unavailable for the same
  CoreSimulator XPC reason. The latest valid full-app normal capture is Round
  7; all subsequent visual changes are gated by `chromeOpacity` and the fresh
  post-change production-modifier comparison is pixel-identical.

No visual correction remains open in the production modifier. The only
remaining evidence limitation is the unavailable second live-window sequence
and final full-app normal recapture from this sandboxed Simulator client.

## Round 10 — slower trace and globally sequenced afterglint

This timing-only pass reduces both perimeter-trace and returning-glint velocity
to 75% of the prior value. Surface staggers, the 100 ms reconnection flare,
colors, glow layers, geometry, exit timing, and Reduce Motion behavior are
unchanged.

| State | Timing and visual result |
|---|---|
| Initial/mid trace | Major panels now take 1.28 s and shared buttons take approximately 0.827 s to close. The same deterministic clockwise paths, heads, trails, and completed-border reveal remain intact. |
| Final connection | The last far-staggered major panel completes its trace and 100 ms flare at 1.455 s. Smaller surfaces remain statically closed; none shows a returning glint while waiting. |
| Global afterglint | Every eligible surface begins its second pass from the same 1.455 s global gate. Major glints run approximately 0.667 s; role-specific glints retain their existing relative durations at the same 75% velocity. |
| Settled | The finite activation clock ends at approximately 2.122 s and removes transient trace, flare, and glint layers exactly as before. |

Fresh production-modifier evidence is in
`PartyModeQAArtifacts/round10-timing/`. Initial trace, mid trace, final
reconnection, early synchronized glint, and late fizzle all have distinct PNG
hashes. The final-connection frame shows the local pearl flare at the last
panel's start point with no glints on already-closed controls; the next frame
shows simultaneous glint heads on the panel, button, and play circle.

The 3× normal baseline and inactive Party modifier remain byte-identical with
SHA-256
`2cf1213343de84eaf0f9612f2b37c09f190ff2151da2279399c6f3ed19097027`.

Fresh live-window attempts, including a cooldown retry after the timing build,
both ended before device discovery because this sandboxed `simctl` client lost
CoreSimulator XPC while `simdiskimaged` was unavailable. Round 10 therefore
relies on the production SwiftUI renderer frames above rather than claiming a
new live-app capture.
