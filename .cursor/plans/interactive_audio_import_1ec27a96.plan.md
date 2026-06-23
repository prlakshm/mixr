---
name: Interactive Audio Import
overview: Replace static `mockTracks` with a live `TrackLibrary` state object, wire the Import Songs button to SwiftUI .fileImporter, restructure the layout into a single shared vertical ScrollView for linked scrolling, support placeholder-first import with async duration loading, and add gripper-based drag reordering that updates all three columns simultaneously.
todos:
  - id: model
    content: Create MixrTrack.swift and MixrClip.swift in Mixr/Models/
    status: completed
  - id: library
    content: "Create TrackLibrary.swift: placeholder-first addTracks(from:), async duration update by ID, reorder(from:to:)"
    status: completed
  - id: timeline-data
    content: "Refactor TimelineScreen: @StateObject library, remove mockTracks/MockTrack/MockClip, wire .fileImporter, pass tracks into subviews"
    status: pending
  - id: linked-scroll
    content: Replace three independent scroll regions with single ScrollView(.vertical) HStack + inner ScrollView(.horizontal) for timeline only
    status: pending
  - id: sidebar
    content: Refactor TLSongSidebar to take [MixrTrack], add ruler-height spacer, wire showFilePicker binding
    status: pending
  - id: controls
    content: Refactor TLTrackControlsColumn to take Binding<[MixrTrack]>, remove @State volumes dict, bind volume from track model
    status: pending
  - id: reorder
    content: Add drag-to-reorder via gripper handle — DragGesture on sidebar gripper, mutates library.tracks, all columns update simultaneously
    status: pending
  - id: emptystate
    content: "Verify empty state: grid + ruler visible, no rows, Import button always pinned at bottom-left"
    status: pending
isProject: false
---

# Interactive Audio Import — Mixr

## Current architecture pain points

- `mockTracks` is a file-level `private let` read by three completely independent scroll views.
- `TLSongSidebar`, `TLTimelineArea`, and `TLTrackControlsColumn` each manage their own vertical scroll (or no scroll at all), so they drift when content grows.
- Volume state lives in a `[UUID: Double]` dict inside `TLTrackControlsColumn`, not in the track model.

## New file structure

```
Mixr/
  Models/
    MixrTrack.swift      ← replaces MockTrack / MockClip
    TrackLibrary.swift   ← ObservableObject, holds @Published tracks
  TimelineScreen.swift   ← refactored (the only other file touched)
```

No `AudioFilePicker.swift` needed — SwiftUI `.fileImporter` handles the picker inline.  
No design-system files are touched.

---

## 1. `MixrTrack.swift`

Replaces `MockTrack` / `MockClip`. Keeps the same property shape so existing rendering views need only a type rename.

```swift
struct MixrTrack: Identifiable {
    let id: UUID
    var title: String
    var artist: String
    var duration: String        // "3:20" display string; "--:--" while loading
    var durationSeconds: Double?
    var bpm: Int                // default 120 until metadata is read
    var color: MixrWaveformColor
    var volume: Double          // moved out of TLTrackControlsColumn
    var url: URL?
    var clips: [MixrClip]
}

struct MixrClip: Identifiable {
    let id: UUID
    var start: CGFloat   // timeline units
    var length: CGFloat  // timeline units
}
```

---

## 2. `TrackLibrary.swift`

### File picker

SwiftUI's `.fileImporter` modifier (iOS 14+) is used directly on `TimelineScreen` — no `UIViewControllerRepresentable` wrapper needed:

```swift
.fileImporter(
    isPresented: $showFilePicker,
    allowedContentTypes: [.mp3, .wav, .mpeg4Audio, .aiff, .audio],
    allowsMultipleSelection: true
) { result in
    if case .success(let urls) = result {
        library.addTracks(from: urls)
    }
}
```

`.audio` covers `.caf` and generic audio UTTypes. `.mpeg4Audio` covers `.m4a` and `.aac`.

### Placeholder-first import

Tracks are appended immediately in selection order before any async work runs. Color is assigned at append-time from the current count — this is stable because no `Task` can interleave between synchronous loop iterations on `@MainActor`.

```swift
@MainActor
final class TrackLibrary: ObservableObject {
    @Published var tracks: [MixrTrack] = []
    private let colorCycle: [MixrWaveformColor] = [.pink, .purple, .red, .yellow, .blue]

    func addTracks(from urls: [URL]) {
        for url in urls {
            // 1. Assign color and create placeholder — synchronously, in order
            let color    = colorCycle[tracks.count % colorCycle.count]
            let trackID  = UUID()
            let title    = url.deletingPathExtension().lastPathComponent
            let placeholder = MixrTrack(
                id: trackID, title: title, artist: "Unknown Artist",
                duration: "--:--", durationSeconds: nil,
                bpm: 120, color: color, volume: 0.75, url: url,
                clips: [MixrClip(id: UUID(), start: 0, length: 48)]  // default ~2 min
            )
            tracks.append(placeholder)

            // 2. Async-load duration, then patch by ID — never reorders or re-colors
            Task {
                let asset = AVURLAsset(url: url)
                guard let cm = try? await asset.load(.duration) else { return }
                let seconds = CMTimeGetSeconds(cm)
                guard seconds.isFinite && seconds > 0 else { return }
                guard let idx = tracks.firstIndex(where: { $0.id == trackID }) else { return }
                tracks[idx].duration      = Self.formattedDuration(seconds)
                tracks[idx].durationSeconds = seconds
                tracks[idx].clips[0].length = Self.clipUnits(for: seconds)
            }
        }
    }

    func reorder(from source: IndexSet, to destination: Int) {
        withAnimation(.easeOut(duration: 0.22)) {
            tracks.move(fromOffsets: source, toOffset: destination)
        }
    }
    // helpers: clipUnits(for:), formattedDuration(_:)
}
```

Key guarantees:
- All placeholders appear immediately in file-picker selection order.
- Colors are assigned cyclically at append time — no async race.
- Duration patches find the track by `UUID`, so reordering between append and patch is safe.

---

## 3. `TimelineScreen.swift` — data flow refactor

**Root view** gains library state and picker binding:

```swift
struct TimelineScreen: View {
    @StateObject private var library = TrackLibrary()
    @State private var showFilePicker = false
    // drag-reorder state (see §6)
    @State private var draggingID: UUID? = nil
    @State private var dragTranslation: CGFloat = 0

    var body: some View { ... }
}
```

`.fileImporter` modifier is attached to the root `ZStack` or `VStack`.

All three subcolumns receive `tracks` / bindings from the library:

- Sidebar: `tracks: library.tracks`, `showFilePicker: $showFilePicker`, drag state
- Timeline center: `tracks: library.tracks`
- Controls: `tracks: $library.tracks`

`mockTracks`, `MockTrack`, `MockClip` are removed entirely.

Volume bound directly: `$library.tracks[index].volume`.

---

## 4. Layout refactor — linked vertical scrolling

The critical change is replacing the three independent scroll containers with **one shared vertical `ScrollView`** that contains all three columns side by side, with a separate inner horizontal `ScrollView` for the timeline canvas only.

```
Before:
  HStack {
    TLSongSidebar          ← own ScrollView(.vertical)
    TLTimelineArea         ← ScrollView([.horizontal, .vertical]) + controls outside it
  }

After:
  ZStack {
    ScrollView(.vertical) {       ← single vertical scroll
      HStack(alignment: .top) {
        sidebarRowsColumn         ← no scroll, just VStack
        ScrollView(.horizontal) { ← horizontal only
          grid + ruler + lanes
        }
        controlsRowsColumn        ← no scroll, just VStack
      }
    }
    importButton                  ← overlay, always visible bottom-left
  }
```

Detailed structure:

```swift
// Inside the timeline height GeometryReader:
ZStack(alignment: .topLeading) {
    // Column background fills (sidebar, controls stay distinct from timeline)
    columnBackgrounds

    ScrollView(.vertical, showsIndicators: false) {
        HStack(alignment: .top, spacing: 0) {

            // LEFT — song rows
            VStack(spacing: 0) {
                Color.clear.frame(height: TLK.rulerHeight)   // aligns with ruler
                ForEach(tracks) { TLSongRow(track: $0) }
                Color.clear.frame(height: importButtonHeight) // avoids overlap
            }
            .frame(width: TLK.sidebarWidth)

            // CENTER — ruler + lanes, horizontal scroll only
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    TLGridCanvas(width: contentW, height: contentH)
                    VStack(spacing: 0) {
                        TLRuler(width: contentW)
                        ForEach(tracks) { TLTrackLane(track: $0, timelineWidth: contentW) }
                    }
                    TLPlayhead(timelineWidth: contentW, totalHeight: contentH)
                }
                .frame(width: contentW, height: contentH)
            }

            // RIGHT — controls rows
            VStack(spacing: 0) {
                Color.clear.frame(height: TLK.rulerHeight)
                ForEach(tracks) { track in
                    TLTrackControlRow(
                        track: track,
                        volume: binding for track.volume in library.tracks
                    )
                    .frame(height: TLK.trackRowHeight)
                }
                Spacer()
            }
            .frame(width: TLK.smColumnWidth)
        }
        .frame(minHeight: timelineHeight)  // fills full viewport when few tracks
    }

    // Import Songs — always visible, bottom-left of sidebar
    .overlay(alignment: .bottomLeading) {
        importButtonView
            .frame(width: TLK.sidebarWidth)
    }
}
```

- `contentH = TLK.rulerHeight + CGFloat(tracks.count) * TLK.trackRowHeight` — grows as tracks are added.
- `contentW = max(viewportW, TLK.totalUnits * TLK.timelineUnitWidth)` — unchanged from current logic.
- Sidebar rows and controls rows are plain `VStack`s inside the unified `ScrollView(.vertical)` — no independent scroll.

---

## 5. Drag-to-reorder

Dragging a track by its gripper handle reorders `library.tracks`. Because all three columns (`ForEach(tracks)` in sidebar, timeline, controls) iterate the same array, all three animate their rows simultaneously — there is no separate ordering state per column.

### Shared drag state (in `TimelineScreen`)

```swift
@State private var draggingID: UUID?       = nil
@State private var dragTranslation: CGFloat = 0
```

Both values are passed into the unified layout view and down into each column. A computed helper drives all per-row visual decisions:

```swift
// Returns the live Y offset to apply to any row while a drag is in progress.
func rowOffset(trackID: UUID, in tracks: [MixrTrack]) -> CGFloat {
    guard let dragging = draggingID,
          let from = tracks.firstIndex(where: { $0.id == dragging })
    else { return 0 }

    let steps = Int((dragTranslation / TLK.trackRowHeight).rounded())
    let insertAt = (from + steps).clamped(to: 0...(tracks.count - 1))

    if trackID == dragging {
        // The grabbed row follows the finger
        return dragTranslation
    }
    guard let i = tracks.firstIndex(where: { $0.id == trackID }) else { return 0 }
    // Other rows shift to open a gap at the live insertion point
    if from < insertAt, i > from, i <= insertAt { return -TLK.trackRowHeight }
    if from > insertAt, i >= insertAt, i < from  { return  TLK.trackRowHeight }
    return 0
}
```

This function is called in all three columns' `ForEach` — sidebar, timeline lanes, and controls — so every column shifts its rows identically in real time.

### Gesture on gripper

`TLSongRowGripper` gains a `DragGesture(minimumDistance: 8)`. The gesture is applied in the sidebar column where the gripper lives; drag state updates are `@State` in the parent, so all three columns react:

```swift
.gesture(
    DragGesture(minimumDistance: 8)
        .onChanged { value in
            if draggingID == nil { draggingID = track.id }
            dragTranslation = value.translation.height
        }
        .onEnded { value in
            if let id = draggingID,
               let from = library.tracks.firstIndex(where: { $0.id == id }) {
                let steps    = Int((value.translation.height / TLK.trackRowHeight).rounded())
                let insertAt = (from + steps).clamped(to: 0...(library.tracks.count - 1))
                if insertAt != from {
                    library.reorder(
                        from: IndexSet([from]),
                        to: insertAt > from ? insertAt + 1 : insertAt
                    )
                }
            }
            withAnimation(.easeOut(duration: 0.18)) {
                draggingID       = nil
                dragTranslation  = 0
            }
        }
)
```

### Per-row visual modifiers (applied in all three columns)

```swift
let isDragging = track.id == draggingID
rowView
    .offset(y: rowOffset(trackID: track.id, in: library.tracks))
    .scaleEffect(isDragging ? CGSize(width: 1.0, height: 1.02) : .init(width: 1, height: 1),
                 anchor: .center)
    .shadow(color: isDragging ? .black.opacity(0.32) : .clear, radius: 8, x: 0, y: 4)
    .opacity(isDragging ? 0.96 : 1)
    .zIndex(isDragging ? 1 : 0)
    .animation(.easeOut(duration: 0.14), value: dragTranslation)
```

All three columns apply the same modifiers to their per-track views, driven by the same `draggingID` / `dragTranslation` state. The result: the sidebar row, waveform lane, and controls row all float upward together, and surrounding rows in all three columns open the same gap simultaneously.

### Live insertion indicator

A thin accent line (2pt, `MixrColors.primaryPurple`) is drawn at the insertion position inside the sidebar column's VStack. It is positioned using the computed `insertAt` index:

```swift
// Drawn after the row at insertAt - 1, before the row at insertAt
if dragTranslation != 0, let insertAt = liveInsertionIndex {
    MixrColors.primaryPurple
        .frame(height: 2)
        .clipShape(Capsule())
        .padding(.horizontal, 8)
}
```

### On drop

`library.reorder(from:to:)` calls `tracks.move(fromOffsets:toOffset:)` inside `withAnimation(.easeOut(duration: 0.22))`. SwiftUI's identity-based diffing on `ForEach` moves rows in all three VStacks simultaneously without any additional coordination.

All associated data — `volume`, `clips`, `color`, `url`, `durationSeconds` — travels with the `MixrTrack` value because the struct is moved as a unit.

```
During drag (live):        On drop:
 Sidebar | Timeline | SM   Sidebar | Timeline | SM
 [Track C↑ floating]       [Track C]  [lane C]  [ctrl C]
 [       insertion line ]  [Track A]  [lane A]  [ctrl A]
 [Track A ↓ shifted   ]   [Track B]  [lane B]  [ctrl B]
 [Track B ↓ shifted   ]
```

---

## 6. Empty state

When `library.tracks.isEmpty`:
- Sidebar column shows only the ruler-height spacer (no rows).
- Timeline shows grid + ruler with no lanes.
- Controls column shows only the ruler spacer.
- Import Songs button is always visible via overlay.
- No placeholder rows or special empty-state view — the grid itself is sufficient.

---

## Scroll & interaction summary

| Action | Sidebar | Timeline | Controls |
|---|---|---|---|
| Swipe up/down | moves | moves | moves |
| Swipe left/right | fixed | pans | fixed |
| Ruler | aligns via spacer | scrolls horizontally | aligns via spacer |
| Drag gripper | reorders | reorders (same data) | reorders (same data) |

---

## Files changed

- **New**: `Mixr/Models/MixrTrack.swift`
- **New**: `Mixr/Models/TrackLibrary.swift`
- **Modified**: `Mixr/TimelineScreen.swift` — remove mock data, refactor layout, wire `.fileImporter`, drag reorder

## Files not touched

All `DesignSystem/` files, `ContentView.swift`, `MixrSongColorChip.swift`
