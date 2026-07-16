import SwiftUI

// MARK: - Auto Remix Summary Sheet

/// Shown after Entire Project Auto succeeds. Scannable decisions + warnings;
/// no internal scores or debug seed.
struct AutoRemixSummarySheet: View {
    let summary: AutoRemixSummary
    var onDone: () -> Void = {}
    var onUndoAuto: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: MixrSpacing.lg) {
            header

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: MixrSpacing.md) {
                    metaRow
                    section(title: "Sequence", body: summary.sequence)

                    if !summary.anchorNames.isEmpty {
                        section(
                            title: summary.anchorNames.count == 1 ? "Anchor" : "Anchors",
                            body: summary.anchorNames.joined(separator: " · ")
                        )
                    }

                    if !summary.transitionRecipes.isEmpty {
                        chipSection(title: "Transitions", items: summary.transitionRecipes)
                    }
                    if !summary.effectsUsed.isEmpty {
                        chipSection(title: "Effects", items: summary.effectsUsed)
                    }
                    if !summary.sfxUsed.isEmpty {
                        chipSection(title: "SFX", items: summary.sfxUsed)
                    }

                    if !summary.decisions.isEmpty {
                        bulletSection(title: "Decisions", items: Array(summary.decisions.prefix(8)))
                    }
                    if !summary.warnings.isEmpty {
                        bulletSection(title: "Warnings", items: summary.warnings, warning: true)
                    }
                }
                .padding(.bottom, MixrSpacing.sm)
            }

            actions
        }
        .padding(MixrSpacing.xl)
        .frame(width: 480, height: 360)
        .background {
            GlassBackground(level: .strong, cornerRadius: MixrRadius.glass)
        }
        .clipShape(RoundedRectangle(cornerRadius: MixrRadius.glass, style: .continuous))
        .mixrShadow(.glassStrong)
        .mixrGlow(.glassAmbientStrong)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: MixrSpacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(MixrColors.secondaryPurple)
                .shadow(color: MixrColors.primaryPurple.opacity(0.7), radius: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text("Auto \(summary.modeTitle)")
                    .mixrFont(.sectionTitle)
                    .foregroundStyle(MixrColors.textPrimary)
                Text("Arrangement ready")
                    .mixrFont(.metadata)
                    .foregroundStyle(MixrColors.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var metaRow: some View {
        HStack(spacing: MixrSpacing.md) {
            metaChip(label: "BPM", value: "\(summary.targetBPM)")
            metaChip(label: "Handoffs", value: "\(summary.handoffCount)")
            Spacer(minLength: 0)
        }
    }

    private func metaChip(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .mixrFont(.caption)
                .foregroundStyle(MixrColors.textSecondary)
            Text(value)
                .mixrFont(.songTitle)
                .foregroundStyle(MixrColors.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: MixrRadius.button, style: .continuous)
                .fill(Color.white.opacity(0.06))
        }
        .overlay {
            RoundedRectangle(cornerRadius: MixrRadius.button, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6)
        }
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .mixrFont(.caption)
                .foregroundStyle(MixrColors.textSecondary)
            Text(body)
                .mixrFont(.body)
                .foregroundStyle(MixrColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chipSection(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .mixrFont(.caption)
                .foregroundStyle(MixrColors.textSecondary)
            FlowWrap(items: items)
        }
    }

    private func bulletSection(title: String, items: [String], warning: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .mixrFont(.caption)
                .foregroundStyle(warning ? MixrColors.waveformYellow : MixrColors.textSecondary)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Text("·")
                        .mixrFont(.body)
                        .foregroundStyle(warning ? MixrColors.waveformYellow.opacity(0.85) : MixrColors.textSecondary)
                    Text(item)
                        .mixrFont(.body)
                        .foregroundStyle(MixrColors.textPrimary.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: MixrSpacing.md) {
            Button("Undo Auto") {
                onUndoAuto()
            }
            .buttonStyle(MixrSecondaryGlassButtonStyle())

            Spacer(minLength: 0)

            Button("Done") {
                onDone()
            }
            .buttonStyle(MixrPrimaryButtonStyle())
        }
    }
}

// MARK: - Simple wrap for chips

private struct FlowWrap: View {
    let items: [String]

    var body: some View {
        // Landscape summary is wide enough for a single wrapping HStack via LazyVGrid.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 88), spacing: 6)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .mixrFont(.caption)
                    .foregroundStyle(MixrColors.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.07))
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.55)
                    }
            }
        }
    }
}

// MARK: - Auto Error Sheet

struct AutoRemixErrorSheet: View {
    let message: String
    var onDismiss: () -> Void = {}

    var body: some View {
        VStack(spacing: MixrSpacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(MixrColors.waveformYellow)

            Text("Auto couldn’t finish")
                .mixrFont(.sectionTitle)
                .foregroundStyle(MixrColors.textPrimary)

            Text(message)
                .mixrFont(.body)
                .foregroundStyle(MixrColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("OK") { onDismiss() }
                .buttonStyle(MixrPrimaryButtonStyle())
        }
        .padding(MixrSpacing.xl)
        .frame(width: 360)
        .background {
            GlassBackground(level: .strong, cornerRadius: MixrRadius.glass)
        }
        .clipShape(RoundedRectangle(cornerRadius: MixrRadius.glass, style: .continuous))
        .mixrShadow(.glassStrong)
    }
}
