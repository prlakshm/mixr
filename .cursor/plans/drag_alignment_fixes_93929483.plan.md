---
name: Drag Alignment Fixes
overview: Fix 4 bugs in `floatingDraggedClip` and the vertical ScrollView that cause the floating clip and insertion indicator to be misaligned, the clip to jump to cursor-center on grab, and the timeline to scroll vertically during drag.
todos:
  - id: fix-floatingx
    content: "Fix floating clip X: use cursorAreaX - grabScreenPx instead of cursorAreaX - clipW/2"
    status: pending
  - id: fix-floatingy
    content: "Fix floating clip Y: use cursorAreaY - grabScreenPy - clipDragLiftY instead of centering"
    status: pending
  - id: fix-armed-offset
    content: "Fix armed floating clip: compute clip's actual timeline screen position instead of using clipDragArmedAreaX/Y"
    status: pending
  - id: disable-vscroll
    content: Disable vertical ScrollView during drag with .scrollDisabled(isDraggingClip || clipDragArmed != nil)
    status: pending
isProject: false
---

# Drag Alignment Fixes

Four bugs in [`Mixr/TimelineScreen.swift`](Mixr/TimelineScreen.swift). All changes are in `floatingDraggedClip` (lines 884–915) and the outer `ScrollView(.vertical)` (line 984).

---

## Bug 1 — Floating clip X is centered on cursor instead of respecting grab offset

**Location**: `floatingDraggedClip`, line 896

**Current** (wrong):
```swift
x: drag.cursorAreaX - clipW / 2,
```

**Fix**:
```swift
x: drag.cursorAreaX - drag.grabScreenPx,
```

**Why**: The clip should appear at the position where the user grabbed it, not floating centered on the cursor. `grabScreenPx` is the distance from the clip's leading edge to the finger at grab time. After this fix, the floating clip's leading edge exactly matches the insertion indicator's `screenX` in non-snap cases (mathematically provable — they collapse to the same expression).

---

## Bug 2 — Floating clip Y is centered instead of respecting grab offset + lift

**Location**: `floatingDraggedClip`, line 897

**Current** (wrong):
```swift
y: drag.cursorAreaY - TLK.waveformHeight / 2
```

**Fix**:
```swift
y: drag.cursorAreaY - drag.grabScreenPy - TLK.clipDragLiftY
```

**Why**: The clip should follow the grab point vertically, then lift up by `clipDragLiftY` (6 pt) for the "lifted" feel. `grabScreenPy` is stored in `ClipDragState` at drag start (line 712).

---

## Bug 3 — Armed floating clip uses cursor position instead of clip's timeline position

**Location**: `floatingDraggedClip`, lines 909–912 (the `else if let armedID` branch)

**Current** (wrong):
```swift
.offset(
    x: clipDragArmedAreaX - clipW / 2,
    y: clipDragArmedAreaY - TLK.waveformHeight / 2
)
```

**Fix** — compute the clip's actual screen position:
```swift
let contentX = (f.clip.start / contentUnits) * contentW
let screenX = TLK.sidebarWidth + contentX - hScrollOffset
let clipTopY = TLK.rulerHeight
    + CGFloat(f.trackIdx) * TLK.trackRowHeight
    + (TLK.trackRowHeight - TLK.waveformHeight) / 2
    - vScrollOffset
// then:
.offset(x: screenX, y: clipTopY - TLK.clipDragLiftY)
```

**Why**: The armed overlay should appear lifted exactly over the clip's current timeline position (the "hold then lift" moment), not over the cursor. `clipDragArmedAreaX/Y` is the tap position, not the clip position.

---

## Bug 4 — Vertical ScrollView scrolls during drag

**Location**: outer `ScrollView(.vertical, showsIndicators: false)` at line 984

**Fix**: add `.scrollDisabled(isDraggingClip || clipDragArmed != nil)` immediately after the ScrollView's closing brace.

**Why**: The user's finger movement tracking drives the floating clip; any accidental vertical scroll during drag shifts `vScrollOffset`, breaking the insertion indicator's Y position and the scrim alignment. Both armed and active-drag states should lock vertical scroll.

---

## How the indicator and clip align after these fixes

```
floatingX (clip leading edge) = cursorAreaX − grabScreenPx
indicator screenX              = sidebarWidth + proposedLeadingEdgePx − scrollX
                               = sidebarWidth + (cursorAreaX − sidebarWidth + scrollX − grabScreenPx) − scrollX
                               = cursorAreaX − grabScreenPx   ✓
```

They are mathematically identical in the non-snap case. In snap zones the indicator glides to the snapped edge while the clip floats freely — this is the standard professional editor behavior (Logic Pro / Final Cut Pro).
