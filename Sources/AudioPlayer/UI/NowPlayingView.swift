import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct NowPlayingView: View {

    private struct PitchCycleListItem: Identifiable {
        let pitch: Int

        var id: Int {
            pitch
        }
    }

    private enum NowPlayingSection: Hashable {
        case playlists
        case currentlyPlaying
        case pitchCycles
    }

    private let player: Player

    @Environment(AppController.self) private var appController

    @State private var selectedSection: NowPlayingSection
    @State private var pitchCycleSelectionAnchor: Int?
    @State private var pitchCycleTransitionID = UUID()
    @State private var pitchCycleOffsetText = ""
    @State private var pitchCycleSaveErrorMessage: String?

    @State private var playbackProgress: PlaybackProgress
    @State private var isSeeking = false
    @State private var seekPosition: Double = 0.0
    @State private var hoveredSection: NowPlayingSection?
    @State private var coverImage: NSImage?
    @State private var currentTrack: Track?
    @State private var exportErrorMessage: String?
    @State private var isExporting = false

    @MainActor
    init(player: Player, appController: AppController) {
        self.player = player

        switch appController.persistence.appState.nowPlayingSection {
        case "playlists":
            _selectedSection = State(initialValue: .playlists)
        case "pitchCycles":
            _selectedSection = State(initialValue: .pitchCycles)
        case "currentlyPlaying":
            _selectedSection = State(initialValue: .currentlyPlaying)
        default:
            _selectedSection = State(initialValue: .currentlyPlaying)
        }

        let progress = PlaybackProgress()
        progress.update(
            position: player.currentPlaybackPosition,
            duration: player.currentTrackDuration
        )

        _playbackProgress = State(initialValue: progress)
    }

    private var pitchCyclesAreActive: Bool {
        appController.isPitchCyclesPlaybackActive
    }

    var body: some View {
        VStack(spacing: 0) {

            HStack(spacing: 0) {

                sectionButton(
                    title: "Currently Playing",
                    section: .currentlyPlaying
                )

                sectionButton(
                    title: "Playlists",
                    section: .playlists
                )

                sectionButton(
                    title: "Pitch Cycles",
                    section: .pitchCycles
                )
            }
            .padding()

            Divider()

            Group {
                switch selectedSection {
                case .playlists:
                    PlaylistHomeView()

                case .currentlyPlaying:
                    currentlyPlayingContent

                case .pitchCycles:
                    pitchCyclesContent
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
        .navigationTitle("Now Playing")
        .onChange(of: selectedSection) { _, newSection in
            persistSection(newSection)
        }
        .onChange(of: appController.playbackUIRefreshToken) { _, _ in
            updatePlaybackProgress()
        }
        .alert(
            "Export Failed",
            isPresented: Binding(
                get: {
                    exportErrorMessage != nil
                },
                set: { visible in
                    if !visible {
                        exportErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {
                exportErrorMessage = nil
            }
        } message: {
            Text(exportErrorMessage ?? "")
        }
        .task(id: player.currentTrackURL) {
            await loadCurrentTrackMetadata()

            coverImage = nil

            guard let currentTrackURL = player.currentTrackURL else {
                return
            }

            let loadedCover = await CoverLoader.load(
                from: currentTrackURL
            )

            guard !Task.isCancelled else {
                return
            }

            coverImage = loadedCover.flatMap {
                NSImage(data: $0.data)
            }
        }
    }

    private func sectionButton(
        title: String,
        section: NowPlayingSection
    ) -> some View {
        Button {
            
            if selectedSection == .pitchCycles,
               section != .pitchCycles {
                appController.pitchCycles.restoreLastSaved()
                syncPitchCycleOffsetText()
            }

            selectedSection = section
        } label: {
            Text(title)
                .frame(
                    maxWidth: .infinity
                )
                .frame(height: 28)
                .background(
                    RoundedRectangle(
                        cornerRadius: 6
                    )
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
                    RoundedRectangle(
                        cornerRadius: 6
                    )
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredSection = hovering ? section : nil
        }
        .frame(
            maxWidth: .infinity
        )
        .frame(height: 28)
    }
    private var pitchCycleList: some View {
        ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: 0
            ) {
                ListTransition<PitchCycleListItem, PitchCycleRow>(
                    items:
                        appController.pitchCycles
                            .availableBasePitches
                            .map { pitch in
                                PitchCycleListItem(pitch: pitch)
                            },
                    isInteractionEnabled: { _ in
                        true
                    },
                    isRapidScrolling: false,
                    transitionID: pitchCycleTransitionID
                ) { item, _ in
                    PitchCycleRow(
                        title:
                            item.pitch >= 0
                            ? "+\(item.pitch)"
                            : "\(item.pitch)",
                        isSelected:
                            appController.pitchCycles
                                .selectedBasePitches
                                .contains(item.pitch),
                        onSelect: { isShiftPressed in
                            togglePitchCycleSelection(
                                item.pitch,
                                isShiftPressed:
                                    isShiftPressed
                            )
                        }
                    )
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var pitchCyclesContent: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Base Pitch")
                        .font(.headline)

                    Spacer()

                    SortControl(
                        sortOrder:
                            appController.pitchCycles.sortOrder,
                        options: [
                            SortOption(
                                id: PitchCycleState.SortOrder.ascending,
                                title: "Ascend"
                            ),
                            SortOption(
                                id: PitchCycleState.SortOrder.descending,
                                title: "Descend"
                            )
                        ],
                        onSelect: setPitchCycleSortOrder
                    )
                }

                pitchCycleList

                .frame(
                    minWidth: 300,
                    maxWidth: .infinity
                )
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            Color(
                                nsColor:
                                    .controlBackgroundColor
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            Color.secondary.opacity(0.25),
                            lineWidth: 1
                        )
                }
            }

            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                Text("Offset")
                    .font(.headline)

                HStack(spacing: 8) {
                    TextField(
                        "0.00",
                        text: $pitchCycleOffsetText
                    )
                    .frame(width: 76)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        commitPitchCyclesOffset()
                    }

                    Button {
                        appController.pitchCycles.resetOffset()
                        syncPitchCycleOffsetText()
                    } label: {
                        Image(
                            systemName:
                                "arrow.counterclockwise"
                        )
                    }
                    .buttonStyle(.borderless)
                    .help("Reset Offset")
                }

                Text("−0.99 to +0.99")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let current =
                    appController.pitchCycles.currentEffectivePitch
                {
                    Divider()

                    Text(
                        String(
                            format:
                                "Current Cycle Pitch: %+.2f",
                            current
                        )
                    )
                    .font(.title3)
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button {
                        appController.pitchCycles.previousCycle()
                    } label: {
                        Label(
                            "Previous",
                            systemImage: "chevron.left"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        appController.pitchCycles
                            .sortedBasePitches.isEmpty
                    )

                    Button {
                        appController.pitchCycles.nextCycle()
                    } label: {
                        Label(
                            "Next",
                            systemImage: "chevron.right"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        appController.pitchCycles
                            .sortedBasePitches.isEmpty
                    )
                }

                Spacer(minLength: 10)

                VStack(
                    alignment: .leading,
                    spacing: 12
                ) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                Color.black.opacity(0.75)
                            )

                        if let coverImage {
                            Image(nsImage: coverImage)
                                .resizable()
                                .scaledToFill()
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 8
                                    )
                                )
                        } else {
                            Text("COVER")
                                .font(.headline)
                                .foregroundStyle(
                                    .white.opacity(0.75)
                                )
                        }
                    }
                    .frame(
                        width: 200,
                        height: 200
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: 8)
                    )

                    currentTrackInfo
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                }

                Spacer(minLength: 10)

                HStack(spacing: 8) {
                    Button("Reset") {
                        appController.pitchCycles.resetToDefault()
                        syncPitchCycleOffsetText()
                        refreshPitchCycleList()
                    }

                    Button("Cancel") {
                        appController.pitchCycles.restoreLastSaved()
                        syncPitchCycleOffsetText()
                        refreshPitchCycleList()
                    }

                    Button("Save") {
                        savePitchCycles()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(
                width: 260,
                alignment: .topLeading
            )
        }
        .padding(20)
        .onAppear {
            syncPitchCycleOffsetText()
        }
        .onChange(
            of: appController.pitchCycles.offset
        ) { _, newValue in
            pitchCycleOffsetText = String(
                format: "%.2f",
                newValue
            )
        }
        .alert(
            "Cannot Save Pitch Cycles",
            isPresented: Binding(
                get: {
                    pitchCycleSaveErrorMessage != nil
                },
                set: { visible in
                    if !visible {
                        pitchCycleSaveErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {
                pitchCycleSaveErrorMessage = nil
            }
        } message: {
            Text(
                pitchCycleSaveErrorMessage
                    ?? ""
            )
        }
    }



    private func setPitchCycleSortOrder(
        _ order: PitchCycleState.SortOrder
    ) {
        guard appController.pitchCycles.sortOrder != order else {
            return
        }

        appController.pitchCycles.setSortOrder(order)
        refreshPitchCycleList()
    }

    private func refreshPitchCycleList() {
        pitchCycleTransitionID = UUID()
    }

    private func togglePitchCycleSelection(
        _ pitch: Int,
        isShiftPressed: Bool
    ) {
        let selected =
            appController.pitchCycles.selectedBasePitches

        if isShiftPressed,
           let anchor = pitchCycleSelectionAnchor {
            let lower = min(anchor, pitch)
            let upper = max(anchor, pitch)

            let range = Set(lower...upper)
            let shouldClear = range.isSubset(of: selected)

            var updated = selected

            if shouldClear {
                updated.subtract(range)
            } else {
                updated.formUnion(range)
            }

            appController.pitchCycles.setSelection(updated)
            return
        }

        var updated = selected

        if updated.contains(pitch) {
            updated.remove(pitch)
        } else {
            updated.insert(pitch)
        }

        appController.pitchCycles.setSelection(updated)
        pitchCycleSelectionAnchor = pitch
    }

    private func syncPitchCycleOffsetText() {
        pitchCycleOffsetText = String(
            format: "%.2f",
            appController.pitchCycles.offset
        )
    }

    private func commitPitchCyclesOffset() {
        guard let value = Double(pitchCycleOffsetText) else {
            syncPitchCycleOffsetText()
            return
        }

        let clamped = min(
            max(value, -0.99),
            0.99
        )

        appController.pitchCycles.setOffset(clamped)

        pitchCycleOffsetText = String(
            format: "%.2f",
            clamped
        )
    }

    private func savePitchCycles() {
        guard !appController.pitchCycles.selectedBasePitches.isEmpty else {
            pitchCycleSaveErrorMessage =
                "At least one Base Pitch must be selected."
            return
        }

        commitPitchCyclesOffset()
        appController.pitchCycles.save()
        refreshPitchCycleList()
    }

    private var currentTrackInfo: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(currentTrack?.title ?? "No Track Playing")
                .font(.title2)
                .fontWeight(.semibold)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Artist:")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Text(currentTrack?.artist ?? "Unknown")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Text("Album:")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Text(currentTrack?.album ?? "Unknown")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func loadCurrentTrackMetadata() async {
        guard let url = player.currentTrackURL else {
            currentTrack = nil
            return
        }

        let libraryTrack = appController.library.tracks.first {
            $0.id == url
        }

        let scannedTrack = await LibraryScanner.scanFile(
            fileURL: url
        )

        guard !Task.isCancelled else {
            return
        }

        guard let libraryTrack else {
            currentTrack = scannedTrack
            return
        }

        guard let scannedTrack else {
            currentTrack = libraryTrack
            return
        }

        currentTrack = Track(
            id: libraryTrack.id,
            title:
                libraryTrack.title.isEmpty
                ? scannedTrack.title
                : libraryTrack.title,
            artist:
                libraryTrack.artist
                ?? scannedTrack.artist,
            album:
                libraryTrack.album
                ?? scannedTrack.album,
            fileFormat: libraryTrack.fileFormat,
            duration: libraryTrack.duration,
            filePath: libraryTrack.filePath
        )
    }

    private var currentlyPlayingContent: some View {
        VStack(spacing: 18) {

            HStack(alignment: .top, spacing: 18) {

                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.75))

                    if let coverImage {
                        Image(nsImage: coverImage)
                            .resizable()
                            .scaledToFill()
                            .clipShape(
                                RoundedRectangle(cornerRadius: 8)
                            )
                    } else {
                        Text("COVER")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .frame(width: 150, height: 150)
                .clipShape(
                    RoundedRectangle(cornerRadius: 8)
                )

                currentTrackInfo
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                PlaybackContextView()
                    .frame(width: 220)
            }

            parameterSection(
                title: "Pitch",
                valueText: String(
                    format: "%+.2f",
                    player.pitch
                ),
                value: Binding(
                    get: { player.pitch },
                    set: { player.pitch = $0 }
                ),
                range: -12...12,
                step: 1,
                reset: { player.pitch = 0 }
            )
            .disabled(
                player.playbackProcessingMode == .native
                || pitchCyclesAreActive
            )

            parameterSection(
                title: "Speed",
                valueText: String(
                    format: "%.0f%%",
                    player.speed * 100
                ),
                value: Binding(
                    get: { player.speed * 100 },
                    set: {
                        player.speed = Double(
                            Int($0.rounded())
                        ) / 100
                    }
                ),
                range: 10...300,
                step: 10,
                reset: { player.speed = 1.0 }
            )
            .disabled(player.playbackProcessingMode == .native)

            parameterSection(
                title: "Volume",
                valueText: String(
                    format: "%.0f%%",
                    player.volume * 100
                ),
                value: Binding(
                    get: { player.volume * 100 },
                    set: { player.volume = $0 / 100 }
                ),
                range: 0...100,
                step: 5,
                reset: { player.volume = 1.0 }
            )

            VStack(spacing: 8) {
                HStack {
                    Text(
                        "\(Int(isSeeking ? seekPosition : playbackProgress.position))s"
                    )
                    Spacer()
                    Text(
                        "\(Int(playbackProgress.duration))s"
                    )
                }
                .font(.body)
                .foregroundStyle(.primary)

                Slider(
                    value: Binding(
                        get: {
                            isSeeking
                                ? seekPosition
                                : playbackProgress.position
                        },
                        set: {
                            seekPosition = $0
                            isSeeking = true
                        }
                    ),
                    in: 0...max(
                        playbackProgress.duration,
                        0.001
                    ),
                    onEditingChanged: { editing in
                        if editing {
                            seekPosition = playbackProgress.position
                            isSeeking = true
                        } else {
                            player.seek(to: seekPosition)
                            playbackProgress.update(
                                position: seekPosition,
                                duration: playbackProgress.duration
                            )
                            isSeeking = false
                        }
                    }
                )
                .disabled(
                    playbackProgress.duration <= 0
                )
            }

            Spacer(minLength: 4)

            HStack(spacing: 40) {
                Button {
                    appController.previous()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }

                Button {
                    togglePlayPause()
                } label: {
                    Image(
                        systemName:
                            player.playbackState == .playing
                            ? "pause.fill"
                            : "play.fill"
                    )
                    .font(.title2)
                }

                Button {
                    appController.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
            }

            HStack(alignment: .center, spacing: 12) {
                Button {
                    replay()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.title3)
                }
                .buttonStyle(.bordered)

                PlaybackModeControl(
                    playbackMode: appController.playbackMode,
                    onSelect: { mode in
                        appController.setPlaybackMode(mode)
                    }
                )

                PitchCyclesControl(
                    isEnabled:
                        appController.pitchCycles.isEnabled,
                    onSelect: { enabled in
                        appController.setPitchCyclesEnabled(enabled)
                    }
                )

                Button {
                    exportCurrentTrack()
                } label: {
                    Label(
                        isExporting ? "Exporting..." : "Export",
                        systemImage: "square.and.arrow.up"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(
                    player.currentTrackURL == nil || isExporting
                )
            }
            .frame(maxWidth: .infinity)
        }
        .padding(30)
        .frame(
            minWidth: 500,
            minHeight: 500
        )
        .task(id: appController.isApplicationActive) {
            guard appController.isApplicationActive else {
                return
            }

            while !Task.isCancelled,
                  appController.isApplicationActive {
                updatePlaybackProgress()
                try? await Task.sleep(
                    for: .milliseconds(100)
                )
            }
        }
    }

    private func persistSection(
        _ section: NowPlayingSection
    ) {

        let value: String

        switch section {

        case .playlists:
            value = "playlists"

        case .currentlyPlaying:
            value = "currentlyPlaying"

        case .pitchCycles:
            value = "pitchCycles"
        }

        var appState = appController.persistence.appState
        appState.nowPlayingSection = value
        appController.persistence.reportApp(appState)
    }

    @ViewBuilder
    private func parameterSection(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double?,
        reset: @escaping () -> Void
    ) -> some View {

        HStack(spacing: 12) {

            VStack(alignment: .leading, spacing: 8) {

                Text("\(title): \(valueText)")

                if let step {

                    Slider(
                        value: value,
                        in: range,
                        step: step
                    )

                } else {

                    Slider(
                        value: value,
                        in: range
                    )
                }
            }

            ResetButton(action: reset)
        }
    }


    private func togglePlayPause() {

        switch player.playbackState {

        case .playing:
            player.pause()

        case .paused:
            player.resume()

        case .stopped:

            guard player.currentTrackURL != nil else {
                return
            }

            do {

                try player.continuePlayback()

            } catch {

                print(
                    "Failed to continue playback:",
                    error
                )
            }
        }
    }

    private func updatePlaybackProgress() {

        guard !isSeeking else {
            return
        }

        let duration = player.currentTrackDuration

        if let position = player.currentPlaybackPosition(
            shouldAutoSave: false
        ) {

            playbackProgress.update(
                position: position,
                duration: duration
            )

        } else {

            playbackProgress.update(
                position: playbackProgress.position,
                duration: duration
            )
        }
    }
    private var playbackModeTitle: String {
        switch appController.playbackMode {
        case .single:
            return "Single Track"
        case .repeatOne:
            return "Repeat Track"
        case .list:
            return "Single List"
        case .repeatList:
            return "Repeat List"
        }
    }

    private var playbackModeIcon: String {
        switch appController.playbackMode {
        case .single:
            return "play"
        case .repeatOne:
            return "repeat.1"
        case .list:
            return "list.number"
        case .repeatList:
            return "repeat"
        }
    }

    private func exportCurrentTrack() {
        guard let sourceURL = player.currentTrackURL else {
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Audio"
        panel.prompt = "Export"
        panel.nameFieldLabel = "Export As:"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowsOtherFileTypes = false
        panel.allowedContentTypes = [
            .wav,
            .aiff,
            .mpeg4Audio,
            UTType(filenameExtension: "mp3"),
            UTType(filenameExtension: "flac"),
            UTType(filenameExtension: "ogg"),
            UTType(filenameExtension: "aac")
        ].compactMap { $0 }

        let defaultBaseName =
            currentTrack?.title
            ?? sourceURL.deletingPathExtension().lastPathComponent

        panel.nameFieldStringValue =
            "\(defaultBaseName).wav"

        let formatPopup = NSPopUpButton(
            frame: NSRect(
                x: 0,
                y: 0,
                width: 220,
                height: 28
            )
        )
        formatPopup.addItems(
            withTitles: AudioExportFormat.allCases.map(\.displayName)
        )
        formatPopup.selectItem(at: 0)
        let formatHandler = ExportFormatSelectionHandler(panel: panel)
        formatPopup.target = formatHandler
        formatPopup.action = #selector(ExportFormatSelectionHandler.formatChanged(_:))

        let accessory = NSStackView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: 320,
                height: 36
            )
        )
        accessory.orientation = .horizontal
        accessory.spacing = 10

        let formatLabel = NSTextField(
            labelWithString: "Format:"
        )
        accessory.addArrangedSubview(formatLabel)
        accessory.addArrangedSubview(formatPopup)
        panel.accessoryView = accessory
        panel.setContentSize(NSSize(width: 720, height: 500))

        guard panel.runModal() == .OK,
              let selectedURL = panel.url else {
            return
        }

        let formatIndex = formatPopup.indexOfSelectedItem
        guard AudioExportFormat.allCases.indices.contains(formatIndex) else {
            return
        }

        let format = AudioExportFormat.allCases[formatIndex]
        let destinationURL =
            selectedURL
                .deletingPathExtension()
                .appendingPathExtension(format.fileExtension)

        let algorithm =
            appController.settings.audioProcessingAlgorithm
        let pitch = player.pitch
        let speed = player.speed
        let volume = player.volume

        isExporting = true

        Task.detached(priority: .userInitiated) {
            do {
                try AudioExporter.export(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    format: format,
                    algorithm: algorithm,
                    pitch: pitch,
                    speed: speed,
                    volume: volume
                )

                await MainActor.run {
                    isExporting = false
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportErrorMessage =
                        error.localizedDescription
                }
            }
        }
    }

    private func replay() {

        do {

            try player.restart()

        } catch {

            print(
                "Failed to replay:",
                error
            )
        }
    }
}

@MainActor
private final class ExportFormatSelectionHandler: NSObject {
    weak var panel: NSSavePanel?

    init(panel: NSSavePanel) {
        self.panel = panel
    }

    @objc func formatChanged(_ sender: NSPopUpButton) {
        guard let panel else { return }
        let formats = AudioExportFormat.allCases
        let index = sender.indexOfSelectedItem
        guard formats.indices.contains(index) else { return }

        let currentName = panel.nameFieldStringValue
        let baseName = (currentName as NSString).deletingPathExtension
        guard !baseName.isEmpty else { return }
        panel.nameFieldStringValue =
            "\(baseName).\(formats[index].fileExtension)"
    }
}

private struct PlaybackModeControl: View {

    let playbackMode: PlaybackMode
    let onSelect: (PlaybackMode) -> Void

    @State private var isPresented = false

    private let options: [(PlaybackMode, String)] = [
        (.single, "Single Track"),
        (.repeatOne, "Repeat Track"),
        (.list, "Single List"),
        (.repeatList, "Repeat List")
    ]

    var body: some View {

        Button {
            isPresented.toggle()
        } label: {
            Label(
                title,
                systemImage: icon
            )
            .font(.body)
            .lineLimit(1)
            .frame(width: 130)
        }
        .buttonStyle(.bordered)
        .popover(
            isPresented: $isPresented,
            arrowEdge: .bottom
        ) {
            VStack(spacing: 4) {
                ForEach(options, id: \.0) { option in
                    optionRow(
                        title: option.1,
                        mode: option.0
                    )
                }
            }
            .padding(8)
            .frame(width: 220)
        }
    }

    private func optionRow(
        title: String,
        mode: PlaybackMode
    ) -> some View {
        PlaybackModeOptionRow(
            title: title,
            mode: mode,
            playbackMode: playbackMode,
            onSelect: { selectedMode in
                onSelect(selectedMode)
                isPresented = false
            }
        )
    }

    private var title: String {
        switch playbackMode {
        case .single:
            return "Single Track"
        case .repeatOne:
            return "Repeat Track"
        case .list:
            return "Single List"
        case .repeatList:
            return "Repeat List"
        }
    }

    private var icon: String {
        switch playbackMode {
        case .single:
            return "play"
        case .repeatOne:
            return "repeat.1"
        case .list:
            return "list.number"
        case .repeatList:
            return "repeat"
        }
    }
}

private struct PitchCyclesControl: View {

    let isEnabled: Bool
    let onSelect: (Bool) -> Void

    @State private var isPresented = false

    private let options: [(Bool, String)] = [
        (true, "Pitch Cycles On"),
        (false, "Pitch Cycles Off")
    ]

    var body: some View {

        Button {
            isPresented.toggle()
        } label: {
            Label(
                title,
                systemImage: "arrow.triangle.2.circlepath"
            )
            .font(.body)
            .lineLimit(1)
            .frame(width: 130)
        }
        .buttonStyle(.bordered)
        .frame(width: 130)
        .popover(
            isPresented: $isPresented,
            arrowEdge: .bottom
        ) {
            VStack(spacing: 4) {
                ForEach(options, id: \.0) { option in
                    optionRow(
                        title: option.1,
                        enabled: option.0
                    )
                }
            }
            .padding(8)
            .frame(width: 220)
        }
    }

    private func optionRow(
        title: String,
        enabled: Bool
    ) -> some View {
        PitchCyclesOptionRow(
            title: title,
            enabled: enabled,
            isEnabled: isEnabled,
            onSelect: { selected in
                onSelect(selected)
                isPresented = false
            }
        )
    }

    private var title: String {
        isEnabled
            ? "Pitch Cycles On"
            : "Pitch Cycles Off"
    }
}

private struct PitchCyclesOptionRow: View {

    let title: String
    let enabled: Bool
    let isEnabled: Bool
    let onSelect: (Bool) -> Void

    @State private var isHovered = false

    private var backgroundOpacity: Double {
        if isEnabled == enabled {
            return 0.50
        }

        if isHovered {
            return 0.25
        }

        return 0.0
    }

    var body: some View {

        Button {
            onSelect(enabled)
        } label: {
            HStack {
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        Color.secondary.opacity(
                            backgroundOpacity
                        )
                    )
            }
            .contentShape(
                RoundedRectangle(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct PlaybackModeOptionRow: View {

    let title: String
    let mode: PlaybackMode
    let playbackMode: PlaybackMode
    let onSelect: (PlaybackMode) -> Void

    @State private var isHovered = false

    private var isSelected: Bool {
        playbackMode == mode
    }

    private var backgroundOpacity: Double {
        if isSelected {
            return 0.50
        }

        if isHovered {
            return 0.25
        }

        return 0.0
    }

    var body: some View {
        Button {
            onSelect(mode)
        } label: {
            HStack {
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        Color.secondary.opacity(
                            backgroundOpacity
                        )
                    )
            }
            .contentShape(
                RoundedRectangle(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct ResetButton: View {

    let action: () -> Void

    @State private var isHovered = false
    @State private var isActivated = false

    var body: some View {

        Button {

            action()

            withAnimation(.easeOut(duration: 0.08)) {
                isActivated = true
            }

            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.12
            ) {

                withAnimation(.easeOut(duration: 0.12)) {
                    isActivated = false
                }
            }

        } label: {

            Image(systemName: "arrow.counterclockwise")
                .font(.body)
                .frame(
                    width: 40,
                    height: 32
                )
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(
                            isActivated
                            ? Color.primary.opacity(0.18)
                            : isHovered
                            ? Color.primary.opacity(0.08)
                            : Color.clear
                        )
                )
                .contentShape(
                    RoundedRectangle(cornerRadius: 7)
                )
        }
        .buttonStyle(.borderless)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("Reset")
    }
}
