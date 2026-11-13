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

    var bpmKeyEnabled: Bool
    var screenEffectEnabled: Bool
    var showEffectToggleStateInCurrentPlayingTab: Bool
    var screenEffectStrength: Double
    var screenEffectHoldDuration: Double
    var screenEffectFadeInDuration: Double
    var screenEffectFadeOutDuration: Double
    var screenEffectBeatRateMultiplier: Double
    var screenEffectRedMultiplier: Double
    var screenEffectGreenMultiplier: Double
    var screenEffectBlueMultiplier: Double
    var screenEffectTriggerKeyCode: UInt32
    var screenEffectTriggerKeyLabel: String
    var screenEffectTriggerShift: Bool

    static let screenEffectBeatRateOptions: [Double] = [
        0.125, 0.25, 0.5, 1.0, 2.0, 4.0
    ]

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
        bpmKeyEnabled: false,
        screenEffectEnabled: false,
        showEffectToggleStateInCurrentPlayingTab: false,
        screenEffectStrength: 1.1,
        screenEffectHoldDuration: 0.1,
        screenEffectFadeInDuration: 0.1,
        screenEffectFadeOutDuration: 0.5,
        screenEffectBeatRateMultiplier: 1.0,
        screenEffectRedMultiplier: 1.0,
        screenEffectGreenMultiplier: 1.0,
        screenEffectBlueMultiplier: 1.0,
        screenEffectTriggerKeyCode: 28,
        screenEffectTriggerKeyLabel: "8",
        screenEffectTriggerShift: false,
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
        case bpmKeyEnabled
        case screenEffectEnabled
        case showEffectToggleStateInCurrentPlayingTab
        case screenEffectStrength
        case screenEffectHoldDuration
        case screenEffectFadeInDuration
        case screenEffectFadeOutDuration
        case screenEffectBeatRateMultiplier
        case screenEffectRedMultiplier
        case screenEffectGreenMultiplier
        case screenEffectBlueMultiplier
        case screenEffectTriggerKeyCode
        case screenEffectTriggerKeyLabel
        case screenEffectTriggerShift
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case commandF7F9SideButtonsEnabled
        case screenEffectRedChannelEnabled
        case screenEffectGreenChannelEnabled
        case screenEffectBlueChannelEnabled
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
        bpmKeyEnabled: Bool = false,
        screenEffectEnabled: Bool = false,
        showEffectToggleStateInCurrentPlayingTab: Bool = false,
        screenEffectStrength: Double = 1.1,
        screenEffectHoldDuration: Double = 0.1,
        screenEffectFadeInDuration: Double = 0.1,
        screenEffectFadeOutDuration: Double = 0.5,
        screenEffectBeatRateMultiplier: Double = 1.0,
        screenEffectRedMultiplier: Double = 1.0,
        screenEffectGreenMultiplier: Double = 1.0,
        screenEffectBlueMultiplier: Double = 1.0,
        screenEffectTriggerKeyCode: UInt32 = 28,
        screenEffectTriggerKeyLabel: String = "8",
        screenEffectTriggerShift: Bool = false,
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
        self.bpmKeyEnabled = bpmKeyEnabled
        self.screenEffectEnabled = screenEffectEnabled && bpmKeyEnabled
        self.showEffectToggleStateInCurrentPlayingTab = showEffectToggleStateInCurrentPlayingTab
        self.screenEffectStrength = min(max(screenEffectStrength, 0.75), 2.0)
        self.screenEffectHoldDuration = min(max((screenEffectHoldDuration * 10).rounded() / 10, 0.0), 10.0)
        self.screenEffectFadeInDuration = min(max((screenEffectFadeInDuration * 10).rounded() / 10, 0.0), 1.0)
        self.screenEffectFadeOutDuration = min(max((screenEffectFadeOutDuration * 10).rounded() / 10, 0.0), 10.0)
        self.screenEffectBeatRateMultiplier = Self.screenEffectBeatRateOptions.min {
            abs($0 - screenEffectBeatRateMultiplier) < abs($1 - screenEffectBeatRateMultiplier)
        } ?? 1.0
        self.screenEffectRedMultiplier = min(max((screenEffectRedMultiplier * 100).rounded() / 100, 0.0), 1.0)
        self.screenEffectGreenMultiplier = min(max((screenEffectGreenMultiplier * 100).rounded() / 100, 0.0), 1.0)
        self.screenEffectBlueMultiplier = min(max((screenEffectBlueMultiplier * 100).rounded() / 100, 0.0), 1.0)
        self.screenEffectTriggerKeyCode = screenEffectTriggerKeyCode
        self.screenEffectTriggerKeyLabel = screenEffectTriggerKeyLabel
        self.screenEffectTriggerShift = screenEffectTriggerShift
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

        bpmKeyEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .bpmKeyEnabled
        ) ?? false

        screenEffectEnabled = (try container.decodeIfPresent(
            Bool.self,
            forKey: .screenEffectEnabled
        ) ?? false) && bpmKeyEnabled

        showEffectToggleStateInCurrentPlayingTab = try container.decodeIfPresent(
            Bool.self,
            forKey: .showEffectToggleStateInCurrentPlayingTab
        ) ?? false

        screenEffectStrength = min(max(try container.decodeIfPresent(
            Double.self,
            forKey: .screenEffectStrength
        ) ?? 1.1, 0.75), 2.0)

        screenEffectHoldDuration = min(max(((try container.decodeIfPresent(
            Double.self,
            forKey: .screenEffectHoldDuration
        ) ?? 0.1) * 10).rounded() / 10, 0.0), 10.0)

        screenEffectFadeInDuration = min(max(((try container.decodeIfPresent(
            Double.self,
            forKey: .screenEffectFadeInDuration
        ) ?? 0.1) * 10).rounded() / 10, 0.0), 1.0)

        screenEffectFadeOutDuration = min(max(((try container.decodeIfPresent(
            Double.self,
            forKey: .screenEffectFadeOutDuration
        ) ?? 0.5) * 10).rounded() / 10, 0.0), 10.0)

        let storedBeatRateMultiplier = try container.decodeIfPresent(
            Double.self,
            forKey: .screenEffectBeatRateMultiplier
        ) ?? 1.0
        screenEffectBeatRateMultiplier = Self.screenEffectBeatRateOptions.min {
            abs($0 - storedBeatRateMultiplier) < abs($1 - storedBeatRateMultiplier)
        } ?? 1.0

        let legacyChannelSettings = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let legacyRedEnabled = try legacyChannelSettings.decodeIfPresent(Bool.self, forKey: .screenEffectRedChannelEnabled) ?? true
        let legacyGreenEnabled = try legacyChannelSettings.decodeIfPresent(Bool.self, forKey: .screenEffectGreenChannelEnabled) ?? true
        let legacyBlueEnabled = try legacyChannelSettings.decodeIfPresent(Bool.self, forKey: .screenEffectBlueChannelEnabled) ?? true
        screenEffectRedMultiplier = min(max(((try container.decodeIfPresent(Double.self, forKey: .screenEffectRedMultiplier) ?? (legacyRedEnabled ? 1.0 : 0.0)) * 100).rounded() / 100, 0.0), 1.0)
        screenEffectGreenMultiplier = min(max(((try container.decodeIfPresent(Double.self, forKey: .screenEffectGreenMultiplier) ?? (legacyGreenEnabled ? 1.0 : 0.0)) * 100).rounded() / 100, 0.0), 1.0)
        screenEffectBlueMultiplier = min(max(((try container.decodeIfPresent(Double.self, forKey: .screenEffectBlueMultiplier) ?? (legacyBlueEnabled ? 1.0 : 0.0)) * 100).rounded() / 100, 0.0), 1.0)

        screenEffectTriggerKeyCode = try container.decodeIfPresent(
            UInt32.self,
            forKey: .screenEffectTriggerKeyCode
        ) ?? 28

        screenEffectTriggerKeyLabel = try container.decodeIfPresent(
            String.self,
            forKey: .screenEffectTriggerKeyLabel
        ) ?? "8"

        screenEffectTriggerShift = try container.decodeIfPresent(
            Bool.self,
            forKey: .screenEffectTriggerShift
        ) ?? false
    }
}
