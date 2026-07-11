import SwiftUI

/// Side-by-side mockups of undo / redo toolbar icon options (A–G).
struct UndoRedoIconOptionsGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Undo / Redo Icon Options")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(MixrColors.textPrimary)
                    Text("Alternatives with a wider spread than the bottom wrap-around U-turn.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(MixrColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                option(label: "★ Shipped — soft U-turn, stub tail, rounded head",
                       undoCustom: { MixrHistoryArrow(direction: .undo, size: 17) },
                       redoCustom: { MixrHistoryArrow(direction: .redo, size: 17) })
                option(label: "A · SF Symbol — bottom U-turn (previous)",
                       undoIcon: "arrow.uturn.backward",
                       redoIcon: "arrow.uturn.forward")
                option(label: "B · Open circle — counter / clockwise",
                       undoIcon: "arrow.counterclockwise",
                       redoIcon: "arrow.clockwise")
                option(label: "C · Media — go backward / forward",
                       undoIcon: "gobackward",
                       redoIcon: "goforward")
                option(label: "D · Top hook — turn up left / right",
                       undoIcon: "arrow.turn.up.left",
                       redoIcon: "arrow.turn.up.right")
                option(label: "E · Arrowshape — turn up left / right",
                       undoIcon: "arrowshape.turn.up.left",
                       redoIcon: "arrowshape.turn.up.right")
                option(label: "F · Triangle head — counter / clockwise",
                       undoIcon: "arrow.trianglehead.counterclockwise",
                       redoIcon: "arrow.trianglehead.clockwise")
                option(label: "G · Custom — wide top arc (mock)",
                       undoCustom: { TLWideHistoryUndoIcon() },
                       redoCustom: { TLWideHistoryRedoIcon() })
            }
            .padding(20)
        }
        .background {
            ZStack {
                MixrGradients.backgroundLinear
                MixrGradients.backgroundRadial
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }

    private func option<Undo: View, Redo: View>(
        label: String,
        undoIcon: String? = nil,
        redoIcon: String? = nil,
        @ViewBuilder undoCustom: @escaping () -> Undo = { EmptyView() },
        @ViewBuilder redoCustom: @escaping () -> Redo = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MixrColors.textSecondary)
            ToolbarHistoryContextRow(
                undoIcon: undoIcon,
                redoIcon: redoIcon,
                undoCustom: undoCustom,
                redoCustom: redoCustom
            )
        }
    }
}

// MARK: - Toolbar context row

struct ToolbarHistoryContextRow<Undo: View, Redo: View>: View {
    var undoIcon: String? = nil
    var redoIcon: String? = nil
    var undoCustom: () -> Undo
    var redoCustom: () -> Redo

    init(
        undoIcon: String? = nil,
        redoIcon: String? = nil,
        @ViewBuilder undoCustom: @escaping () -> Undo = { EmptyView() },
        @ViewBuilder redoCustom: @escaping () -> Redo = { EmptyView() }
    ) {
        self.undoIcon = undoIcon
        self.redoIcon = redoIcon
        self.undoCustom = undoCustom
        self.redoCustom = redoCustom
    }

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 7) {
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(MixrColors.primaryPurple)
                Text("Mixr")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(MixrColors.textPrimary)
            }

            HStack(spacing: 4) {
                Text("My Remix")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MixrColors.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MixrColors.textSecondary)
            }

            HStack(spacing: 6) {
                if let undoIcon {
                    TLToolbarHistoryButton(icon: undoIcon, isEnabled: true) {}
                } else {
                    TLToolbarHistoryCustomButton(isEnabled: true) { undoCustom() }
                }
                if let redoIcon {
                    TLToolbarHistoryButton(icon: redoIcon, isEnabled: true) {}
                } else {
                    TLToolbarHistoryCustomButton(isEnabled: true) { redoCustom() }
                }
            }

            HStack(spacing: 6) {
                if let undoIcon {
                    TLToolbarHistoryButton(icon: undoIcon, isEnabled: false) {}
                } else {
                    TLToolbarHistoryCustomButton(isEnabled: false) { undoCustom() }
                }
                if let redoIcon {
                    TLToolbarHistoryButton(icon: redoIcon, isEnabled: false) {}
                } else {
                    TLToolbarHistoryCustomButton(isEnabled: false) { redoCustom() }
                }
            }
            .opacity(0.85)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(MixrColors.backgroundSecondary.opacity(0.85))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(MixrColors.divider.opacity(0.45), lineWidth: 0.5)
                }
        }
    }
}

#Preview("Undo / Redo Icon Options") {
    UndoRedoIconOptionsGallery()
}
