import SwiftUI
import AppKit

struct MainView: View {

    private enum SidebarSection: Hashable {
        case nowPlaying
        case library
        case settings
    }

    @Environment(AppController.self) private var appController
    @State private var sidebarSelection: SidebarSection?
    @State private var pendingSidebarSelection: SidebarSection?
    @State private var showingUnsavedChangesAlert = false
    @State private var handledExternalOpenGeneration = 0

    @MainActor
    init(appController: AppController) {
        switch appController.persistence.appState.sidebarSection {
        case "library":
            _sidebarSelection = State(initialValue: .library)
        case "settings":
            _sidebarSelection = State(initialValue: .settings)
        case "nowPlaying":
            _sidebarSelection = State(initialValue: .nowPlaying)
        default:
            _sidebarSelection = State(initialValue: .nowPlaying)
        }
    }

    private func persistSidebarSelection(
        _ selection: SidebarSection?
    ) {
        let section: String?

        switch selection {
        case .nowPlaying:
            section = "nowPlaying"
        case .library:
            section = "library"
        case .settings:
            section = "settings"
        case nil:
            section = nil
        }

        var appState = appController.persistence.appState
        appState.sidebarSection = section
        appController.persistence.reportApp(appState)
    }

    var body: some View {
        Group {
            if appController.isReady {
                NavigationSplitView {
                    List(selection: $sidebarSelection) {
                        Label("Now Playing", systemImage: "play.circle")
                            .tag(SidebarSection.nowPlaying)

                        Label("Library", systemImage: "music.note.list")
                            .tag(SidebarSection.library)

                        Label("Settings", systemImage: "gearshape")
                            .tag(SidebarSection.settings)
                    }
                    .safeAreaInset(edge: .bottom) {
                        Button {
                            NSApplication.shared.terminate(nil)
                        } label: {
                            HStack(spacing: 6) {
                                Label(
                                    "Quit",
                                    systemImage: "power"
                                )

                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity)
                            .contentShape(
                                RoundedRectangle(
                                    cornerRadius: 6
                                )
                            )
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(
                                cornerRadius: 6
                            )
                            .fill(Color.red)
                        )
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                    .navigationTitle("Audio Player")
                } detail: {
                    switch sidebarSelection {
                    case .nowPlaying:
                        NowPlayingView(
                            player: appController.player,
                            appController: appController
                        )
                    case .library:
                        LibraryView(appController: appController)
                    case .settings:
                        SettingsView(appController: appController)
                    case nil:
                        NowPlayingView(
                            player: appController.player,
                            appController: appController
                        )
                    }
                }
            } else {
                ProgressView("Loading…")
            }
        }
        .onChange(of: sidebarSelection) { oldSelection, newSelection in
            if newSelection == .nowPlaying,
               handledExternalOpenGeneration == appController.externalOpenGeneration,
               appController.externalOpenGeneration > 0 {
                persistSidebarSelection(.nowPlaying)
                handledExternalOpenGeneration = 0
                return
            }

            if oldSelection == .settings,
               newSelection != .settings,
               appController.hasUnsavedSettingsChanges {
                pendingSidebarSelection = newSelection
                sidebarSelection = .settings

                DispatchQueue.main.async {
                    showingUnsavedChangesAlert = true
                }

                return
            }

            persistSidebarSelection(newSelection)
        }
        .task(id: appController.externalOpenGeneration) {
            guard appController.externalOpenGeneration > 0 else {
                return
            }

            await Task.yield()

            guard appController.externalOpenGeneration > handledExternalOpenGeneration else {
                return
            }

            handledExternalOpenGeneration = appController.externalOpenGeneration
            sidebarSelection = .nowPlaying
        }
        .alert(
            "Unsaved Changes",
            isPresented: $showingUnsavedChangesAlert
        ) {
            Button("Cancel", role: .cancel) {
                pendingSidebarSelection = nil
            }

            Button("Leave", role: .destructive) {
                let selection = pendingSidebarSelection
                pendingSidebarSelection = nil

                appController.setSettingsHasUnsavedChanges(false)

                if let selection {
                    sidebarSelection = selection
                }
            }
        } message: {
            Text("You have unsaved changes. Do you want to leave without saving?")
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}
