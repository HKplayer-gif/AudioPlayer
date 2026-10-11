import Foundation
import AppKit
import Observation

@MainActor
@Observable
final class AppController {
    let persistence: PersistenceCoordinator

    let settingsStore: SettingsStore
    private(set) var settings: SettingsState
    private(set) var hasUnsavedSettingsChanges = false

    let selectedFolder: SelectedFolder
    let library: Library
    let player: Player
    let pitchCycles: PitchCyclesStore
    let history: History
    let playlists: PlaylistStore
    let keybindManager: KeybindManager
    let nowPlayingController: NowPlayingController

    private(set) var playbackQueue: PlaybackQueue?
    private(set) var playbackQueueCurrentIndex: Int?
    private(set) var currentPlaylistItemID: UUID?
    private(set) var currentPlaylistID: UUID?
    private(set) var playbackMode: PlaybackMode = .single
    private(set) var playbackErrorMessage: String?
    private var playbackMonitorTask: Task<Void, Never>?
    private var playbackGapTask: Task<Void, Never>?

    let browser: Browser

    private(set) var isReady = false
    private(set) var isApplicationActive = true
    private(set) var playbackUIRefreshToken = 0
    private(set) var accessibilityPermissionRefreshToken = 0
    private var pendingExternalFileURL: URL?
    private(set) var externalOpenGeneration = 0

    init() {
        persistence = PersistenceCoordinator()

        settingsStore = SettingsStore()
        let loadedSettings =
            settingsStore.loadUserSettings()
            ?? settingsStore.loadDefaultSettings()

        settings = loadedSettings

        selectedFolder = SelectedFolder()
        library = Library()
        player = Player()
        pitchCycles = PitchCyclesStore()
        history = History(
            maximumCount: loadedSettings.historyCapacity
        )
        playlists = PlaylistStore()
        keybindManager = KeybindManager(
            settings: loadedSettings
        )
        nowPlayingController = NowPlayingController()

        browser = Browser()
        nowPlayingController.onPlay = { [weak self] in
            guard let self else {
                return
            }
            self.player.resume()
        }

        nowPlayingController.onPause = { [weak self] in
            guard let self else {
                return
            }
            self.player.pause()
        }

        nowPlayingController.onTogglePlayPause = { [weak self] in
            guard let self else {
                return
            }
            self.player.togglePlayPause()
        }

        nowPlayingController.onPreviousTrack = { [weak self] in
            guard let self else {
                return
            }
            self.previous()
        }

        nowPlayingController.onNextTrack = { [weak self] in
            guard let self else {
                return
            }
            self.next()
        }

        AudioPlayerAppDelegate.externalFileOpenHandler = { [weak self] urls in
            guard let self else {
                return
            }

            for url in urls {
                self.handleExternalFileOpen(url)
            }
        }

        let pendingExternalFileURLs =
            AudioPlayerAppDelegate.pendingExternalFileURLs
        AudioPlayerAppDelegate.pendingExternalFileURLs.removeAll()
        pendingExternalFileURL = pendingExternalFileURLs.first
        player.playbackProcessingMode = settings.playbackProcessingMode
        player.audioProcessingAlgorithm = settings.audioProcessingAlgorithm
        player.speedFixEnabled = settings.speedFixEnabled
        player.progressSaveMode = settings.progressSaveMode

        player.onPersistentStateChange = { [weak self] playerState in
            self?.persistence.reportPlayer(playerState)
        }
        player.onPlaybackStateChange = { [weak self] playbackState in
            guard let self else {
                return
            }

            self.nowPlayingController.update(
                playbackState: playbackState,
                currentTrackURL: self.player.currentTrackURL,
                currentTrackDuration: self.player.currentTrackDuration
            )

            switch playbackState {
            case .playing:
                self.cancelPendingPlaybackGap()
                self.startPlaybackMonitor()
            case .paused, .stopped:
                self.stopPlaybackMonitor()
            }
        }

        player.onPlaybackEnded = { [weak self] in
            guard let self else {
                return
            }

            self.playbackGapTask?.cancel()
            let gap = self.settings.trackGap

            guard gap != .none else {
                self.advanceAfterPlaybackGap()
                return
            }

            self.playbackGapTask = Task { @MainActor [weak self] in
                let nanoseconds = UInt64(gap.rawValue * 1_000_000_000)
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return
                }

                guard let self, !Task.isCancelled else {
                    return
                }

                self.playbackGapTask = nil
                self.advanceAfterPlaybackGap()
            }
        }

        keybindManager.onAction = { [weak self] action in
            guard let self else {
                return
            }

            switch action {
            case .previousTrack:
                self.previous()

            case .f7PreviousTrack:
                self.handleF7PreviousTrack()

            case .playPause:
                self.player.togglePlayPause()

            case .nextTrack:
                self.next()

            case .seekBackward:
                self.player.seek(to: self.player.currentPlaybackPosition - self.settings.seekStep.seconds)

            case .seekForward:
                self.player.seek(to: self.player.currentPlaybackPosition + self.settings.seekStep.seconds)

            case .mouseSideButtonDown:
                let succeeded: Bool

                switch self.settings.mouseSideButtonAction {
                case .pitch:
                    guard !self.isPitchCyclesPlaybackActive else {
                        return
                    }

                    succeeded = self.player.adjustPitch(
                        direction: .down,
                        accuracy: self.settings.pitchAdjustmentAccuracy
                    )

                case .speed:
                    succeeded = self.player.adjustSpeed(
                        direction: .down,
                        step: self.settings.speedAdjustmentStep
                    )

                case .volume:
                    succeeded = self.player.adjustVolume(
                        direction: .down,
                        step: self.settings.volumeAdjustmentStep
                    )
                }

                if succeeded {
                } else {
                    NSSound.beep()
                }

            case .mouseSideButtonUp:
                let succeeded: Bool

                switch self.settings.mouseSideButtonAction {
                case .pitch:
                    guard !self.isPitchCyclesPlaybackActive else {
                        return
                    }

                    succeeded = self.player.adjustPitch(
                        direction: .up,
                        accuracy: self.settings.pitchAdjustmentAccuracy
                    )

                case .speed:
                    succeeded = self.player.adjustSpeed(
                        direction: .up,
                        step: self.settings.speedAdjustmentStep
                    )

                case .volume:
                    succeeded = self.player.adjustVolume(
                        direction: .up,
                        step: self.settings.volumeAdjustmentStep
                    )
                }

                if succeeded {
                } else {
                    NSSound.beep()
                }
            }
        }

        keybindManager.startMonitoring()

        Task { @MainActor in
            await initialize()
        }
    }

    var isPitchCyclesPlaybackActive: Bool {
        pitchCycles.isEnabled
            && (playbackMode == .repeatOne || playbackMode == .repeatList)
    }

    private var pitchCyclePlaybackContext: PitchCyclePlaybackContext {
        PitchCyclePlaybackContext(
            isEnabled: { [weak self] in
                self?.pitchCycles.isEnabled == true
            },
            currentEffectivePitch: { [weak self] in
                self?.pitchCycles.currentEffectivePitch
            },
            advance: { [weak self] in
                self?.pitchCycles.nextCycle()
            }
        )
    }

    private func startPlaybackMonitor() {
        guard isApplicationActive,
              playbackMonitorTask == nil else {
            return
        }

        playbackMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self,
                      self.isApplicationActive else {
                    return
                }

                _ = self.player.currentPlaybackPosition(
                    shouldAutoSave: true
                )

                try? await Task.sleep(
                    for: .seconds(1)
                )
            }
        }
    }

    private func stopPlaybackMonitor() {
        playbackMonitorTask?.cancel()
        playbackMonitorTask = nil
    }

    func setSettingsHasUnsavedChanges(_ value: Bool) {
        hasUnsavedSettingsChanges = value
    }

    func handleApplicationDidBecomeActive() {
        isApplicationActive = true

        _ = player.currentPlaybackPosition(
            shouldAutoSave: true
        )

        playbackUIRefreshToken &+= 1
        refreshAccessibilityPermissionStatus()

        if player.playbackState == .playing {
            startPlaybackMonitor()
        }
    }

    func handleApplicationWillResignActive() {
        _ = player.currentPlaybackPosition(
            shouldAutoSave: true
        )

        isApplicationActive = false
        stopPlaybackMonitor()
    }

    func refreshAccessibilityPermissionStatus() {
        _ = keybindManager.refreshAccessibilityPermission()
        accessibilityPermissionRefreshToken &+= 1
    }

    func saveSettings(_ settings: SettingsState) {
        _ = keybindManager.canApplySettings(settings)

        do {
            try settingsStore.saveUserSettings(settings)
            self.settings = settings
            self.hasUnsavedSettingsChanges = false
            self.keybindManager.updateSettings(settings)
            // Apply the selected algorithm and Speed Fix flag before changing
            // Native/Processed mode, so the mode transition activates only the
            // final intended playback route.
            self.player.audioProcessingAlgorithm =
                settings.audioProcessingAlgorithm
            self.player.speedFixEnabled = settings.speedFixEnabled
            self.player.playbackProcessingMode =
                settings.playbackProcessingMode
            self.player.progressSaveMode = settings.progressSaveMode
            self.history.setMaximumCount(settings.historyCapacity)

            if settings.progressSaveMode == .never {
                self.player.clearPersistedPlaybackProgress()
            }
        } catch {
            
        }
    }

    func deleteAllUserData() {
        player.stop()
        playbackQueue = nil
        currentPlaylistItemID = nil
        currentPlaylistID = nil
        playbackMode = .single
        playbackErrorMessage = nil

        library.clear()
        browser.clear()
        history.clear()
        playlists.deleteAll()
        selectedFolder.clearSelection()
        selectedFolder.history.clearAll()
        pitchCycles.resetToDefault()

        settings = settingsStore.loadDefaultSettings()
        hasUnsavedSettingsChanges = false
        keybindManager.updateSettings(settings)
        player.playbackProcessingMode = settings.playbackProcessingMode
        player.audioProcessingAlgorithm = settings.audioProcessingAlgorithm
        player.speedFixEnabled = settings.speedFixEnabled
        player.progressSaveMode = settings.progressSaveMode
        history.setMaximumCount(settings.historyCapacity)
        player.resetToDefault()

        persistence.clearQueueResume()
        persistence.resetToDefault()

        do {
            try StateStore.deleteAllUserData()
        } catch {
            
        }
    }

    private func attachQueuePersistence(
        _ queue: PlaybackQueue
    ) {
        playbackQueueCurrentIndex = queue.currentIndex

        queue.onStateChange = { [weak self, weak queue] in
            guard let self, let queue else {
                return
            }

            self.playbackQueueCurrentIndex = queue.currentIndex

            if queue.source == .playlist,
               let playlistID = self.currentPlaylistID,
               let playlist = self.playlists.playlist(with: playlistID),
               playlist.items.indices.contains(queue.currentIndex) {
                self.currentPlaylistItemID =
                    playlist.items[queue.currentIndex].id
            } else {
                self.currentPlaylistItemID = nil
                self.currentPlaylistID = nil
            }

            self.persistence.saveQueueResume(
                queue.resumeSnapshot
            )
        }
    }

    private func handleDirectSelectionFailure(
        _ error: Error,
        source: QueueSource,
        url: URL
    ) {
        
        player.stop()
        playbackQueue = nil
        currentPlaylistItemID = nil
        currentPlaylistID = nil
        persistence.clearQueueResume()

        if let failure = error as? PlaybackFailure {
            switch failure {
            case .fileUnavailable:
                switch source {
                case .library:
                    library.remove(url)

                case .history:
                    history.remove(url)

                case .singleFile:
                    browser.clear()

                case .playlist:
                    break
                }

            case .playbackFailed(_, let underlyingError):
                playbackErrorMessage =
                    underlyingError.localizedDescription
            }

            return
        }

        playbackErrorMessage = error.localizedDescription
    }

    func dismissPlaybackError() {
        playbackErrorMessage = nil
    }

    private func restoreQueueResume() {
        guard let snapshot = persistence.loadQueueResume() else {
            return
        }

        guard let queue = PlaybackQueue(
            player: player,
            snapshot: snapshot,
            pitchCycleContext: pitchCyclePlaybackContext
        ) else {
            
            return
        }

        queue.playbackMode = playbackMode
        attachQueuePersistence(queue)
        playbackQueue = queue

    }

    func handleExternalFileOpen(_ url: URL) {
        pendingExternalFileURL = url
        processPendingExternalFileOpenIfReady()
    }

    private func processPendingExternalFileOpenIfReady() {
        guard isReady,
              let url = pendingExternalFileURL else {
            return
        }

        pendingExternalFileURL = nil

        guard play(url) else {
            return
        }

        externalOpenGeneration += 1
    }

    private func initialize() async {
        

        switch persistence.appState.librarySortOrder {
        case "nameDescending":
            library.sortOrder = .nameDescending
        default:
            library.sortOrder = .nameAscending
        }

        switch persistence.appState.historySortOrder {
        case "nameDescending":
            history.sortOrder = .nameDescending
        case "lastPlayedAscending":
            history.sortOrder = .lastPlayedAscending
        case "lastPlayedDescending":
            history.sortOrder = .lastPlayedDescending
        default:
            history.sortOrder = .nameAscending
        }

        switch persistence.appState.playbackMode {
        case "repeatOne":
            playbackMode = .repeatOne
        case "list":
            playbackMode = .list
        case "repeatList":
            playbackMode = .repeatList
        default:
            playbackMode = .single
        }

        player.restoreVolume(
            persistence.playerState.volume
        )

        player.restorePitch(
            persistence.playerState.pitch
        )

        player.restoreSpeed(
            persistence.playerState.speed
        )

        let hasExternalOpen = pendingExternalFileURL != nil

        if !hasExternalOpen,
           let currentTrackURL = persistence.playerState.currentTrackURL {
            do {
                try player.restoreCurrentTrack(
                    currentTrackURL,
                    playbackProgress: TimeInterval(
                        persistence.playerState.playbackProgress ?? 0
                    )
                )
            } catch {
                
            }
        }

        if let folderURL = selectedFolder.folderURL {
            await library.refresh(from: folderURL)

        
        }

        if !hasExternalOpen {
            restoreQueueResume()
        }

        isReady = true

        processPendingExternalFileOpenIfReady()

        
    }

    func play(_ track: Track) {
        currentPlaylistItemID = nil
        currentPlaylistID = nil

        pitchCycles.resetCycleForNewQueue()

        let urls = library.sortedTracks.map(\.filePath)

        guard let queue = PlaybackQueue(
            player: player,
            urls: urls,
            startingAt: track.filePath,
            source: .library,
            pitchCycleContext: pitchCyclePlaybackContext
        ) else {
            
            return
        }

        queue.playbackMode = playbackMode
        attachQueuePersistence(queue)
        playbackQueue = queue
        persistence.saveQueueResume(queue.resumeSnapshot)

        do {
            try queue.playCurrent(
                origin: .directSelection
            )

            if let currentURL = queue.currentURL {
                history.record(currentURL)
            }
        } catch {
            handleDirectSelectionFailure(
                error,
                source: .library,
                url: track.filePath
            )
        }
    }

    @discardableResult
    func play(_ url: URL) -> Bool {
        currentPlaylistItemID = nil
        currentPlaylistID = nil

        pitchCycles.resetCycleForNewQueue()

        guard let queue = PlaybackQueue(
            player: player,
            urls: [url],
            startingAt: url,
            source: .singleFile,
            pitchCycleContext: pitchCyclePlaybackContext
        ) else {
            
            return false
        }

        queue.playbackMode = playbackMode
        attachQueuePersistence(queue)
        playbackQueue = queue
        persistence.saveQueueResume(queue.resumeSnapshot)

        do {
            try queue.playCurrent(
                origin: .directSelection
            )

            if let currentURL = queue.currentURL {
                history.record(currentURL)
            }
        } catch {
            handleDirectSelectionFailure(
                error,
                source: .singleFile,
                url: url
            )
            return false
        }

        return true
    }

    func playHistory(_ url: URL) {
        currentPlaylistItemID = nil
        currentPlaylistID = nil

        guard history.validate(url) else {
            return
        }

        pitchCycles.resetCycleForNewQueue()

        let urls = history.sortedRecords.map(\.url)

        guard let queue = PlaybackQueue(
            player: player,
            urls: urls,
            startingAt: url,
            source: .history,
            pitchCycleContext: pitchCyclePlaybackContext
        ) else {
            
            return
        }

        queue.playbackMode = playbackMode
        attachQueuePersistence(queue)
        playbackQueue = queue
        persistence.saveQueueResume(queue.resumeSnapshot)

        do {
            try queue.playCurrent(
                origin: .directSelection
            )

            if let currentURL = queue.currentURL {
                history.record(currentURL)
            }

            persistence.saveQueueResume(queue.resumeSnapshot)
        } catch {
            handleDirectSelectionFailure(
                error,
                source: .history,
                url: url
            )
        }
    }


    func playPlaylistTrack(
        _ itemID: UUID,
        in playlistID: UUID
    ) {
        playlists.refresh(playlistID)

        guard let playlist = playlists.playlist(with: playlistID),
              let startingIndex = playlist.items.firstIndex(
                  where: { $0.id == itemID }
              )
        else {
            return
        }

        pitchCycles.resetCycleForNewQueue()

        let urls = playlist.items.map(\.url)

        guard let startingURL = urls.indices.contains(startingIndex)
                ? urls[startingIndex]
                : nil
        else {
            return
        }

        guard let queue = PlaybackQueue(
            player: player,
            urls: urls,
            startingAt: startingIndex,
            source: .playlist,
            pitchCycleContext: pitchCyclePlaybackContext
        ) else {
            
            return
        }

        currentPlaylistID = playlistID
        currentPlaylistItemID = itemID

        queue.playbackMode = playbackMode
        attachQueuePersistence(queue)
        playbackQueue = queue
        persistence.saveQueueResume(queue.resumeSnapshot)

        do {
            try queue.playCurrent(
                origin: .directSelection
            )

            if let currentURL = queue.currentURL {
                history.record(currentURL)
            }

            persistence.saveQueueResume(queue.resumeSnapshot)
        } catch {
            handleDirectSelectionFailure(
                error,
                source: .playlist,
                url: startingURL
            )
        }
    }

    func setLibrarySortOrder(
        _ order: Library.SortOrder
    ) {
        library.sortOrder = order

        var appState = persistence.appState

        switch order {
        case .nameAscending:
            appState.librarySortOrder = "nameAscending"
        case .nameDescending:
            appState.librarySortOrder = "nameDescending"
        }

        persistence.reportApp(appState)
    }

    func setHistorySortOrder(
        _ order: History.SortOrder
    ) {
        history.sortOrder = order

        var appState = persistence.appState

        switch order {
        case .nameAscending:
            appState.historySortOrder = "nameAscending"
        case .nameDescending:
            appState.historySortOrder = "nameDescending"
        case .lastPlayedAscending:
            appState.historySortOrder = "lastPlayedAscending"
        case .lastPlayedDescending:
            appState.historySortOrder = "lastPlayedDescending"
        }

        persistence.reportApp(appState)
    }

    func setPitchCyclesEnabled(_ enabled: Bool) {
        pitchCycles.setEnabled(enabled)

        if !isPitchCyclesPlaybackActive {
            player.setPlaybackPitchOverride(nil)
        }
    }

    func setPlaybackMode(_ mode: PlaybackMode) {
        playbackMode = mode
        playbackQueue?.playbackMode = mode

        if !isPitchCyclesPlaybackActive {
            player.setPlaybackPitchOverride(nil)
        }

        var appState = persistence.appState

        switch mode {
        case .single:
            appState.playbackMode = "single"
        case .repeatOne:
            appState.playbackMode = "repeatOne"
        case .list:
            appState.playbackMode = "list"
        case .repeatList:
            appState.playbackMode = "repeatList"
        }

        persistence.reportApp(appState)
    }

    func playPlaybackQueueIndex(_ index: Int) {
        guard let queue = playbackQueue else {
            return
        }

        _ = queue.select(index: index)
    }

    private func advanceAfterPlaybackGap() {
        guard let queue = playbackQueue else {
            return
        }

        do {
            try queue.playbackReachedEnd()
        } catch {
            
        }
    }

    private func cancelPendingPlaybackGap() {
        playbackGapTask?.cancel()
        playbackGapTask = nil
    }

    func next() {
        cancelPendingPlaybackGap()

        guard let queue = playbackQueue else {
            return
        }

        if isPitchCyclesPlaybackActive {
            pitchCycles.nextCycle()

            do {
                try queue.playCurrent(
                    origin: .navigation
                )
            } catch {
                
            }

            return
        }

        queue.next()
    }

    func handleF7PreviousTrack() {
        guard let queue = playbackQueue else {
            return
        }

        if player.currentPlaybackPosition <= 10.0 {
            previous()
            return
        }

        player.seek(to: 0.0)
        persistence.saveQueueResume(queue.resumeSnapshot)
    }

    func previous() {
        cancelPendingPlaybackGap()

        guard let queue = playbackQueue else {
            return
        }

        if isPitchCyclesPlaybackActive {
            pitchCycles.previousCycle()

            do {
                try queue.playCurrent(
                    origin: .navigation
                )
            } catch {
                
            }

            return
        }

        queue.previous()
    }

}
