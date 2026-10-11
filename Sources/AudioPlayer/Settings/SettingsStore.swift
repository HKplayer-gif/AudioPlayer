import Foundation

private struct LegacySettingsState: Codable {
    var playbackProcessingMode: PlaybackProcessingMode
    var progressSaveMode: ProgressSaveMode
    var historyCapacity: Int
    var trackNavigationKeybindEnabled: Bool
    var playPauseKeybindEnabled: Bool
    var pitchAdjustmentKeybindEnabled: Bool
}

final class SettingsStore {

    private let userSettingsFileName = "User Settings.json"

    private var userSettingsURL: URL {
        StateStore.userDataDirectoryURL
            .appendingPathComponent(userSettingsFileName)
    }

    private var legacyUserSettingsURL: URL {
        StateStore.userDataDirectoryURL
            .deletingLastPathComponent()
            .appendingPathComponent(userSettingsFileName)
    }

    func loadDefaultSettings() -> SettingsState {
        let url = defaultSettingsResourceURL()

        guard let url else {
            
            return .default
        }

        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(
                  SettingsState.self,
                  from: data
              ) else {
            
            return .default
        }

        return settings
    }

    /// Resolve bundled defaults without touching SwiftPM's generated Bundle.module
    /// accessor. That accessor embeds an absolute .build path as a fallback, which
    /// is unavailable after distribution and can trap during static initialization.
    private func defaultSettingsResourceURL() -> URL? {
        let fileManager = FileManager.default
        let bundleName = "AudioPlayer_AudioPlayer.bundle"
        var candidateBundleURLs: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidateBundleURLs.append(
                resourceURL.appendingPathComponent(bundleName, isDirectory: true)
            )
        }

        candidateBundleURLs.append(
            Bundle.main.bundleURL.appendingPathComponent(bundleName, isDirectory: true)
        )

        if let executablePath = CommandLine.arguments.first, !executablePath.isEmpty {
            let executableDirectory = URL(fileURLWithPath: executablePath)
                .standardizedFileURL
                .deletingLastPathComponent()
            candidateBundleURLs.append(
                executableDirectory.appendingPathComponent(bundleName, isDirectory: true)
            )
        }

        for bundleURL in candidateBundleURLs {
            guard fileManager.fileExists(atPath: bundleURL.path),
                  let bundle = Bundle(url: bundleURL),
                  let resourceURL = bundle.url(
                      forResource: "Default Settings",
                      withExtension: "json"
                  ) else {
                continue
            }
            return resourceURL
        }

        return Bundle.main.url(
            forResource: "Default Settings",
            withExtension: "json"
        )
    }

    func loadUserSettings() -> SettingsState? {
        let data: Data

        if let currentData = try? Data(contentsOf: userSettingsURL) {
            data = currentData
        } else if let legacyData = try? Data(contentsOf: legacyUserSettingsURL) {
            data = legacyData

            do {
                try FileManager.default.createDirectory(
                    at: userSettingsURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try legacyData.write(to: userSettingsURL, options: .atomic)
                try FileManager.default.removeItem(at: legacyUserSettingsURL)
            } catch {
                
            }
        } else {
            return nil
        }

        if let settings = try? JSONDecoder().decode(
            SettingsState.self,
            from: data
        ) {
            return settings
        }

        guard let legacy = try? JSONDecoder().decode(
            LegacySettingsState.self,
            from: data
        ) else {
            return nil
        }

        return SettingsState(
            playbackProcessingMode: legacy.playbackProcessingMode,
            audioProcessingAlgorithm: .systemTimePitch,
            trackGap: .none,
            speedFixEnabled: false,
            progressSaveMode: legacy.progressSaveMode,
            historyCapacity: legacy.historyCapacity,
            quickSearchEnabled: false,
            quickSearchCaseSensitive: false,
            quickKeysEnabled: true,
            arrowKeySeekingEnabled: false,
            seekStep: .fiveSeconds,
            quickTrackNavigationEnabled:
                legacy.trackNavigationKeybindEnabled,
            f7RestartBehaviorEnabled: false,
            quickPlayPauseEnabled:
                legacy.playPauseKeybindEnabled,
            mouseSideButtonsEnabled:
                false,
            mouseSideButtonsReversed:
                false,
            shiftF7F9SideButtonsEnabled:
                false,
            mouseSideButtonAction: .pitch,
            pitchAdjustmentAccuracy: .semitone,
            speedAdjustmentStep: 0.10,
            volumeAdjustmentStep: 0.05,
            allowDuplicatePlaylistItems: false,
            playlistEscapeNavigationEnabled: false,
        )
    }

    func saveUserSettings(_ settings: SettingsState) throws {
        let directoryURL = userSettingsURL.deletingLastPathComponent()

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(settings)

        try data.write(
            to: userSettingsURL,
            options: .atomic
        )
    }
}
