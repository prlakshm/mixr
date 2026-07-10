import SwiftUI

// MARK: - Project Dropdown Menu

/// Dark glass dropdown for the "My Remix" project title — switch, create,
/// and rename projects. Presented as a floating overlay under the toolbar.
struct ProjectDropdownMenu: View {
    let projects: [ProjectSummary]
    let currentProjectID: UUID?
    let currentName: String
    var onSelectProject: (UUID) -> Void = { _ in }
    var onCreateProject: () -> Void = {}
    var onRename: (String) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    @State private var isRenaming = false
    @State private var renameText = ""
    @FocusState private var renameFieldFocused: Bool

    private let menuWidth: CGFloat = 232
    private let rowHeight: CGFloat = 38

    var body: some View {
        VStack(spacing: 0) {
            if isRenaming {
                renameRow
                menuDivider
            }

            ForEach(projects) { project in
                projectRow(project)
                if project.id != projects.last?.id {
                    menuDivider.padding(.leading, 40)
                }
            }

            if !projects.isEmpty {
                menuDivider
            }

            actionRow(icon: "pencil", title: "Rename Project") {
                renameText = currentName
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    isRenaming = true
                }
                renameFieldFocused = true
            }

            menuDivider.padding(.leading, 40)

            actionRow(icon: "plus", title: "New Project") {
                onCreateProject()
                onDismiss()
            }
        }
        .padding(.vertical, 4)
        .frame(width: menuWidth)
        .background { menuGlass }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 20, x: 0, y: 8)
        .shadow(color: .black.opacity(0.20), radius: 4, x: 0, y: 2)
    }

    // MARK: Rows

    private func projectRow(_ project: ProjectSummary) -> some View {
        let isCurrent = project.id == currentProjectID
        return Button {
            if !isCurrent { onSelectProject(project.id) }
            onDismiss()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isCurrent ? MixrColors.secondaryPurple : MixrColors.textSecondary)
                    .frame(width: 22)

                Text(isCurrent ? currentName : project.name)
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? MixrColors.secondaryPurple : MixrColors.textPrimary)
                    .lineLimit(1)

                Spacer()

                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MixrColors.secondaryPurple)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(TLClipActionPressStyle())
    }

    private func actionRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MixrColors.textSecondary)
                    .frame(width: 22)

                Text(title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(MixrColors.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(TLClipActionPressStyle())
    }

    private var renameRow: some View {
        HStack(spacing: 8) {
            TextField("Project name", text: $renameText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MixrColors.textPrimary)
                .textFieldStyle(.plain)
                .focused($renameFieldFocused)
                .submitLabel(.done)
                .onSubmit(commitRename)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(MixrColors.primaryPurple.opacity(0.45), lineWidth: 0.6)
                        }
                }

            Button(action: commitRename) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MixrColors.textPrimary)
                    .frame(width: 24, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: rowHeight + 4)
    }

    private func commitRename() {
        onRename(renameText)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            isRenaming = false
        }
    }

    // MARK: Chrome

    private var menuDivider: some View {
        Rectangle()
            .fill(MixrColors.divider.opacity(0.5))
            .frame(height: 0.25)
    }

    private var menuGlass: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return shape
            .fill(Color(hex: "050810").opacity(0.90))
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .opacity(0.10)
                    .environment(\.colorScheme, .dark)
            }
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.045), Color.clear],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.35)
                    )
                )
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
            }
    }
}

#Preview("Project Dropdown") {
    ZStack {
        MixrGradients.backgroundLinear.ignoresSafeArea()
        ProjectDropdownMenu(
            projects: [
                ProjectSummary(id: UUID(), name: "My Remix", modifiedAt: Date()),
                ProjectSummary(id: UUID(), name: "Festival Set", modifiedAt: Date()),
            ],
            currentProjectID: nil,
            currentName: "My Remix"
        )
    }
    .frame(width: 400, height: 400)
    .preferredColorScheme(.dark)
}
