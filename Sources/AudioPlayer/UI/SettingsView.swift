import SwiftUI

struct SettingsView: View {

    private enum SettingsSection: Hashable {
        case nowPlaying
        case library
        case others
    }

    @Environment(AppController.self) private var appController

    @State private var selectedSection: SettingsSection
    @State private var hoveredSection: SettingsSection?
@State private var pendingSection: SettingsSection?
@State private var showingUnsavedChangesAlert = false

    @MainActor
    init(appController: AppController) {
        switch appController.persistence.appState.settingsSection {
        case "library":
            _selectedSection = State(initialValue: .library)
        case "others":
            _selectedSection = State(initialValue: .others)
        case "nowPlaying":
            _selectedSection = State(initialValue: .nowPlaying)
        default:
            _selectedSection = State(initialValue: .nowPlaying)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sectionButton(
                    title: "Now Playing",
                    section: .nowPlaying
                )

                sectionButton(
                    title: "Library",
                    section: .library
                )

                sectionButton(
                    title: "Others",
                    section: .others
                )
            }
            .padding()

            Divider()

            Group {
                switch selectedSection {
                case .nowPlaying:
                    SettingsNowPlayingView()

                case .library:
                    SettingsLibraryView()

                case .others:
                    SettingsOthersView()
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
        .navigationTitle("Settings")
        .onChange(of: selectedSection) { _, newSection in
            persistSection(newSection)
        }
        .alert(
            "Unsaved Changes",
            isPresented: $showingUnsavedChangesAlert
        ) {
            Button("Cancel", role: .cancel) {
                pendingSection = nil
            }

            Button("Leave", role: .destructive) {
                let section = pendingSection
                pendingSection = nil

                appController.setSettingsHasUnsavedChanges(false)

                if let section {
                    selectedSection = section
                }
            }
        } message: {
            Text("You have unsaved changes. Do you want to leave without saving?")
        }
        .onDisappear {
            appController.setSettingsHasUnsavedChanges(false)
        }
    }

    private func sectionButton(
        title: String,
        section: SettingsSection
    ) -> some View {
        Button {
            requestSectionChange(to: section)
        } label: {
            Text(title)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            Color.primary.opacity(
                                selectedSection == section
                                    ? 0.26
                                    : hoveredSection == section
                                        ? 0.14
                                        : 0.07
                            )
                        )
                )
                .contentShape(
                    RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredSection = hovering ? section : nil
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
    }

    private func requestSectionChange(
        to section: SettingsSection
    ) {
        guard section != selectedSection else {
            return
        }

        if appController.hasUnsavedSettingsChanges {
            pendingSection = section
            showingUnsavedChangesAlert = true
        } else {
            selectedSection = section
        }
    }

    private func persistSection(
        _ section: SettingsSection
    ) {
        let value: String

        switch section {
        case .nowPlaying:
            value = "nowPlaying"

        case .library:
            value = "library"

        case .others:
            value = "others"
        }

        var appState = appController.persistence.appState
        appState.settingsSection = value
        appController.persistence.reportApp(appState)
    }
}
