import Foundation

enum TrackGap: Double, Codable, Equatable, CaseIterable {
    case none = 0.0
    case oneSecond = 1.0
    case threeSeconds = 3.0
    case fiveSeconds = 5.0
    case tenSeconds = 10.0

    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .oneSecond:
            return "1 S"
        case .threeSeconds:
            return "3 S"
        case .fiveSeconds:
            return "5 S"
        case .tenSeconds:
            return "10 S"
        }
    }
}

struct SettingsState: Codable, Equatable {

    var playbackProcessingMode: PlaybackProcessingMode

    var audioProcessingAlgorithm: AudioProcessingAlgorithm

    var trackGap: TrackGap

    var speedFixEnabled: Bool

    var progressSaveMode: ProgressSaveMode

    var historyCapacity: Int

    var quickSearchEnabled: Bool
    var quickSearchCaseSensitive: Bool

    var quickKeysEnabled: Bool

    var arrowKeySeekingEnabled: Bool
    var seekStep: SeekStep

    var quickTrackNavigationEnabled: Bool

    var f7RestartBehaviorEnabled: Bool

    var quickPlayPauseEnabled: Bool

    var mouseSideButtonsEnabled: Bool
    var mouseSideButtonsReversed: Bool
    var shiftF7F9SideButtonsEnabled: Bool

    var mouseSideButtonAction: MouseSideButtonAction

    var pitchAdjustmentAccuracy: PitchAdjustmentAccuracy

    var speedAdjustmentStep: Double

    var volumeAdjustmentStep: Double

    var allowDuplicatePlaylistItems: Bool

    var playlistEscapeNavigationEnabled: Bool

    static let `default` = SettingsState(
        playbackProcessingMode: .processed,
        audioProcessingAlgorithm: .systemTimePitch,
        trackGap: .none,
        speedFixEnabled: true,
        progressSaveMode: .everySecond,
        historyCapacity: 10,
        quickSearchEnabled: false,
        quickSearchCaseSensitive: false,
        quickKeysEnabled: true,
        arrowKeySeekingEnabled: false,
        seekStep: .fiveSeconds,
        quickTrackNavigationEnabled: true,
        f7RestartBehaviorEnabled: false,
        quickPlayPauseEnabled: true,
        mouseSideButtonsEnabled: false,
        mouseSideButtonsReversed: false,
        shiftF7F9SideButtonsEnabled: false,
        mouseSideButtonAction: .pitch,
        pitchAdjustmentAccuracy: .semitone,
        speedAdjustmentStep: 0.10,
        volumeAdjustmentStep: 0.05,
        allowDuplicatePlaylistItems: false,
        playlistEscapeNavigationEnabled: false,
    )

    private enum CodingKeys: String, CodingKey {
        case playbackProcessingMode
        case audioProcessingAlgorithm
        case trackGap
        case speedFixEnabled
        case progressSaveMode
        case historyCapacity
        case quickSearchEnabled
        case quickSearchCaseSensitive
        case quickKeysEnabled
        case arrowKeySeekingEnabled
        case seekStep
        case quickTrackNavigationEnabled
        case f7RestartBehaviorEnabled
        case quickPlayPauseEnabled
        case mouseSideButtonsReversed
        case shiftF7F9SideButtonsEnabled
        case mouseSideButtonsEnabled
        case mouseSideButtonAction
        case pitchAdjustmentAccuracy
        case speedAdjustmentStep
        case volumeAdjustmentStep
        case allowDuplicatePlaylistItems
        case playlistEscapeNavigationEnabled
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case commandF7F9SideButtonsEnabled
    }

    init(
        playbackProcessingMode: PlaybackProcessingMode,
        audioProcessingAlgorithm: AudioProcessingAlgorithm,
        trackGap: TrackGap,
        speedFixEnabled: Bool,
        progressSaveMode: ProgressSaveMode,
        historyCapacity: Int,
        quickSearchEnabled: Bool,
        quickSearchCaseSensitive: Bool,
        quickKeysEnabled: Bool,
        arrowKeySeekingEnabled: Bool,
        seekStep: SeekStep,
        quickTrackNavigationEnabled: Bool,
        f7RestartBehaviorEnabled: Bool,
        quickPlayPauseEnabled: Bool,
        mouseSideButtonsEnabled: Bool,
        mouseSideButtonsReversed: Bool,
        shiftF7F9SideButtonsEnabled: Bool,
        mouseSideButtonAction: MouseSideButtonAction,
        pitchAdjustmentAccuracy: PitchAdjustmentAccuracy,
        speedAdjustmentStep: Double,
        volumeAdjustmentStep: Double,
        allowDuplicatePlaylistItems: Bool,
        playlistEscapeNavigationEnabled: Bool,
    ) {
        self.playbackProcessingMode = playbackProcessingMode
        self.audioProcessingAlgorithm = audioProcessingAlgorithm
        self.trackGap = trackGap
        self.speedFixEnabled = speedFixEnabled
        self.progressSaveMode = progressSaveMode
        self.historyCapacity = historyCapacity
        self.quickSearchEnabled = quickSearchEnabled
        self.quickSearchCaseSensitive = quickSearchCaseSensitive
        self.quickKeysEnabled = quickKeysEnabled
        self.arrowKeySeekingEnabled = arrowKeySeekingEnabled
        self.seekStep = seekStep
        self.quickTrackNavigationEnabled = quickTrackNavigationEnabled
        self.f7RestartBehaviorEnabled = f7RestartBehaviorEnabled
        self.quickPlayPauseEnabled = quickPlayPauseEnabled
        self.mouseSideButtonsEnabled = mouseSideButtonsEnabled
        self.mouseSideButtonsReversed = mouseSideButtonsReversed
        self.shiftF7F9SideButtonsEnabled = shiftF7F9SideButtonsEnabled
        self.mouseSideButtonAction = mouseSideButtonAction
        self.pitchAdjustmentAccuracy = pitchAdjustmentAccuracy
        self.speedAdjustmentStep = speedAdjustmentStep
        self.volumeAdjustmentStep = volumeAdjustmentStep
        self.allowDuplicatePlaylistItems = allowDuplicatePlaylistItems
        self.playlistEscapeNavigationEnabled = playlistEscapeNavigationEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        playbackProcessingMode = try container.decode(
            PlaybackProcessingMode.self,
            forKey: .playbackProcessingMode
        )

        audioProcessingAlgorithm = try container.decodeIfPresent(
            AudioProcessingAlgorithm.self,
            forKey: .audioProcessingAlgorithm
        ) ?? .systemTimePitch

        trackGap = try container.decodeIfPresent(
            TrackGap.self,
            forKey: .trackGap
        ) ?? .none

        speedFixEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .speedFixEnabled
        ) ?? false

        progressSaveMode = try container.decode(
            ProgressSaveMode.self,
            forKey: .progressSaveMode
        )

        historyCapacity = try container.decode(
            Int.self,
            forKey: .historyCapacity
        )

        quickSearchEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .quickSearchEnabled
        ) ?? false

        quickSearchCaseSensitive = try container.decodeIfPresent(
            Bool.self,
            forKey: .quickSearchCaseSensitive
        ) ?? false

        quickKeysEnabled = try container.decode(
            Bool.self,
            forKey: .quickKeysEnabled
        )

        arrowKeySeekingEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .arrowKeySeekingEnabled
        ) ?? false

        seekStep = try container.decodeIfPresent(
            SeekStep.self,
            forKey: .seekStep
        ) ?? .fiveSeconds

        quickTrackNavigationEnabled = try container.decode(
            Bool.self,
            forKey: .quickTrackNavigationEnabled
        )

        f7RestartBehaviorEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .f7RestartBehaviorEnabled
        ) ?? false

        quickPlayPauseEnabled = try container.decode(
            Bool.self,
            forKey: .quickPlayPauseEnabled
        )

        mouseSideButtonsEnabled = try container.decode(
            Bool.self,
            forKey: .mouseSideButtonsEnabled
        )

        mouseSideButtonsReversed = try container.decodeIfPresent(
            Bool.self,
            forKey: .mouseSideButtonsReversed
        ) ?? false

        if let value = try container.decodeIfPresent(
            Bool.self,
            forKey: .shiftF7F9SideButtonsEnabled
        ) {
            shiftF7F9SideButtonsEnabled = value
        } else {
            let legacyContainer = try decoder.container(
                keyedBy: LegacyCodingKeys.self
            )
            shiftF7F9SideButtonsEnabled =
                try legacyContainer.decodeIfPresent(
                    Bool.self,
                    forKey: .commandF7F9SideButtonsEnabled
                ) ?? false
        }

        mouseSideButtonAction = try container.decodeIfPresent(
            MouseSideButtonAction.self,
            forKey: .mouseSideButtonAction
        ) ?? .pitch

        pitchAdjustmentAccuracy = try container.decodeIfPresent(
            PitchAdjustmentAccuracy.self,
            forKey: .pitchAdjustmentAccuracy
        ) ?? .semitone

        speedAdjustmentStep = try container.decodeIfPresent(
            Double.self,
            forKey: .speedAdjustmentStep
        ) ?? 0.10

        volumeAdjustmentStep = try container.decodeIfPresent(
            Double.self,
            forKey: .volumeAdjustmentStep
        ) ?? 0.05

        allowDuplicatePlaylistItems = try container.decodeIfPresent(
            Bool.self,
            forKey: .allowDuplicatePlaylistItems
        ) ?? false

        playlistEscapeNavigationEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .playlistEscapeNavigationEnabled
        ) ?? false
    }
}
