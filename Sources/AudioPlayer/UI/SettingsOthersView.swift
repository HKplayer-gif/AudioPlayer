import AppKit
import SwiftUI

struct SettingsOthersView: View {
    @State private var showSupportedFormatsInfo = false
    @State private var showBPMKeyInfo = false
    @State private var showThirdPartyCredits = false
    @State private var showProjectLicenseNotice = false

    @Environment(AppController.self) private var appController

    @State private var draft: SettingsState
    @State private var showDeleteAllUserDataAlert = false
    @State private var showF7RestartHelp = false
    @State private var showCopiedToast = false

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
        .onChange(of: appController.settings.screenEffectEnabled) { _, enabled in
            draft.screenEffectEnabled = enabled
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Others")
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
                spacing: 48
            ) {
                keybindsSection

                bpmKeySection

                screenEffectSection

                accessibilitySection

                userDataSection

                infoSection

                supportSection
            }
            .frame(
                maxWidth: .infinity,
                alignment: .topLeading
            )
            .padding()
        }
    }

    private var keybindsSection: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Text("Keybinds")
                .font(.headline)

            HStack {
                Text("Enable Quick Keys")
                Spacer()
                Toggle(
                    "",
                    isOn: $draft.quickKeysEnabled
                )
                .labelsHidden()
                .frame(width: 160)
            }

            Spacer()
                .frame(height: 16)

            HStack {
                Text(
                    "Enable Track Navigation (F7 / F9 — Previous / Next)"
                )
                Spacer()
                Toggle(
                    "",
                    isOn: $draft.quickTrackNavigationEnabled
                )
                .labelsHidden()
                .frame(width: 160)
            }

            HStack {
                Text("Enable Advanced F7")

                Button {
                    showF7RestartHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.plain)
                .popover(
                    isPresented: $showF7RestartHelp,
                    arrowEdge: .trailing
                ) {
                    f7RestartHelp
                }

                Spacer()

                Toggle(
                    "",
                    isOn: $draft.f7RestartBehaviorEnabled
                )
                .labelsHidden()
                .frame(width: 160)
            }

            HStack {
                Text(
                    "Enable Playback Control (F8 — Play / Pause)"
                )
                Spacer()
                Toggle(
                    "",
                    isOn: $draft.quickPlayPauseEnabled
                )
                .labelsHidden()
                .frame(width: 160)
            }

            HStack {
                Text("Enable Arrow Key Seeking (← / →)")
                Spacer()
                Toggle(
                    "",
                    isOn: $draft.arrowKeySeekingEnabled
                )
                .labelsHidden()
                .frame(width: 160)
            }

            HStack {
                Text("Seek Accuracy")
                Spacer()
                Picker(
                    "",
                    selection: $draft.seekStep
                ) {
                    ForEach(SeekStep.allCases, id: \.self) { step in
                        Text(step.displayName)
                            .tag(step)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            Spacer()
                .frame(height: 16)

            HStack {
                Text("Enable Adjustment Quick Key (Mouse 4 / Mouse 5)*")
                Spacer()
                Toggle(
                    "",
                    isOn: $draft.mouseSideButtonsEnabled
                )
                .labelsHidden()
                .frame(width: 160)
            }

            HStack {
                Text("Enable Adjustment Quick Key (Shift + Previous / Shift + Next)*")
                Spacer()
                Toggle(
                    "",
                    isOn: $draft.shiftF7F9SideButtonsEnabled
                )
                .labelsHidden()
                .frame(width: 160)
            }

            HStack {
                Text("Reverse Mouse Side Button")
                Spacer()
                Toggle(
                    "",
                    isOn: $draft.mouseSideButtonsReversed
                )
                .labelsHidden()
                .frame(width: 160)
            }

            HStack {
                Text("Quick Key Adjustment Action")
                Spacer()
                Picker(
                    "",
                    selection: $draft.mouseSideButtonAction
                ) {
                    Text("Track")
                        .tag(MouseSideButtonAction.track)
                    Text("Pitch")
                        .tag(MouseSideButtonAction.pitch)
                    Text("Speed")
                        .tag(
                            MouseSideButtonAction.speed
                        )

                    Text("Volume")
                        .tag(
                            MouseSideButtonAction.volume
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





    private var bpmKeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BPM & Key")
                .font(.headline)

            HStack {
                Text("Enable BPM & Key")
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { draft.bpmKeyEnabled },
                        set: { enabled in
                            draft.bpmKeyEnabled = enabled
                            if !enabled {
                                draft.screenEffectEnabled = false
                            }
                        }
                    )
                )
                .labelsHidden()
                .frame(width: 160)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Analyze the current track for musical key and beat information.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { showBPMKeyInfo = true } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showBPMKeyInfo) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("BPM & Key Analysis").font(.headline)
                        Text("Uses Essentia (RhythmExtractor2013 and KeyExtractor) to analyze the current track's tempo, beat positions, and musical key.")
                        Text("Analysis may require additional memory. Enable this feature according to your needs.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(width: 360, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var screenEffectSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Screen Effect")
                .font(.headline)

            HStack {
                Text("Show effect toggle state in Current Playing tab")
                Spacer()
                Toggle(
                    "",
                    isOn: $draft.showEffectToggleStateInCurrentPlayingTab
                )
                .labelsHidden()
                .frame(width: 160)
            }

            Divider()

            HStack {
                Text("Beat Rate Multiplier")
                Spacer()
                Picker(
                    "",
                    selection: $draft.screenEffectBeatRateMultiplier
                ) {
                    ForEach(SettingsState.screenEffectBeatRateOptions, id: \.self) { multiplier in
                        Text(String(format: "%.3f×", multiplier))
                            .tag(multiplier)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }

            numericSettingRow(
                title: "Red Channel Multiplier",
                value: $draft.screenEffectRedMultiplier,
                range: 0.0...1.0,
                precision: 2,
                suffix: "×",
                step: 0.01
            )

            numericSettingRow(
                title: "Green Channel Multiplier",
                value: $draft.screenEffectGreenMultiplier,
                range: 0.0...1.0,
                precision: 2,
                suffix: "×",
                step: 0.01
            )

            numericSettingRow(
                title: "Blue Channel Multiplier",
                value: $draft.screenEffectBlueMultiplier,
                range: 0.0...1.0,
                precision: 2,
                suffix: "×",
                step: 0.01
            )

            numericSettingRow(
                title: "Pulse Strength",
                value: $draft.screenEffectStrength,
                range: 0.5...2.5,
                precision: 2,
                suffix: "×"
            )

            durationSettingRow(
                title: "Hold Duration",
                value: $draft.screenEffectHoldDuration,
                range: 0...10
            )

            durationSettingRow(
                title: "Fade In Duration",
                value: $draft.screenEffectFadeInDuration,
                range: 0...5
            )

            durationSettingRow(
                title: "Fade Out Duration",
                value: $draft.screenEffectFadeOutDuration,
                range: 0...5
            )

            HStack(alignment: .center) {
                Text("Trigger Key")
                Spacer()
                ScreenEffectHotKeyCaptureField(
                    keyLabel: (draft.screenEffectTriggerShift ? "⇧ + " : "")
                        + draft.screenEffectTriggerKeyLabel,
                    onCapture: { code, label, shift in
                        draft.screenEffectTriggerKeyCode = code
                        draft.screenEffectTriggerKeyLabel = label
                        draft.screenEffectTriggerShift = shift
                    },
                    onCancel: {}
                )
                .frame(width: 220, height: 32)
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func durationSettingRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        numericSettingRow(
            title: title,
            value: value,
            range: range,
            precision: 1,
            suffix: " s",
            step: 0.1
        )
    }

    private func numericSettingRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        precision: Int,
        suffix: String,
        step: Double = 0.01
    ) -> some View {
        let steppedValue = Binding<Double>(
            get: { value.wrappedValue },
            set: { newValue in
                let snapped = (newValue / step).rounded() * step
                value.wrappedValue = min(
                    max(snapped, range.lowerBound),
                    range.upperBound
                )
            }
        )

        return HStack {
            Text(title)
            Spacer()
            NumericSettingTextField(
                value: value,
                range: range,
                precision: precision,
                suffix: suffix
            )
            Slider(value: steppedValue, in: range)
                .frame(width: 180)
        }
    }

    private var accessibilitySection: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Text("Permissions")
                .font(.headline)

            HStack {
                Text("Accessibility")
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(appController.keybindManager.accessibilityListenerStatus)
                        .foregroundStyle(
                            appController.keybindManager.isEventTapActive
                                ? .green
                                : .secondary
                        )
                    if let description = appController.keybindManager.accessibilityRequirementDescription {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .id(appController.accessibilityPermissionRefreshToken)

                Button("Refresh") {
                    appController.refreshAccessibilityPermissionStatus()
                }

                Button("Open Settings") {
                    appController.keybindManager.openAccessibilitySettings()
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }

    private var f7RestartHelp: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Text("Advanced F7")
                .font(.headline)

            Text("When enabled, F7 uses the current playback position to decide whether to restart the current track or switch to the previous track.")

            Text("Behavior")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("• 10 seconds or less: switch to the previous track.")
                Text("• More than 10 seconds: restart the current track from the beginning.")
            }

            Text("When disabled, F7 follows the normal previous-track behavior.")
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 360)
    }

    private var userDataSection: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Text("User Data")
                .font(.headline)

            Text(
                "Permanently removes saved playback state, library data, history, playlists, recent folders, pitch cycles, and user settings."
            )
            .foregroundStyle(.secondary)

            Button("Delete All User Data", role: .destructive) {
                showDeleteAllUserDataAlert = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .alert(
            "Delete All User Data?",
            isPresented: $showDeleteAllUserDataAlert
        ) {
            Button("Delete All", role: .destructive) {
                appController.deleteAllUserData()
                draft = appController.settings
            }

            Button("Cancel", role: .cancel) {
            }
        } message: {
            Text(
                "This will permanently remove all saved user data and restore Audio Player to its default state."
            )
        }
    }

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Support Me")
                .font(.headline)
            Text("For feedback, questions, or support, you can contact me at:")
                .foregroundStyle(.secondary)
            Button {
                copySupportEmail()
            } label: {
                Label("hkplayergif.dev@gmail.com", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .overlay(alignment: .bottomTrailing) {
                if showCopiedToast {
                    Text("Copied to Clipboard")
                        .font(.callout)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                        .transition(.opacity)
                        .offset(y: 42)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var projectLicenseNotice: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Audio Player — Open Source License")
                .font(.headline)

            Text("Copyright © 2026 HKplayer-gif. Modified on November 12, 2026.")

            Text("Audio Player v4.51.4 and later are distributed under the GNU Affero General Public License, version 3 (AGPL-3.0-only).")

            Text("You may redistribute and modify this program under the terms of the AGPL-3.0. The program is provided without warranty, to the extent permitted by law.")

            Text("The corresponding source code and build materials are available from the Audio Player GitHub repository.")

            Button("Open Full AGPL-3.0 License") {
                openProjectLicense()
            }
            .buttonStyle(.link)
        }
        .frame(width: 390, alignment: .leading)
    }

    private func openProjectLicense() {
        guard let licenseURL = Bundle.module.url(
            forResource: "AudioPlayer-AGPL-3.0",
            withExtension: "txt",
            subdirectory: "ThirdPartyLicenses"
        ) else {
            return
        }

        NSWorkspace.shared.open(licenseURL)
    }

    private var thirdPartyCreditsInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Third-Party Audio Components")
                .font(.headline)

            Text("SoundTouch")
                .font(.subheadline.weight(.semibold))
            Text("SoundTouch by Olli Parviainen. Licensed under the GNU Lesser General Public License, version 2.1 (LGPL-2.1).")
            Link("SoundTouch project", destination: URL(string: "https://www.surina.net/soundtouch/")!)

            Divider()

            Text("Essentia")
                .font(.subheadline.weight(.semibold))
            Text("Essentia 2.1_beta5. Audio analysis for musical key, BPM, and beat timestamps. Licensed under GNU AGPL-3.0.")
            Link("Essentia source", destination: URL(string: "https://github.com/MTG/essentia")!)

            Divider()

            Text("FFmpeg")
                .font(.subheadline.weight(.semibold))
            Text("FFmpeg 9.0.2. Audio codec backend. This bundled build enables GPL components and is licensed under GNU GPL-3.0-or-later.")
            Link("FFmpeg source", destination: URL(string: "https://ffmpeg.org/")!)

            Divider()

            Text("Signalsmith Stretch")
                .font(.subheadline.weight(.semibold))
            Text("Signalsmith Stretch by Geraint Luff / Signalsmith Audio Ltd. Copyright © 2022. MIT License.")
            Text("Signalsmith Linear dependency by Signalsmith Audio. Copyright © 2025. MIT License.")
            Link("Signalsmith Stretch source", destination: URL(string: "https://github.com/Signalsmith-Audio/signalsmith-stretch")!)

        }
        .frame(width: 380, alignment: .leading)
    }

    private var supportedFormatsInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Supported Audio Formats")
                .font(.headline)

            Text("Playback / Library")
                .font(.subheadline.weight(.semibold))

            Text("MP3 (.mp3) — MPEG Layer III")
            Text("WAV (.wav) — Waveform Audio File Format")
            Text("FLAC (.flac) — Free Lossless Audio Codec")
            Text("OGG (.ogg) — Ogg container")
            Text("M4A (.m4a) — MPEG-4 audio")
            Text("AAC (.aac) — AAC audio")
            Text("AIFF (.aiff) — Audio Interchange File Format")

            Divider()

            Text("Export")
                .font(.subheadline.weight(.semibold))

            Text(
                "WAV, AIFF, M4A (AAC), MP3, FLAC, OGG (Vorbis), and AAC are available for export. WAV, AIFF, and M4A use native Apple encoding. MP3, FLAC, OGG (Vorbis), and raw AAC use the FFmpeg codec backend when FFmpeg is available."
            )
            .foregroundStyle(.secondary)

            Text(
                "If FFmpeg is not bundled with this build, it must be available on the Mac for MP3, FLAC, OGG, and raw AAC export."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(
                "The playback list and export formats are separate: a format being playable does not automatically mean it can be exported."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(width: 360, alignment: .leading)
    }

    private var infoSection: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Text("Info")
                .font(.headline)

            HStack {
                Text("Version")
                Spacer()
                Text("v26.11.1")
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Supported Audio Formats")
                Spacer()

                Button {
                    showSupportedFormatsInfo = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSupportedFormatsInfo) {
                    supportedFormatsInfo
                        .padding(16)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Third-Party Audio Components")
                Spacer()
                Button {
                    showThirdPartyCredits = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showThirdPartyCredits) {
                    thirdPartyCreditsInfo
                        .padding(16)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Open Source License")
                Spacer()
                Button {
                    showProjectLicenseNotice = true
                } label: {
                    Label("AGPL-3.0", systemImage: "info.circle")
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showProjectLicenseNotice) {
                    projectLicenseNotice
                        .padding(16)
                }
            }

        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }

    private func copySupportEmail() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            "hkplayergif.dev@gmail.com",
            forType: .string
        )

        withAnimation(.easeInOut(duration: 0.15)) {
            showCopiedToast = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.15)) {
                showCopiedToast = false
            }
        }
    }

    // MARK: - Actions

    private func restoreDraftIfNeeded() {
        draft = appController.settings
    }

    private func resetDraft() {
        draft = appController.settingsStore
            .loadDefaultSettings()
    }

    private func cancelChanges() {
        draft = appController.settings
    }

    private func saveChanges() {
        appController.saveSettings(draft)
    }
}


private struct NumericSettingTextField: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let precision: Int
    let suffix: String

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 68)
                .focused($isFocused)
                .onAppear(perform: synchronizeText)
                .onSubmit(commit)
                .onChange(of: text) { _, newText in
                    applyValidText(newText)
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }
                .onChange(of: value) { _, _ in
                    if !isFocused { synchronizeText() }
                }

            Text(suffix)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func synchronizeText() {
        text = String(format: "%.*f", precision, value)
    }

    private func applyValidText(_ rawText: String) {
        let candidate = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let decimalPattern = #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$"#
        guard candidate.range(of: decimalPattern, options: .regularExpression) != nil,
              let parsed = Double(candidate),
              parsed.isFinite,
              range.contains(parsed) else { return }
        let scale = pow(10.0, Double(precision))
        value = (parsed * scale).rounded() / scale
    }

    private func commit() {
        applyValidText(text)
        synchronizeText()
    }
}
