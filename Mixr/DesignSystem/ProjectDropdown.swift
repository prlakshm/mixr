import SwiftUI

// MARK: - Project Dropdown Menu

/// Apple-style dark pull-down menu for the project title — switch projects,
/// delete the current one, or create a new one. Presented as a floating
/// overlay under the toolbar; rename lives on the nav title (long-press).
struct ProjectDropdownMenu: View {
    let projects: [ProjectSummary]
    let currentProjectID: UUID?
    let currentName: String
    var onSelectProject: (UUID) -> Void = { _ in }
    var onCreateProject: () -> Void = {}
    var onDeleteProject: () -> Void = {}
    var onDismiss: () -> Void = {}

    /// Public so the presenter can align menu label leading with the nav title.
    /// Scaled from the prior 17pt system (factor 15/17).
    static let horizontalPadding: CGFloat = 14
    static let rowHeight: CGFloat = 39
    static let maxVisibleProjects: Int = 4
    static let cornerRadius: CGFloat = 12
    static let menuWidth: CGFloat = 230
    static let dividerHeight: CGFloat = 0.5
    static let labelFontSize: CGFloat = 15
    static let iconFontSize: CGFloat = 13
    static let iconSlotWidth: CGFloat = 16

    private var listHeight: CGFloat {
        let count = min(max(projects.count, 1), Self.maxVisibleProjects)
        let dividers = max(count - 1, 0)
        return CGFloat(count) * Self.rowHeight + CGFloat(dividers) * Self.dividerHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            projectList

            if !projects.isEmpty {
                sectionDivider
            }

            actionRow(
                title: "Delete Project",
                icon: "trash",
                isDestructive: true
            ) {
                onDeleteProject()
            }

            rowDivider

            actionRow(
                title: "New Project",
                icon: "plus",
                isDestructive: false
            ) {
                onCreateProject()
                onDismiss()
            }
        }
        .padding(.vertical, 3.5)
        .frame(width: Self.menuWidth)
        .background { menuGlass }
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .partyModeBorder(
            shape: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous),
            role: .menu,
            lighting: .violetTrailing,
            glintOffset: .near
        )
        .shadow(color: .black.opacity(0.55), radius: 18, x: 0, y: 7)
        .shadow(color: .black.opacity(0.20), radius: 3.5, x: 0, y: 1.75)
    }

    // MARK: - Project list

    private var projectList: some View {
        Group {
            if projects.isEmpty {
                Text("No Projects")
                    .font(.system(size: Self.labelFontSize, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Self.horizontalPadding)
                    .frame(height: Self.rowHeight)
            } else if projects.count <= Self.maxVisibleProjects {
                VStack(spacing: 0) {
                    ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                        projectRow(project)
                        if index < projects.count - 1 {
                            rowDivider
                        }
                    }
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                            projectRow(project)
                            if index < projects.count - 1 {
                                rowDivider
                            }
                        }
                    }
                }
                .frame(height: listHeight)
            }
        }
    }

    private func projectRow(_ project: ProjectSummary) -> some View {
        let isCurrent = project.id == currentProjectID
        return Button {
            if !isCurrent { onSelectProject(project.id) }
            onDismiss()
        } label: {
            HStack(spacing: 9) {
                Text(isCurrent ? currentName : project.name)
                    .font(.system(size: Self.labelFontSize, weight: .regular))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "checkmark")
                    .font(.system(size: Self.iconFontSize, weight: .semibold))
                    .opacity(isCurrent ? 1 : 0)
                    .frame(width: Self.iconSlotWidth, alignment: .center)
            }
            .padding(.horizontal, Self.horizontalPadding)
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(ProjectMenuPressStyle(isDestructive: false))
    }

    private func actionRow(
        title: String,
        icon: String,
        isDestructive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(title)
                    .font(.system(size: Self.labelFontSize, weight: .regular))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: icon)
                    .font(.system(size: Self.iconFontSize, weight: .regular))
                    .frame(width: Self.iconSlotWidth, alignment: .center)
            }
            .padding(.horizontal, Self.horizontalPadding)
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(ProjectMenuPressStyle(isDestructive: isDestructive))
    }

    // MARK: - Chrome

    /// Light hairline between project rows and between Delete / New.
    private var rowDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: Self.dividerHeight)
    }

    /// Stronger separator between the scrollable project list and pinned footer.
    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.18))
            .frame(height: Self.dividerHeight)
    }

    private var menuGlass: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
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

// MARK: - Press Style

/// Project menu press — same white/red 0.88 color step as alert Delete / OK.
private struct ProjectMenuPressStyle: ButtonStyle {
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let resting = isDestructive
            ? MixrAlertPressColors.redResting
            : MixrAlertPressColors.whiteResting
        let pressed = isDestructive
            ? MixrAlertPressColors.redPressed
            : MixrAlertPressColors.whitePressed

        configuration.label
            .foregroundStyle(configuration.isPressed ? pressed : resting)
            .offset(y: configuration.isPressed ? 1.1 : 0)
            .animation(
                .spring(response: 0.17, dampingFraction: 0.82),
                value: configuration.isPressed
            )
    }
}

#Preview("Project Dropdown") {
    ZStack {
        MixrGradients.backgroundLinear.ignoresSafeArea()
        ProjectDropdownMenu(
            projects: [
                ProjectSummary(id: UUID(), name: "My Remix", modifiedAt: Date()),
                ProjectSummary(id: UUID(), name: "Festival Set", modifiedAt: Date()),
                ProjectSummary(id: UUID(), name: "Sunset Mix", modifiedAt: Date()),
                ProjectSummary(id: UUID(), name: "Club Night", modifiedAt: Date()),
                ProjectSummary(id: UUID(), name: "Demo Reel", modifiedAt: Date()),
            ],
            currentProjectID: nil,
            currentName: "My Remix"
        )
    }
    .frame(width: 400, height: 400)
    .preferredColorScheme(.dark)
}

// MARK: - Delete Project Confirm

/// Same chrome as `AutoScopeDialog` — Cancel (left, gray) / Delete (right, red).
struct DeleteProjectConfirmDialog: View {
    var projectName: String
    var onCancel: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            Text("Delete “\(projectName)”?")
                .font(.system(size: MixrAlertChrome.titleFontSize, weight: .semibold))
                .foregroundStyle(MixrColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, MixrAlertChrome.horizontalPadding)
                .frame(maxWidth: .infinity)
                .frame(height: MixrAlertChrome.titleHeight)
                .padding(.bottom, MixrAlertChrome.titleBottomExtraPadding)

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5)

            HStack(spacing: 0) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(MixrAlertActionPressStyle(kind: .cancel))

                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 0.5)

                Button("Delete", action: onDelete)
                    .buttonStyle(MixrAlertActionPressStyle(kind: .destructive))
            }
            .frame(height: MixrAlertChrome.actionHeight)
        }
        .frame(width: MixrAlertChrome.alertWidth)
        .fixedSize(horizontal: true, vertical: true)
        .background { MixrAlertChrome.background() }
        .clipShape(RoundedRectangle(cornerRadius: MixrAlertChrome.cornerRadius, style: .continuous))
        .partyModeBorder(
            shape: RoundedRectangle(
                cornerRadius: MixrAlertChrome.cornerRadius,
                style: .continuous
            ),
            role: .dialog,
            lighting: .clockwise,
            glintOffset: .near
        )
        .shadow(color: .black.opacity(0.35), radius: 22, x: 0, y: 9)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Delete \(projectName)?")
    }
}

#Preview("Delete Confirm") {
    ZStack {
        MixrGradients.backgroundLinear.ignoresSafeArea()
        DeleteProjectConfirmDialog(projectName: "My Remix 4")
    }
    .frame(width: 500, height: 320)
    .preferredColorScheme(.dark)
}
