# Handoff: build, Simulator screenshots and phone-flow testing (local Mac session)

The cloud session that wrote this ran on Linux, with no Xcode, no Simulator and no Mac.
Everything below was written but **never compiled for iOS or run on a device**.
Your job is to build it, run it in the Simulator in **landscape**, fix what breaks,
capture real screenshots, and test every phone flow.

## Branch and state

- Branch: `claude/remix-quality-audit-26yyt3` (push here; never to `main`).
- PR #8 (Auto Remix / DJ-turn mashups) is already merged into `main`.
- New on this branch, since `main`:
  1. `1c856e5` **iPhone only**: `TARGETED_DEVICE_FAMILY = 1`, `SUPPORTS_MACCATALYST = NO`
     (Debug and Release). iPhone orientations are unchanged. The editor is
     landscape-only in practice: portrait shows the "Rotate iPhone" overlay.
  2. `0499349` **First-launch onboarding tour**: never compiled.
- No PR is open for these two commits yet. Open one when the build is green
  and the user agrees.

## The user's goal

Submit to the App Store this week. Before that:

1. **Build** the app and fix any compile errors in the new tour code.
2. **Open the Simulator in landscape** (iPhone 16 Pro Max is 6.9" and gives App Store
   size 2868×1320), run the real app, and **screenshot every onboarding step**.
   The user may use these for submission. When they ask for edits: make the change,
   **delete the previous set**, and send the new set.
3. **Test every phone flow extensively.** Everything should work and feel seamless.
   Write a full test suite. **If unsure how something should work, ask the user. Don't guess.**
4. The app is used **rotated to landscape**. Test landscape left and right. Portrait
   should only show the rotate prompt.

## Onboarding tour: what was built (approved by the user)

Spotlight tour on the real editor: a dimmed scrim with a cut-out around one real
control, an animated finger, and a glass tip card. **Skip** sits left of **Next**
on every step except the last.

| # | Spotlights (real control) | Gesture | Title / message (final copy, verbatim) |
|---|---|---|---|
| 1 | Import Songs (track list footer, above Effects) | tap | Import your songs / Tap Import Songs to bring in the tracks you want to remix. |
| 2 | First song row | swipe left | Swipe left to delete / Slide a song to the left, then tap Delete to remove it. |
| 3 | Controls column (S/M + volume) | drag | Set each song’s volume / Drag a slider on the right. S solos a song, M mutes it. |
| 4 | First clip of first song (its real toolbar opens) | tap | Tap a clip for tools / Split it, change its speed, duplicate it or delete it. |
| 5 | Effects panel (expanded) | scroll | Tune the sound / With a clip selected, add Reverb, Echo, Pitch and more. |
| 6 | sfx button | tap | Add sound effects / Tap sfx for risers, impacts, bass drops and more. |

Buttons: `Skip`, `Next`, last step `Start mixing`, project menu `Replay tour`.

**Flow, as chosen by the user ("split it"):**
- First launch on an **empty editor** shows **step 1 only**. Touches inside the
  spotlight reach the real Import Songs button.
- Steps 2–6 continue **as soon as the first song lands**: either the user imports
  from step 1, or taps Next and imports later.
- **Skip** ends the whole tour for good.
- Deleting the last song mid-tour pauses the tour until a song exists again.
- Steps 4–5 select the first clip, so the real toolbar shows. The previous
  selection is restored afterwards. Step 5 expands the effects panel.
- Progress persists in UserDefaults (`mixr.onboardingTour.progress`).
- **Replay tour** is in the project dropdown menu.

**Next button (approved after several rounds; don't change it without asking):**
- Rest: `#7231DD` (the Play button purple), **no border**, glow `#7231DD` at 0.50, radius 10.
- Hover (pointer): `#8244E9`, glow 0.70, radius 15.
- Pressed: `#682BCF`, scale 0.97, glow 0.35, radius 6.
- Skip: text button, white at 74% (hover 100%), at least 44 pt tall.

**Files**
- `Mixr/Models/OnboardingTour.swift`: steps, copy, state machine, store (pure Foundation).
- `Mixr/DesignSystem/OnboardingTourOverlay.swift`: SwiftUI overlay, finger, tip card, button styles.
  - Targets report frames with `.onboardingTarget(_:)` (anchor preferences).
  - The overlay is attached at the editor root with
    `.overlayPreferenceValue(OnboardingTargetKey.self)` in `TimelineScreen.swift`.
- `Mixr/TimelineScreen.swift`:
  - Tour state, `tourDidChange`, `replayTour`.
  - Target modifiers on the Import Songs button, the sfx button, the first song
    row, the controls column, the first clip hit area (`TLTrackLane.onboardingClipID`)
    and the effects panel.
- `Mixr/DesignSystem/ProjectDropdown.swift`: `onReplayTour` and a "Replay tour" row.
- `DevTests/OnboardingTourTests.swift` plus `Scripts/run_onboarding_tests.sh`:
  41 flow, copy and wiring checks (pass on Linux).

**Things to verify first on device (unverified, may need fixes):**
- Compile errors in `OnboardingTourOverlay.swift`, which was written without an SDK.
  APIs used: `onGeometryChange`, `contentShape(_:eoFill:)`,
  `AccessibilityNotification.Announcement`, `onHover`.
- **Tip card placement** at real iPhone landscape sizes, including the Dynamic Island
  side and safe areas. Card placement order: right of the target, then left, above, below.
- The anchor frame for the **first clip**, which sits inside a horizontally
  scrolling lane, and for the **effects panel**, whose target sits after
  `.frame(height:)`.
- The scrim blocking touches on steps 2–6, but **not** the Import Songs button on step 1.
- Steps 4–5: the toolbar is positioned at the playhead, not the clip. Check it looks
  right after a fresh import, when the playhead is at 0:00.
- VoiceOver announcements, Reduce Motion (finger still), Dynamic Type at the
  tip card's fixed width.

## Screenshots: use the app's existing QA capture pattern

There is **no UI test target**. The app has DEBUG-only launch-argument hooks in
`Mixr/ContentView.swift`:
- `-MixrEditorVisualQA <state>`
- `-MixrVisualQAScreenshot`

`PartyModeVisualQACapture.capture(filename:)` writes a PNG of the live window to
the app's Documents folder. `PartyModeQA.md` explains why `simctl io screenshot`
was unreliable on this machine. Suggested approach (ask the user if unsure):
- Add a DEBUG-only `-MixrOnboardingStep <1-6>` that forces the tour to that step on
  a populated project, waits for layout, and captures `mixr-tour-step-N.png`
  through `PartyModeVisualQACapture`.
- Or add a proper XCUITest target. It would also cover the flow tests below.
- Use a **copyright-free demo project** for anything that may go to the App Store.
  Don't use the `Dua x Weeknd - My Remix.m4a` file in the repo root, and confirm
  the content with the user.

## Phone-flow test checklist (landscape)

Write each flow as an automated test (XCUITest preferred), and run it by hand too:

- **First launch:**
  - Empty editor shows tour step 1, with no flash of other steps.
  - Tap Import Songs through the spotlight, import, and step 2 appears.
- Next on step 1 without importing, then import later: steps 2–6 resume.
- **Skip** on every step: the tour never returns after relaunch. Replay from the
  project menu works.
- Relaunch at each stage: progress is kept.
- During the tour, delete the last song: the tour pauses, and adding a song resumes it.
- Rotate to portrait mid-tour: the rotate prompt shows and the tour is hidden.
  Rotate back: the tour returns at the same step.
- Small and large iPhones (SE-class landscape, Pro Max), Dynamic Island on the left
  and right side.
- **Core app flows** (make sure nothing regressed):
  - import (Files), reorder, swipe-to-delete
  - solo / mute / volume
  - select clip, then split / speed / duplicate / delete
  - effects on a clip
  - SFX panel: add a sound effect at the playhead
  - Auto remix (one song) and mashup (2+ songs)
  - play / pause / scrub
  - export / share
  - projects: new / switch / rename / delete
  - undo / redo
  - Party Mode toggle (tap the logo)
- Accessibility: VoiceOver through the tour, Reduce Motion, larger text.
- Audio: playback after import, export renders and plays.

## Tests and how to run them

- `Scripts/run_onboarding_tests.sh`: onboarding flow, copy and wiring (passes).
- `Scripts/run_auto_remix_tests.sh pipeline|render|dj`: Auto Remix (passes).
- `Scripts/run_responsive_tests.sh`: needs CoreGraphics, so macOS only. Not run in the cloud.
- `DevTests/*UILayoutTests.swift`, `PartyModeArchitectureTests.swift`,
  `GrayContrastTokenTests.swift`: these source checks **already fail on `main`**
  (18 lines; SFX styling, empty-state CTA, project-rename field). They are not
  caused by this branch. Ask the user whether to fix or update them.

## Other context

- Product and audio rules: `AGENTS.md` (read it).
- Remix and mashup audit and evidence: `docs/AUTO_REMIX_AUDIT.md`.
- Design references (prototype, copy sheet), private links owned by the user:
  - Onboarding prototype canvas: https://claude.ai/artifact/CxGUTUBgKEVNsFW6J43iHi
  - Tour copy sheet: https://claude.ai/artifact/PaNh5r9oiF8miJupX2jAsi
- App Store notes:
  - iPhone-only means 6.9" iPhone screenshots are required.
  - App Review guideline 2.3.3 wants real in-app screenshots.
  - Don't use other companies' trademarks in copy (e.g. "Auto-Tune").
