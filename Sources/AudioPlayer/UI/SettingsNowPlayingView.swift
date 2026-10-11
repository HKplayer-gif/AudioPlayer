import SwiftUI

struct SettingsNowPlayingView: View {

    @Environment(AppController.self) private var appController

    @State private var draft: SettingsState
    @State private var showDeletePlaylistsAlert = false
    @State private var showSpeedFixHelp = false

    init() {
        _draft = State(
            initialValue: .default
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            content
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .task {
            restoreDraftIfNeeded()
        }
        .onChange(of: draft) { _, newDraft in
            appController.setSettingsHasUnsavedChanges(
                newDraft != appController.settings
            )
        }
        .alert(
            "Delete All Playlists?",
            isPresented: $showDeletePlaylistsAlert
        ) {
            Button("Delete All", role: .destructive) {
                appController.playlists.deleteAll()
            }

            Button("Cancel", role: .cancel) {
            }
        } message: {
            Text(
                "This will permanently remove all playlists."
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Now Playing")
                .font(.headline)

            Spacer()

            Button("Reset") {
                resetDraft()
            }

            Button("Cancel") {
                cancelChanges()
            }

            Button("Save") {
                saveChanges()
            }
        }
        .padding()
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 24
            ) {
                playbackSection
                adjustmentAccuracySection
                progressSection
                playlistSection

                Spacer()
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .padding()
    }

    private var playbackSection: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Text("Playback")
                .font(.headline)

            HStack {
                Text("Playback Processing Mode")
                Spacer()
                Picker(
                    "",
                    selection: $draft.playbackProcessingMode
                ) {
                    Text("Native")
                        .tag(
                            PlaybackProcessingMode.native
                        )
                    Text("Processed")
                        .tag(
                            PlaybackProcessingMode.processed
                        )
                }
                .labelsHidden()
                .frame(width: 160)
            }

            HStack {
                Text("Processing Algorithm")
                Spacer()
                Picker(
                    "",
                    selection: $draft.audioProcessingAlgorithm
                ) {
                    ForEach(
                        AudioProcessingAlgorithm.allCases,
                        id: \.self
                    ) { algorithm in
                        Text(algorithm.displayName)
                            .tag(algorithm)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Enable Speed Fix")

                        Button {
                            showSpeedFixHelp = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .buttonStyle(.plain)
                        .popover(
                            isPresented: $showSpeedFixHelp,
                            arrowEdge: .trailing
                        ) {
                            speedFixHelp
                        }
                    }

                }
                Spacer()
                Toggle(
                    "",
                    isOn: $draft.speedFixEnabled
                )
                .labelsHidden()
                .frame(width: 160)
            }

            HStack {
                Text("Track Gap")
                Spacer()
                Picker(
                    "",
                    selection: $draft.trackGap
                ) {
                    ForEach(TrackGap.allCases, id: \.self) { gap in
                        Text(gap.displayName)
                            .tag(gap)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }

    private var speedFixHelp: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Text("Enable Speed Fix")
                .font(.headline)

            Text("This is a workaround for a known Speed Transition problem in the original playback path. Under some repeated speed changes, the audio can become severely distorted or, very rarely, fall into a silent or invalid render state.")

            Text("Scope: Speed Fix applies only to the System playback algorithm. SoundTouch and Signalsmith use their own independent playback pipelines and are not affected by this setting.")
                .foregroundStyle(.secondary)

            Text("What it changes")
                .font(.subheadline.weight(.semibold))

            Text("Instead of continuously reusing the same playback lane, Speed Fix alternates between two preconnected audio lanes. When Speed changes, the inactive lane is reconfigured and scheduled from the current playback position, then becomes the audible lane.")

            Text("Why")
                .font(.subheadline.weight(.semibold))

            Text("The exact underlying cause has not been proven. The separate-lane approach is being used because repeated testing suggests it can avoid the problematic long-lived playback state while keeping the existing AVFoundation playback core.")

            Text("If disabled")
                .font(.subheadline.weight(.semibold))

            Text("Audio Player returns to the original single-lane playback path. This may reduce the small transition overhead, but it can re-expose the Speed Transition distortion and silence problems described above.")
                .foregroundStyle(.secondary)

            Text("If you have a better solution, please contact me at hkplayergif.dev@gmail.com.")
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 420)
    }

    private var adjustmentAccuracySection: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Text("Adjustment Accuracy")
                .font(.headline)

            HStack {
                Text("Pitch")
                Spacer()
                Picker(
                    "",
                    selection: $draft.pitchAdjustmentAccuracy
                ) {
                    Text("Semitones")
                        .tag(
                            PitchAdjustmentAccuracy.semitone
                        )
                    Text("0.1")
                        .tag(
                            PitchAdjustmentAccuracy.tenth
                        )
                    Text("0.01")
                        .tag(
                            PitchAdjustmentAccuracy.hundredth
                        )
                }
                .labelsHidden()
                .frame(width: 160)
            }

            HStack {
                Text("Speed")
                Spacer()
                Picker(
                    "",
                    selection: $draft.speedAdjustmentStep
                ) {
                    Text("1%")
                        .tag(0.01)
                    Text("5%")
                        .tag(0.05)
                    Text("10%")
                        .tag(0.10)
                }
                .labelsHidden()
                .frame(width: 160)
            }

            HStack {
                Text("Volume")
                Spacer()
                Picker(
                    "",
                    selection: $draft.volumeAdjustmentStep
                ) {
                    Text("1%")
                        .tag(0.01)
                    Text("5%")
                        .tag(0.05)
                    Text("10%")
                        .tag(0.10)
                }
                .labelsHidden()
                .frame(width: 160)
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }

    private var progressSection: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Text("Progress Bar")
                .font(.headline)

            HStack {
                Text("Progress Save Mode")

                Spacer()

                Picker(
                    "",
                    selection: $draft.progressSaveMode
                ) {
                    Text("Never")
                        .tag(
                            ProgressSaveMode.never
                        )

                    Text("Every Second")
                        .tag(
                            ProgressSaveMode.everySecond
                        )

                    Text("Every 5 Seconds")
                        .tag(
                            ProgressSaveMode.everyFiveSeconds
                        )

                    Text("Every 10 Seconds")
                        .tag(
                            ProgressSaveMode.everyTenSeconds
                        )
                }
                .labelsHidden()
                .frame(width: 160)
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }

    private var playlistSection: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Text("Playlists")
                .font(.headline)

            HStack {
                Text("Allow Duplicate Tracks in Same Playlist")
                Spacer()
                Toggle(
                    "",
                    isOn: $draft.allowDuplicatePlaylistItems
                )
                .labelsHidden()
                .frame(width: 160)
            }

            HStack {
                Text("Enable ESC Navigation")
                Spacer()
                Toggle(
                    "",
                    isOn: $draft.playlistEscapeNavigationEnabled
                )
                .labelsHidden()
                .frame(width: 160)
            }

            Button("Delete All Playlists", role: .destructive) {
                showDeletePlaylistsAlert = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }

    // MARK: - Actions

    private func restoreDraftIfNeeded() {
        draft = appController.settings
    }

    private func resetDraft() {
        let defaults =
            appController.settingsStore
                .loadDefaultSettings()

        draft.playbackProcessingMode =
            defaults.playbackProcessingMode

        draft.audioProcessingAlgorithm =
            defaults.audioProcessingAlgorithm

        draft.trackGap =
            defaults.trackGap

        draft.speedFixEnabled =
            defaults.speedFixEnabled

        draft.progressSaveMode =
            defaults.progressSaveMode

        draft.pitchAdjustmentAccuracy =
            defaults.pitchAdjustmentAccuracy

        draft.speedAdjustmentStep =
            defaults.speedAdjustmentStep

        draft.volumeAdjustmentStep =
            defaults.volumeAdjustmentStep

        draft.allowDuplicatePlaylistItems =
            defaults.allowDuplicatePlaylistItems

        draft.playlistEscapeNavigationEnabled =
            defaults.playlistEscapeNavigationEnabled
    }

    private func cancelChanges() {
        draft.playbackProcessingMode =
            appController.settings.playbackProcessingMode

        draft.audioProcessingAlgorithm =
            appController.settings.audioProcessingAlgorithm

        draft.trackGap =
            appController.settings.trackGap

        draft.speedFixEnabled =
            appController.settings.speedFixEnabled

        draft.progressSaveMode =
            appController.settings.progressSaveMode

        draft.pitchAdjustmentAccuracy =
            appController.settings.pitchAdjustmentAccuracy

        draft.speedAdjustmentStep =
            appController.settings.speedAdjustmentStep

        draft.volumeAdjustmentStep =
            appController.settings.volumeAdjustmentStep

        draft.allowDuplicatePlaylistItems =
            appController.settings.allowDuplicatePlaylistItems

        draft.playlistEscapeNavigationEnabled =
            appController.settings.playlistEscapeNavigationEnabled
    }

    private func saveChanges() {
        var settings = appController.settings

        settings.playbackProcessingMode =
            draft.playbackProcessingMode

        settings.audioProcessingAlgorithm =
            draft.audioProcessingAlgorithm

        settings.trackGap =
            draft.trackGap

        settings.speedFixEnabled =
            draft.speedFixEnabled

        settings.progressSaveMode =
            draft.progressSaveMode

        settings.pitchAdjustmentAccuracy =
            draft.pitchAdjustmentAccuracy

        settings.speedAdjustmentStep =
            draft.speedAdjustmentStep

        settings.volumeAdjustmentStep =
            draft.volumeAdjustmentStep

        settings.allowDuplicatePlaylistItems =
            draft.allowDuplicatePlaylistItems

        settings.playlistEscapeNavigationEnabled =
            draft.playlistEscapeNavigationEnabled

        appController.saveSettings(settings)
    }
}
