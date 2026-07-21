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

## Implementation notes

- Party Mode state is nonpersistent and separate from every project/audio model.
- App-owned overlays remain in the same environment and update live.
- Document pickers, the system share sheet, and native alerts retain system chrome.
- Screenshot-only activation uses the Debug launch argument `-MixrPartyModeScreenshot`; normal launches remain off.
