import Foundation
import AVFAudio
import CoreAudio
import Observation
import SoundTouchPlayback
import SignalsmithPlayback

private final class WeakPlayerBox: @unchecked Sendable {
    weak var player: Player?

    init(_ player: Player) {
        self.player = player
    }
}

@Observable
final class Player {

    private enum ActivePipeline {
        case native
        case system
        case soundTouch
        case signalsmith
    }

    private var activePipeline: ActivePipeline = .native

    enum PlaybackState {
        case stopped
        case playing
        case paused
    }

    private let engine = AVAudioEngine()
    @ObservationIgnored private var engineConfigurationObserver: NSObjectProtocol?
    @ObservationIgnored private var defaultOutputDeviceListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var deviceListListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var routeChangeDebounceWorkItem: DispatchWorkItem?
    @ObservationIgnored private var isHandlingEngineConfigurationChange = false
    private let playerNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()

    private let speedFixPlayerNodeB = AVAudioPlayerNode()
    private let speedFixTimePitchB = AVAudioUnitTimePitch()
    private let speedFixLaneMixerA = AVAudioMixerNode()
    private let speedFixLaneMixerB = AVAudioMixerNode()
    private var speedFixActiveLane = 0

    private let soundTouchPlayerNode = AVAudioPlayerNode()
    private let soundTouchMixer = AVAudioMixerNode()
    private var soundTouchSession: SoundTouchStreamSession?
    private var soundTouchGeneration: UInt64 = 0
    private var soundTouchScheduledBuffers = 0
    private var soundTouchSourceEnded = false
    private var soundTouchSourceStartPosition: TimeInterval = 0.0
    private var soundTouchPlaybackSpeed: Double = 1.0

    private let signalsmithPlayerNode = AVAudioPlayerNode()
    private let signalsmithMixer = AVAudioMixerNode()
    private var signalsmithSession: SignalsmithStreamSession?
    private var signalsmithGeneration: UInt64 = 0
    private var signalsmithScheduledBuffers = 0
    private var signalsmithSourceEnded = false
    private var signalsmithSourceStartPosition: TimeInterval = 0.0
    private var signalsmithPlaybackSpeed: Double = 1.0
    private var signalsmithShouldPlay = false

    var speedFixEnabled: Bool = false {
        didSet {
            guard oldValue != speedFixEnabled else {
                return
            }
            applySpeedFixModeChange()
        }
    }

    private var audioFile: AVAudioFile?
    private var playbackPitchOverride: Double?

    private var playbackPositionOffset: TimeInterval = 0.0
    private var lastKnownPlaybackPosition: TimeInterval = 0.0
    private var lastSavedPlaybackSecond: Int?
    private var playbackScheduleGeneration: UInt64 = 0
    private var isRestoringPersistentState = false

    // Temporary default until Settings provides the user's selected mode.
    var progressSaveMode: ProgressSaveMode = .everySecond
    var playbackProcessingMode: PlaybackProcessingMode = .processed {
        didSet {
            guard oldValue != playbackProcessingMode else { return }
            applyPlaybackProcessingModeChange()
        }
    }
    var audioProcessingAlgorithm: AudioProcessingAlgorithm = .systemTimePitch {
        didSet {
            guard oldValue != audioProcessingAlgorithm else { return }
            applyAudioProcessingAlgorithmChange()
        }
    }

    private(set) var playbackState: PlaybackState = .stopped {
        didSet {
            onPlaybackStateChange?(playbackState)
        }
    }
    private(set) var currentTrackURL: URL?
    private(set) var currentTrackDuration: TimeInterval = 0.0

    var currentPlaybackPosition: TimeInterval {
        lastKnownPlaybackPosition
    }

    var onPersistentStateChange: ((PlayerState) -> Void)?
    var onPlaybackStateChange: ((PlaybackState) -> Void)?
    var onPlaybackEnded: (() -> Void)?

    var volume: Double = 1.0 {
        didSet {
            updateVolume()
            reportPersistentState()
        }
    }

    var pitch: Double = 0.0 {
        didSet {
            updatePitch()
            reportPersistentState()
        }
    }

    var speed: Double = 1.0 {
        didSet {
            updateSpeed()

            reportPersistentState()
        }
    }

    init() {

        engine.attach(playerNode)
        engine.attach(timePitch)
        engine.attach(speedFixPlayerNodeB)
        engine.attach(speedFixTimePitchB)
        engine.attach(speedFixLaneMixerA)
        engine.attach(speedFixLaneMixerB)
        engine.attach(soundTouchPlayerNode)
        engine.attach(soundTouchMixer)
        engine.attach(signalsmithPlayerNode)
        engine.attach(signalsmithMixer)

        engine.connect(playerNode, to: timePitch, format: nil)
        engine.connect(timePitch, to: speedFixLaneMixerA, format: nil)
        engine.connect(speedFixLaneMixerA, to: engine.mainMixerNode, format: nil)

        engine.connect(speedFixPlayerNodeB, to: speedFixTimePitchB, format: nil)
        engine.connect(speedFixTimePitchB, to: speedFixLaneMixerB, format: nil)
        engine.connect(speedFixLaneMixerB, to: engine.mainMixerNode, format: nil)
        engine.connect(soundTouchPlayerNode, to: soundTouchMixer, format: nil)
        engine.connect(soundTouchMixer, to: engine.mainMixerNode, format: nil)
        engine.connect(signalsmithPlayerNode, to: signalsmithMixer, format: nil)
        engine.connect(signalsmithMixer, to: engine.mainMixerNode, format: nil)

        speedFixLaneMixerA.outputVolume = 1.0
        speedFixLaneMixerB.outputVolume = 0.0
        soundTouchMixer.outputVolume = 0.0
        signalsmithMixer.outputVolume = 0.0

        updateVolume()
        updatePitch()
        updateSpeed()

        let playerBox = WeakPlayerBox(self)
        engineConfigurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { _ in
            playerBox.player?.scheduleOutputRouteRecovery()
        }

        var outputDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let outputDeviceListener: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async {
                playerBox.player?.scheduleOutputRouteRecovery()
            }
        }
        let listenerStatus = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &outputDeviceAddress,
            DispatchQueue.main,
            outputDeviceListener
        )
        if listenerStatus == noErr {
            defaultOutputDeviceListener = outputDeviceListener
        }

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let deviceListListener: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async {
                playerBox.player?.scheduleOutputRouteRecovery()
            }
        }
        let devicesStatus = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            DispatchQueue.main,
            deviceListListener
        )
        if devicesStatus == noErr {
            self.deviceListListener = deviceListListener
        }
    }

    deinit {
        if let deviceListListener {
            var devicesAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &devicesAddress,
                DispatchQueue.main,
                deviceListListener
            )
        }
        if let defaultOutputDeviceListener {
            var outputDeviceAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &outputDeviceAddress,
                DispatchQueue.main,
                defaultOutputDeviceListener
            )
        }
        if let engineConfigurationObserver {
            NotificationCenter.default.removeObserver(engineConfigurationObserver)
        }
    }

    private func scheduleOutputRouteRecovery() {
        routeChangeDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.handleAudioEngineConfigurationChange()
        }
        routeChangeDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    private func handleAudioEngineConfigurationChange() {
        guard !isHandlingEngineConfigurationChange,
              let file = audioFile else {
            return
        }

        let previousState = playbackState
        guard previousState == .playing || previousState == .paused else {
            return
        }

        isHandlingEngineConfigurationChange = true
        defer { isHandlingEngineConfigurationChange = false }

        let position = currentPlaybackPosition(
            shouldAutoSave: false,
            detectPlaybackEnd: false
        ) ?? lastKnownPlaybackPosition
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else {
            playbackState = .paused
            return
        }

        let duration = Double(file.length) / sampleRate
        let safePosition = min(max(position, 0.0), max(duration - 0.001, 0.0))
        let shouldPlay = previousState == .playing
        let recoverySpeedFixLane = speedFixActiveLane

        // Stop and invalidate every route before rebuilding the selected one.
        // The native AVAudioUnitTimePitch route is restored through the same
        // node/processor reset and lane activation routine used by Speed Fix.
        stopSpeedFixLanes()
        stopSoundTouchPlayback()
        stopSignalsmithPlayback()
        engine.stop()

        playbackPositionOffset = safePosition
        lastKnownPlaybackPosition = safePosition

        do {
            if playbackProcessingMode == .native {
                try startNativePlayback(file: file, position: safePosition, shouldPlay: shouldPlay)
                if !shouldPlay { playbackState = .paused }
                return
            }

            if audioProcessingAlgorithm == .soundTouch {
                try startSoundTouchPlayback(
                    file: file,
                    position: safePosition,
                    shouldPlay: shouldPlay
                )
                if !shouldPlay { playbackState = .paused }
                return
            }

            if audioProcessingAlgorithm == .signalsmith {
                try startSignalsmithPlayback(
                    file: file,
                    position: safePosition,
                    shouldPlay: shouldPlay
                )
                if !shouldPlay { playbackState = .paused }
                return
            }

            // Engine startup and AVAudioUnitTimePitch lane restoration are
            // deliberately separate: the engine must be running before the
            // selected native node is reset, scheduled, and activated.
            try configurePlaybackGraph(for: file)
            guard engine.isRunning else {
                throw NSError(
                    domain: "AudioPlayer.RouteRecovery",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Audio engine did not restart"]
                )
            }

            let targetFrame = AVAudioFramePosition(safePosition * sampleRate)
            guard targetFrame < file.length else {
                playbackState = .stopped
                lastKnownPlaybackPosition = duration
                savePlaybackProgressImmediately()
                onPlaybackEnded?()
                return
            }

            let lane = speedFixEnabled ? recoverySpeedFixLane : 0
            try startSpeedFixLane(
                lane: lane,
                file: file,
                position: safePosition,
                shouldPlay: shouldPlay
            )

            // Unlike Speed Fix mode, ordinary AVAudio playback must keep the
            // native lane available while paused so resume() can simply play
            // the already-scheduled player node.
            if !speedFixEnabled {
                speedFixLaneMixerA.outputVolume = 1.0
                speedFixLaneMixerB.outputVolume = 0.0
            }

            playbackState = shouldPlay ? .playing : .paused
        } catch {
            // Never claim playback is active if the engine could not be rebuilt.
            playbackState = .paused
        }
    }

    private func reportPersistentState(
        playbackProgress: Int? = nil
    ) {
        guard !isRestoringPersistentState else {
            return
        }

        onPersistentStateChange?(
            PlayerState(
                volume: volume,
                pitch: pitch,
                speed: speed,
                currentTrackURL: currentTrackURL,
                playbackProgress: playbackProgress
                    ?? lastSavedPlaybackSecond
                    ?? 0
            )
        )
    }

    private func savePlaybackProgressImmediately() {
        guard progressSaveMode != .never else {
            return
        }

        let second = Int(
            min(
                max(lastKnownPlaybackPosition, 0.0),
                currentTrackDuration
            )
        )

        lastSavedPlaybackSecond = second

        reportPersistentState(
            playbackProgress: second
        )
    }

    private func reportPlaybackProgressIfNeeded(
        previousPosition: TimeInterval
    ) {
        guard progressSaveMode != .never else {
            return
        }

        let currentSecond = Int(
            min(
                max(lastKnownPlaybackPosition, 0.0),
                currentTrackDuration
            )
        )

        let previousSecond = Int(
            min(
                max(previousPosition, 0.0),
                currentTrackDuration
            )
        )

        guard currentSecond > previousSecond else {
            return
        }

        let milestone: Int

        switch progressSaveMode {
        case .never:
            return

        case .everySecond:
            milestone = 1

        case .everyFiveSeconds:
            milestone = 5

        case .everyTenSeconds:
            milestone = 10
        }

        let crossedMilestone = (previousSecond / milestone) <
            (currentSecond / milestone)

        guard crossedMilestone else {
            return
        }

        let savedMilestoneSecond =
            (currentSecond / milestone) * milestone

        guard savedMilestoneSecond > 0 else {
            return
        }

        guard savedMilestoneSecond != lastSavedPlaybackSecond else {
            return
        }

        lastSavedPlaybackSecond = savedMilestoneSecond

        reportPersistentState(
            playbackProgress: savedMilestoneSecond
        )
    }

    func restoreVolume(_ value: Double) {
        isRestoringPersistentState = true
        volume = min(max(value, 0.0), 1.0)
        isRestoringPersistentState = false
    }

    func restorePitch(_ value: Double) {
        isRestoringPersistentState = true
        pitch = min(max(value, -12.0), 12.0)
        isRestoringPersistentState = false
    }

    func restoreSpeed(_ value: Double) {
        isRestoringPersistentState = true
        speed = min(max(value, 0.1), 3.0)
        isRestoringPersistentState = false
    }

    // MARK: - Parameter Adjustment

    enum AdjustmentDirection {
        case down
        case up
    }

    private func nextAdjustmentAnchor(
        current: Double,
        lowerBound: Double,
        upperBound: Double,
        step: Double,
        direction: AdjustmentDirection
    ) -> Double {
        precondition(step > 0.0)

        let relative = (current - lowerBound) / step
        let tolerance = 1e-9

        let lowerIndex = floor(relative + tolerance)
        let upperIndex = ceil(relative - tolerance)

        let targetIndex: Double

        switch direction {
        case .down:
            if abs(relative - lowerIndex) <= tolerance {
                targetIndex = lowerIndex - 1.0
            } else {
                targetIndex = lowerIndex
            }

        case .up:
            if abs(relative - upperIndex) <= tolerance {
                targetIndex = upperIndex + 1.0
            } else {
                targetIndex = upperIndex
            }
        }

        let value = lowerBound + targetIndex * step

        return min(
            max(value, lowerBound),
            upperBound
        )
    }

    func setPlaybackPitchOverride(_ value: Double?) {
        playbackPitchOverride = value
        updatePitch()
    }

    @discardableResult
    func adjustPitch(
        direction: AdjustmentDirection,
        accuracy: PitchAdjustmentAccuracy
    ) -> Bool {
        guard playbackProcessingMode == .processed else {
            return false
        }

        let step: Double

        switch accuracy {
        case .semitone:
            step = 1.0

        case .tenth:
            step = 0.1

        case .hundredth:
            step = 0.01
        }

        pitch = nextAdjustmentAnchor(
            current: pitch,
            lowerBound: -12.0,
            upperBound: 12.0,
            step: step,
            direction: direction
        )

        return true
    }

    @discardableResult
    func adjustSpeed(
        direction: AdjustmentDirection,
        step: Double
    ) -> Bool {
        guard playbackProcessingMode == .processed else {
            return false
        }

        speed = nextAdjustmentAnchor(
            current: speed,
            lowerBound: 0.1,
            upperBound: 3.0,
            step: step,
            direction: direction
        )

        return true
    }

    @discardableResult
    func adjustVolume(
        direction: AdjustmentDirection,
        step: Double
    ) -> Bool {
        volume = nextAdjustmentAnchor(
            current: volume,
            lowerBound: 0.0,
            upperBound: 1.0,
            step: step,
            direction: direction
        )

        return true
    }

    // Temporary compatibility wrappers.
    // These remain until AppController is switched to the anchor-based API.

    @discardableResult
    func adjustPitch(by amount: Double) -> Bool {
        guard amount != 0.0 else {
            return true
        }

        let direction: AdjustmentDirection =
            amount > 0.0 ? .up : .down

        let accuracy: PitchAdjustmentAccuracy

        if abs(amount) >= 1.0 {
            accuracy = .semitone
        } else if abs(amount) >= 0.1 {
            accuracy = .tenth
        } else {
            accuracy = .hundredth
        }

        return adjustPitch(
            direction: direction,
            accuracy: accuracy
        )
    }

    @discardableResult
    func adjustSpeed(by amount: Double) -> Bool {
        guard amount != 0.0 else {
            return true
        }

        return adjustSpeed(
            direction: amount > 0.0 ? .up : .down,
            step: abs(amount)
        )
    }

    @discardableResult
    func adjustVolume(by amount: Double) -> Bool {
        guard amount != 0.0 else {
            return true
        }

        return adjustVolume(
            direction: amount > 0.0 ? .up : .down,
            step: abs(amount)
        )
    }

    // MARK: - Persistent Track Restore

    func restoreCurrentTrack(
        _ url: URL,
        playbackProgress: TimeInterval
    ) throws {
        let file = try AVAudioFile(forReading: url)

        isRestoringPersistentState = true

        audioFile = file
        currentTrackURL = url

        currentTrackDuration = file.processingFormat.sampleRate > 0
            ? Double(file.length) / file.processingFormat.sampleRate
            : 0.0

        let restoredPosition = min(
            max(playbackProgress, 0.0),
            currentTrackDuration
        )

        playbackPositionOffset = restoredPosition
        lastKnownPlaybackPosition = restoredPosition
        lastSavedPlaybackSecond = Int(restoredPosition)

        playbackState = .stopped

        isRestoringPersistentState = false
    }

    // MARK: - Playback

    func play(_ url: URL) throws {
        let file = try AVAudioFile(forReading: url)

        audioFile = file
        currentTrackURL = url
        playbackPositionOffset = 0.0
        lastKnownPlaybackPosition = 0.0
        lastSavedPlaybackSecond = 0
        currentTrackDuration = file.processingFormat.sampleRate > 0
            ? Double(file.length) / file.processingFormat.sampleRate
            : 0.0
        playbackState = .stopped

        if playbackProcessingMode == .native {
            try startNativePlayback(file: file, position: 0.0, shouldPlay: true)
            reportPersistentState()
            return
        }

        deactivateAllPlaybackPipelines()
        try configurePlaybackGraph(for: file)

        if audioProcessingAlgorithm == .soundTouch {
            stopSignalsmithPlayback()
            stopSpeedFixLanes()
            try startSoundTouchPlayback(
                file: file,
                position: 0.0,
                shouldPlay: true
            )
        } else if audioProcessingAlgorithm == .signalsmith {
            stopSoundTouchPlayback()
            try startSignalsmithPlayback(
                file: file,
                position: 0.0,
                shouldPlay: true
            )
        } else if speedFixEnabled {
            try startSpeedFixLane(
                lane: 0,
                file: file,
                position: 0.0,
                shouldPlay: true
            )
        } else {
            stopSpeedFixLanes()
            stopSoundTouchPlayback()
            stopSignalsmithPlayback()
            activePipeline = .system
            speedFixLaneMixerA.outputVolume = 1.0
            speedFixLaneMixerB.outputVolume = 0.0
            soundTouchMixer.outputVolume = 0.0
            signalsmithMixer.outputVolume = 0.0
            scheduleFileWithCompletion(file, on: playerNode)
            playerNode.play()
            playbackState = .playing
        }

        reportPersistentState()
    }

    private func configurePlaybackGraph(
        for file: AVAudioFile
    ) throws {
        let effectivePitch = playbackProcessingMode == .native
            ? 0.0
            : (playbackPitchOverride ?? pitch)
        let effectiveSpeed = playbackProcessingMode == .native ? 1.0 : speed
        let clampedPitch = Float(
            min(max(effectivePitch, -12.0), 12.0) * 100.0
        )
        let clampedRate = Float(
            min(max(effectiveSpeed, 0.1), 3.0)
        )

        timePitch.pitch = clampedPitch
        timePitch.rate = clampedRate
        speedFixTimePitchB.pitch = clampedPitch
        speedFixTimePitchB.rate = clampedRate

        if playbackProcessingMode == .native {
            speedFixLaneMixerA.outputVolume = 1.0
            speedFixLaneMixerB.outputVolume = 0.0
        } else if speedFixEnabled {
            speedFixLaneMixerA.outputVolume =
                speedFixActiveLane == 0 ? 1.0 : 0.0
            speedFixLaneMixerB.outputVolume =
                speedFixActiveLane == 1 ? 1.0 : 0.0
        } else {
            speedFixLaneMixerA.outputVolume = 1.0
            speedFixLaneMixerB.outputVolume = 0.0
        }

        engine.mainMixerNode.outputVolume = Float(
            min(max(volume, 0.0), 1.0)
        )

        if !engine.isRunning {
            try engine.start()
        }
    }

    private var activePlaybackNode: AVAudioPlayerNode {
        switch activePipeline {
        case .native:
            return playerNode
        case .system:
            return speedFixActiveLane == 1 ? speedFixPlayerNodeB : playerNode
        case .soundTouch:
            return soundTouchPlayerNode
        case .signalsmith:
            return signalsmithPlayerNode
        }
    }

    func pause() {
        guard playbackState == .playing else {
            return
        }

        _ = currentPlaybackPosition(shouldAutoSave: false)
        _ = currentPlaybackPosition(shouldAutoSave: false, detectPlaybackEnd: false)
        invalidatePlaybackSchedule()
        activePlaybackNode.stop()
        if audioProcessingAlgorithm == .soundTouch {
            stopSoundTouchPlayback()
        } else if audioProcessingAlgorithm == .signalsmith {
            stopSignalsmithPlayback()
        }
        playbackState = .paused
    }

    func resume() {
        guard playbackState == .paused,
              let audioFile else {
            return
        }

        do {
            if playbackProcessingMode == .native {
                try startNativePlayback(file: audioFile, position: lastKnownPlaybackPosition, shouldPlay: true)
            } else if audioProcessingAlgorithm == .soundTouch {
                try startSoundTouchPlayback(
                    file: audioFile,
                    position: lastKnownPlaybackPosition,
                    shouldPlay: true
                )
            } else if audioProcessingAlgorithm == .signalsmith {
                try startSignalsmithPlayback(
                    file: audioFile,
                    position: lastKnownPlaybackPosition,
                    shouldPlay: true
                )
            } else if speedFixEnabled {
                try startSpeedFixLane(
                    lane: speedFixActiveLane,
                    file: audioFile,
                    position: lastKnownPlaybackPosition,
                    shouldPlay: true
                )
            } else {
                // stop() during pause clears scheduled buffers. Rebuild the
                // system lane from the last known source position instead of
                // calling play() on an empty node.
                try continuePlayback()
            }
        } catch {
            playbackState = .paused
        }
    }

    func continuePlayback() throws {
        guard let audioFile else {
            return
        }

        let sampleRate = audioFile.processingFormat.sampleRate
        guard sampleRate > 0 else {
            return
        }

        let duration = Double(audioFile.length) / sampleRate
        let position = min(
            max(lastKnownPlaybackPosition, 0.0),
            duration
        )

        if playbackProcessingMode == .native {
            try startNativePlayback(file: audioFile, position: position, shouldPlay: true)
            return
        }

        if audioProcessingAlgorithm == .soundTouch {
            try startSoundTouchPlayback(
                file: audioFile,
                position: position,
                shouldPlay: true
            )
            return
        }

        if audioProcessingAlgorithm == .signalsmith {
            try startSignalsmithPlayback(
                file: audioFile,
                position: position,
                shouldPlay: true
            )
            return
        }

        if speedFixEnabled {
            try startSpeedFixLane(
                lane: speedFixActiveLane,
                file: audioFile,
                position: position,
                shouldPlay: true
            )
            return
        }

        let targetFrame = AVAudioFramePosition(position * sampleRate)
        deactivateAllPlaybackPipelines()

        if targetFrame >= audioFile.length {
            playbackPositionOffset = 0.0
            lastKnownPlaybackPosition = 0.0
            lastSavedPlaybackSecond = 0
            try configurePlaybackGraph(for: audioFile)

            playerNode.stop()
            activePipeline = .system
            speedFixLaneMixerA.outputVolume = 1.0
            speedFixLaneMixerB.outputVolume = 0.0
            soundTouchMixer.outputVolume = 0.0
            signalsmithMixer.outputVolume = 0.0
            scheduleFileWithCompletion(audioFile, on: playerNode)
            playerNode.play()
            playbackState = .playing

            reportPersistentState(playbackProgress: 0)
            return
        }

        let frameCount = AVAudioFrameCount(audioFile.length - targetFrame)
        try configurePlaybackGraph(for: audioFile)

        playbackPositionOffset = position
        lastKnownPlaybackPosition = position

        playerNode.stop()
        activePipeline = .system
        speedFixLaneMixerA.outputVolume = 1.0
        speedFixLaneMixerB.outputVolume = 0.0
        soundTouchMixer.outputVolume = 0.0
        signalsmithMixer.outputVolume = 0.0
        scheduleSegmentWithCompletion(
            audioFile,
            startingFrame: targetFrame,
            frameCount: frameCount,
            on: playerNode
        )
        playerNode.play()
        playbackState = .playing
    }

    func togglePlayPause() {

        switch playbackState {

        case .playing:
            pause()

        case .paused:
            resume()

        case .stopped:

            guard currentTrackURL != nil else {
                return
            }

            do {
                try restart()
            } catch {
            }
        }
    }

    func stop() {
        deactivateAllPlaybackPipelines()
        playbackState = .stopped
    }

    func restart() throws {

        guard let currentTrackURL else {
            return
        }

        try play(currentTrackURL)
    }

    private func invalidatePlaybackSchedule() {
        playbackScheduleGeneration &+= 1
    }

    private func scheduleFileWithCompletion(_ file: AVAudioFile, on node: AVAudioPlayerNode) {
        playbackScheduleGeneration &+= 1
        let generation = playbackScheduleGeneration
        let trackURL = currentTrackURL
        let playerBox = WeakPlayerBox(self)

        node.scheduleFile(
            file,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { _ in
            DispatchQueue.main.async {
                guard let self = playerBox.player,
                      self.playbackScheduleGeneration == generation,
                      self.playbackState == .playing,
                      self.currentTrackURL == trackURL else {
                    return
                }

                self.lastKnownPlaybackPosition = self.currentTrackDuration
                self.playbackState = .stopped
                self.savePlaybackProgressImmediately()
                self.onPlaybackEnded?()
            }
        }
    }

    private func scheduleSegmentWithCompletion(
        _ file: AVAudioFile,
        startingFrame: AVAudioFramePosition,
        frameCount: AVAudioFrameCount,
        on node: AVAudioPlayerNode
    ) {
        playbackScheduleGeneration &+= 1
        let generation = playbackScheduleGeneration
        let trackURL = currentTrackURL
        let playerBox = WeakPlayerBox(self)

        node.scheduleSegment(
            file,
            startingFrame: startingFrame,
            frameCount: frameCount,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { _ in
            DispatchQueue.main.async {
                guard let self = playerBox.player,
                      self.playbackScheduleGeneration == generation,
                      self.playbackState == .playing,
                      self.currentTrackURL == trackURL else {
                    return
                }

                self.lastKnownPlaybackPosition = self.currentTrackDuration
                self.playbackState = .stopped
                self.savePlaybackProgressImmediately()
                self.onPlaybackEnded?()
            }
        }
    }

    // MARK: - Playback Position

    func currentPlaybackPosition(
        shouldAutoSave: Bool = true,
        detectPlaybackEnd: Bool = true
    ) -> TimeInterval? {
        guard playbackState == .playing else {
            return nil
        }

        guard let nodeTime = activePlaybackNode.lastRenderTime else {
            return nil
        }

        guard let playerTime = activePlaybackNode.playerTime(
            forNodeTime: nodeTime
        ) else {
            return nil
        }

        guard playerTime.sampleRate > 0 else {
            return nil
        }

        let previousPosition = lastKnownPlaybackPosition

        let outputElapsed =
            Double(playerTime.sampleTime) / playerTime.sampleRate
        let position: TimeInterval
        if activePipeline == .soundTouch {
            position = soundTouchSourceStartPosition
                + outputElapsed * soundTouchPlaybackSpeed
        } else if activePipeline == .signalsmith {
            position = signalsmithSourceStartPosition
                + outputElapsed * signalsmithPlaybackSpeed
        } else if activePipeline == .system {
            position = playbackPositionOffset + outputElapsed * min(max(speed, 0.1), 3.0)
        } else {
            position = playbackPositionOffset + outputElapsed
        }

        let clampedPosition = min(
            max(position, 0.0),
            currentTrackDuration
        )

        lastKnownPlaybackPosition = clampedPosition

        let endTolerance: TimeInterval = 0.01

        if detectPlaybackEnd,
           activePipeline != .soundTouch,
           activePipeline != .signalsmith,
           currentTrackDuration > 0.0,
           currentTrackDuration - clampedPosition <= endTolerance {

            lastKnownPlaybackPosition = currentTrackDuration

            playbackState = .stopped

            savePlaybackProgressImmediately()

            onPlaybackEnded?()

            return currentTrackDuration
        }

        if shouldAutoSave {
            reportPlaybackProgressIfNeeded(
                previousPosition: previousPosition
            )
        }

        return lastKnownPlaybackPosition
    }

    // MARK: - Seek

    func seek(to position: TimeInterval) {
        guard let audioFile else { return }

        let sampleRate = audioFile.processingFormat.sampleRate
        guard sampleRate > 0 else { return }

        let duration = Double(audioFile.length) / sampleRate
        let clampedPosition = min(max(position, 0.0), duration)
        let targetFrame = AVAudioFramePosition(clampedPosition * sampleRate)

        guard targetFrame < audioFile.length else {
            deactivateAllPlaybackPipelines()
            playbackState = .stopped
            playbackPositionOffset = duration
            lastKnownPlaybackPosition = duration
            savePlaybackProgressImmediately()
            onPlaybackEnded?()
            return
        }

        let wasPlaying = playbackState == .playing
        deactivateAllPlaybackPipelines()
        playbackPositionOffset = clampedPosition
        lastKnownPlaybackPosition = clampedPosition

        do {
            if playbackProcessingMode == .native {
                try startNativePlayback(file: audioFile, position: clampedPosition, shouldPlay: wasPlaying)
                if !wasPlaying { playbackState = .paused }
            } else if audioProcessingAlgorithm == .soundTouch {
                try startSoundTouchPlayback(
                    file: audioFile,
                    position: clampedPosition,
                    shouldPlay: wasPlaying
                )
            } else if audioProcessingAlgorithm == .signalsmith {
                try startSignalsmithPlayback(
                    file: audioFile,
                    position: clampedPosition,
                    shouldPlay: wasPlaying
                )
            } else if speedFixEnabled {
                try startSpeedFixLane(
                    lane: speedFixActiveLane,
                    file: audioFile,
                    position: clampedPosition,
                    shouldPlay: wasPlaying
                )
            } else {
                let frameCount = AVAudioFrameCount(
                    audioFile.length - targetFrame
                )
                activePipeline = .system
                speedFixLaneMixerA.outputVolume = 1.0
                speedFixLaneMixerB.outputVolume = 0.0
                soundTouchMixer.outputVolume = 0.0
                signalsmithMixer.outputVolume = 0.0
                scheduleSegmentWithCompletion(
                    audioFile,
                    startingFrame: targetFrame,
                    frameCount: frameCount,
                    on: playerNode
                )
                if wasPlaying {
                    playerNode.play()
                    playbackState = .playing
                } else {
                    playbackState = .paused
                }
            }
        } catch {
            playbackState = wasPlaying ? .playing : .paused
        }

        savePlaybackProgressImmediately()
    }

    // MARK: - Parameters

    func clearPersistedPlaybackProgress() {
        lastSavedPlaybackSecond = 0
        reportPersistentState(
            playbackProgress: 0
        )
    }

    func resetParameters() {

        pitch = 0.0
        speed = 1.0
    }

    func resetToDefault() {
        isRestoringPersistentState = true

        deactivateAllPlaybackPipelines()
        engine.stop()
        audioFile = nil
        playbackPitchOverride = nil
        playbackPositionOffset = 0.0
        lastKnownPlaybackPosition = 0.0
        lastSavedPlaybackSecond = nil
        currentTrackURL = nil
        currentTrackDuration = 0.0
        playbackState = .stopped
        volume = 1.0
        pitch = 0.0
        speed = 1.0

        isRestoringPersistentState = false
        reportPersistentState(playbackProgress: 0)
    }


    private func updateVolume() {

        engine.mainMixerNode.outputVolume =
            Float(
                min(
                    max(volume, 0.0),
                    1.0
                )
            )
    }

    private func deactivateAllPlaybackPipelines() {
        // Mute every output first, then stop nodes and invalidate stream sessions.
        // This closes the brief overlap window between sequential stop calls.
        speedFixLaneMixerA.outputVolume = 0.0
        speedFixLaneMixerB.outputVolume = 0.0
        soundTouchMixer.outputVolume = 0.0
        signalsmithMixer.outputVolume = 0.0
        invalidatePlaybackSchedule()
        stopSpeedFixLanes()
        stopSoundTouchPlayback()
        stopSignalsmithPlayback()
        playerNode.stop()
        playerNode.reset()
        speedFixPlayerNodeB.stop()
        speedFixPlayerNodeB.reset()
        soundTouchPlayerNode.stop()
        soundTouchPlayerNode.reset()
        signalsmithPlayerNode.stop()
        signalsmithPlayerNode.reset()
        speedFixLaneMixerA.outputVolume = 0.0
        speedFixLaneMixerB.outputVolume = 0.0
        soundTouchMixer.outputVolume = 0.0
        signalsmithMixer.outputVolume = 0.0
        activePipeline = .native
    }

    private func startNativePlayback(
        file: AVAudioFile,
        position: TimeInterval,
        shouldPlay: Bool
    ) throws {
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return }
        deactivateAllPlaybackPipelines()
        let targetFrame = AVAudioFramePosition(max(position, 0.0) * sampleRate)
        guard targetFrame < file.length else {
            playbackState = .stopped
            lastKnownPlaybackPosition = currentTrackDuration
            return
        }

        try configurePlaybackGraph(for: file)
        activePipeline = .native
        let frameCount = AVAudioFrameCount(file.length - targetFrame)
        scheduleSegmentWithCompletion(
            file,
            startingFrame: targetFrame,
            frameCount: frameCount,
            on: playerNode
        )
        playbackPositionOffset = max(position, 0.0)
        lastKnownPlaybackPosition = max(position, 0.0)
        speedFixLaneMixerA.outputVolume = 1.0
        speedFixLaneMixerB.outputVolume = 0.0
        soundTouchMixer.outputVolume = 0.0
        signalsmithMixer.outputVolume = 0.0
        if shouldPlay {
            playerNode.play()
            playbackState = .playing
        } else {
            playbackState = .paused
        }
    }

    private func applyPlaybackProcessingModeChange() {
        let previousState = playbackState
        let position = previousState == .playing
            ? (currentPlaybackPosition(shouldAutoSave: false, detectPlaybackEnd: false)
                ?? lastKnownPlaybackPosition)
            : lastKnownPlaybackPosition

        guard let audioFile else {
            if playbackProcessingMode == .native {
                timePitch.pitch = 0.0
                timePitch.rate = 1.0
                speedFixTimePitchB.pitch = 0.0
                speedFixTimePitchB.rate = 1.0
            } else {
                updatePitch()
                updateSpeed()
            }
            deactivateAllPlaybackPipelines()
            return
        }

        if previousState == .stopped {
            deactivateAllPlaybackPipelines()
            do {
                try configurePlaybackGraph(for: audioFile)
                if playbackProcessingMode == .processed {
                    updatePitch()
                    updateSpeed()
                }
            } catch {
                playbackState = .stopped
            }
            playbackState = .stopped
            return
        }

        do {
            if playbackProcessingMode == .native {
                try startNativePlayback(
                    file: audioFile,
                    position: position,
                    shouldPlay: previousState == .playing
                )
                if previousState == .paused { playbackState = .paused }
                return
            }

            deactivateAllPlaybackPipelines()
            playbackPositionOffset = position
            lastKnownPlaybackPosition = position
            if audioProcessingAlgorithm == .soundTouch {
                try startSoundTouchPlayback(file: audioFile, position: position, shouldPlay: previousState == .playing)
            } else if audioProcessingAlgorithm == .signalsmith {
                try startSignalsmithPlayback(file: audioFile, position: position, shouldPlay: previousState == .playing)
            } else if speedFixEnabled {
                try startSpeedFixLane(lane: speedFixActiveLane, file: audioFile, position: position, shouldPlay: previousState == .playing)
            } else {
                try configurePlaybackGraph(for: audioFile)
                activePipeline = .system
                let targetFrame = AVAudioFramePosition(position * audioFile.processingFormat.sampleRate)
                guard targetFrame < audioFile.length else {
                    playbackState = .stopped
                    return
                }
                scheduleSegmentWithCompletion(
                    audioFile,
                    startingFrame: targetFrame,
                    frameCount: AVAudioFrameCount(audioFile.length - targetFrame),
                    on: playerNode
                )
                speedFixLaneMixerA.outputVolume = 1.0
                speedFixLaneMixerB.outputVolume = 0.0
                soundTouchMixer.outputVolume = 0.0
                signalsmithMixer.outputVolume = 0.0
                if previousState == .playing { playerNode.play() }
                playbackState = previousState
            }
            if previousState == .paused { playbackState = .paused }
        } catch {
            deactivateAllPlaybackPipelines()
            playbackState = .paused
        }
    }

    private func applyAudioProcessingAlgorithmChange() {
        guard playbackProcessingMode == .processed,
              let audioFile else { return }

        let position = currentPlaybackPosition(shouldAutoSave: false, detectPlaybackEnd: false) ?? lastKnownPlaybackPosition
        let wasPlaying = playbackState == .playing
        let wasPaused = playbackState == .paused

        do {
            if audioProcessingAlgorithm == .soundTouch {
                try startSoundTouchPlayback(file: audioFile, position: position, shouldPlay: wasPlaying)
                if wasPaused { playbackState = .paused }
                return
            }
            if audioProcessingAlgorithm == .signalsmith {
                try startSignalsmithPlayback(file: audioFile, position: position, shouldPlay: wasPlaying)
                if wasPaused { playbackState = .paused }
                return
            }

            stopSoundTouchPlayback()
            stopSignalsmithPlayback()
            if speedFixEnabled {
                try startSpeedFixLane(lane: speedFixActiveLane, file: audioFile, position: position, shouldPlay: wasPlaying)
                if wasPaused { playbackState = .paused }
                return
            }

            stopSpeedFixLanes()
            configureOriginalTimePitch()
            activePipeline = .system
            let sampleRate = audioFile.processingFormat.sampleRate
            let targetFrame = AVAudioFramePosition(position * sampleRate)
            let frameCount = AVAudioFrameCount(max(0, audioFile.length - targetFrame))
            playbackPositionOffset = position
            lastKnownPlaybackPosition = position
            if targetFrame < audioFile.length {
                scheduleSegmentWithCompletion(audioFile, startingFrame: targetFrame, frameCount: frameCount, on: playerNode)
                if wasPlaying { playerNode.play() }
            }
            speedFixLaneMixerA.outputVolume = 1.0
            speedFixLaneMixerB.outputVolume = 0.0
            playbackState = wasPlaying ? .playing : (wasPaused ? .paused : .stopped)
        } catch {
            playbackState = wasPlaying ? .playing : (wasPaused ? .paused : .stopped)
        }
    }

    private func applySpeedFixModeChange() {
        guard audioProcessingAlgorithm == .systemTimePitch,
              playbackProcessingMode == .processed,
              let audioFile else {
            return
        }

        let position = currentPlaybackPosition(
            shouldAutoSave: false,
            detectPlaybackEnd: false
        ) ?? lastKnownPlaybackPosition
        let wasPlaying = playbackState == .playing
        let wasPaused = playbackState == .paused

        do {
            if speedFixEnabled {
                let targetLane = speedFixActiveLane == 0 ? 1 : 0
                try startSpeedFixLane(
                    lane: targetLane,
                    file: audioFile,
                    position: position,
                    shouldPlay: wasPlaying
                )
                if wasPaused {
                    playbackState = .paused
                }
            } else {
                stopSpeedFixLanes()
                configureOriginalTimePitch()
                let sampleRate = audioFile.processingFormat.sampleRate
                let targetFrame = AVAudioFramePosition(position * sampleRate)
                let frameCount = AVAudioFrameCount(
                    max(0, audioFile.length - targetFrame)
                )

                playbackPositionOffset = position
                lastKnownPlaybackPosition = position
                activePipeline = .system
                soundTouchMixer.outputVolume = 0.0
                signalsmithMixer.outputVolume = 0.0

                if targetFrame < audioFile.length {
                    scheduleSegmentWithCompletion(
                        audioFile,
                        startingFrame: targetFrame,
                        frameCount: frameCount,
                        on: playerNode
                    )
                    if wasPlaying {
                        playerNode.play()
                    }
                }

                speedFixLaneMixerA.outputVolume = 1.0
                speedFixLaneMixerB.outputVolume = 0.0

                playbackState = wasPlaying
                    ? .playing
                    : (wasPaused ? .paused : .stopped)
            }
        } catch {
            playbackState = wasPlaying
                ? .playing
                : (wasPaused ? .paused : .stopped)
        }
    }

    private func configureOriginalTimePitch() {
        let effectivePitch = playbackPitchOverride ?? pitch
        timePitch.pitch = Float(
            min(max(effectivePitch, -12.0), 12.0) * 100.0
        )
        timePitch.rate = Float(
            min(max(speed, 0.1), 3.0)
        )
    }

    private func startSpeedFixLane(
        lane: Int,
        file: AVAudioFile,
        position: TimeInterval,
        shouldPlay: Bool
    ) throws {
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return }

        let clampedPosition = min(
            max(position, 0.0),
            max(Double(file.length - 1) / sampleRate, 0.0)
        )
        let targetFrame = AVAudioFramePosition(
            clampedPosition * sampleRate
        )
        guard targetFrame < file.length else { return }

        let frameCount = AVAudioFrameCount(
            file.length - targetFrame
        )

        // Silence every lane before stopping the previous one or scheduling the next.
        speedFixLaneMixerA.outputVolume = 0.0
        speedFixLaneMixerB.outputVolume = 0.0
        soundTouchMixer.outputVolume = 0.0
        signalsmithMixer.outputVolume = 0.0
        stopSoundTouchPlayback()
        stopSignalsmithPlayback()

        let node: AVAudioPlayerNode
        let processor: AVAudioUnitTimePitch

        if lane == 0 {
            node = playerNode
            processor = timePitch
        } else {
            node = speedFixPlayerNodeB
            processor = speedFixTimePitchB
        }

        let oldNode: AVAudioPlayerNode =
            speedFixActiveLane == 0
                ? playerNode
                : speedFixPlayerNodeB

        node.stop()
        node.reset()
        processor.reset()

        processor.pitch = Float(
            min(
                max(playbackPitchOverride ?? pitch, -12.0),
                12.0
            ) * 100.0
        )
        processor.rate = Float(
            min(max(speed, 0.1), 3.0)
        )

        scheduleSegmentWithCompletion(
            file,
            startingFrame: targetFrame,
            frameCount: frameCount,
            on: node
        )

        speedFixLaneMixerA.outputVolume = 0.0
        speedFixLaneMixerB.outputVolume = 0.0

        speedFixActiveLane = lane
        playbackPositionOffset = clampedPosition
        lastKnownPlaybackPosition = clampedPosition

        activePipeline = .system
        soundTouchMixer.outputVolume = 0.0
        signalsmithMixer.outputVolume = 0.0
        if oldNode !== node {
            oldNode.stop()
        }

        if shouldPlay {
            node.play()

            if lane == 0 {
                speedFixLaneMixerA.outputVolume = 1.0
            } else {
                speedFixLaneMixerB.outputVolume = 1.0
            }

            playbackState = .playing
        } else {
            playbackState = .paused
        }
    }

    private func stopSoundTouchPlayback() {
        soundTouchGeneration &+= 1
        let oldSession = soundTouchSession
        soundTouchSession = nil
        oldSession?.cancelAndWait()
        soundTouchScheduledBuffers = 0
        soundTouchSourceEnded = false
        soundTouchShouldPlay = false
        soundTouchPlayerNode.stop()
        soundTouchPlayerNode.reset()
        soundTouchMixer.outputVolume = 0.0
    }

    private var soundTouchShouldPlay = false

    private func startSoundTouchPlayback(
        file: AVAudioFile,
        position: TimeInterval,
        shouldPlay: Bool
    ) throws {
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else {
            return
        }

        let duration = Double(file.length) / sampleRate
        let clampedPosition = min(
            max(position, 0.0),
            max(duration - 0.001, 0.0)
        )

        // Mute and stop every route before activating SoundTouch.
        deactivateAllPlaybackPipelines()

        let session = try SoundTouchStreamSession(
            file: file,
            startPosition: clampedPosition,
            speed: speed,
            pitchSemitones: playbackPitchOverride ?? pitch
        )

        soundTouchGeneration &+= 1
        let generation = soundTouchGeneration
        activePipeline = .soundTouch
        soundTouchSession = session
        soundTouchScheduledBuffers = 0
        soundTouchSourceEnded = false
        soundTouchShouldPlay = shouldPlay
        soundTouchSourceStartPosition = clampedPosition
        soundTouchPlaybackSpeed = min(max(speed, 0.1), 3.0)
        playbackPositionOffset = clampedPosition
        lastKnownPlaybackPosition = clampedPosition

        speedFixLaneMixerA.outputVolume = 0.0
        speedFixLaneMixerB.outputVolume = 0.0
        soundTouchMixer.outputVolume = 0.0

        try configurePlaybackGraph(for: file)

        // configurePlaybackGraph configures the System lane's mixer for normal
        // playback, so reassert mutual exclusion after graph configuration.
        speedFixLaneMixerA.outputVolume = 0.0
        speedFixLaneMixerB.outputVolume = 0.0
        soundTouchMixer.outputVolume = 0.0

        for _ in 0..<3 {
            requestNextSoundTouchBuffer(
                session: session,
                generation: generation
            )
        }
    }

    private func requestNextSoundTouchBuffer(
        session: SoundTouchStreamSession,
        generation: UInt64
    ) {
        let playerBox = WeakPlayerBox(self)
        session.requestBuffer { buffer, isEnd in
            guard let self = playerBox.player,
                  self.soundTouchGeneration == generation,
                  self.soundTouchSession === session else {
                return
            }

            if let buffer {
                self.scheduleSoundTouchBuffer(
                    buffer,
                    generation: generation
                )
            }

            if isEnd {
                self.soundTouchSourceEnded = true
                self.finishSoundTouchIfNeeded(generation: generation)
            }
        }
    }

    private func scheduleSoundTouchBuffer(
        _ buffer: AVAudioPCMBuffer,
        generation: UInt64
    ) {
        guard soundTouchGeneration == generation else {
            return
        }

        soundTouchScheduledBuffers += 1
        let playerBox = WeakPlayerBox(self)

        soundTouchPlayerNode.scheduleBuffer(
            buffer,
            at: nil,
            options: [],
            completionCallbackType: .dataPlayedBack
        ) { _ in
            DispatchQueue.main.async {
                guard let self = playerBox.player,
                      self.soundTouchGeneration == generation else {
                    return
                }

                self.soundTouchScheduledBuffers = max(
                    self.soundTouchScheduledBuffers - 1,
                    0
                )

                if self.soundTouchSourceEnded {
                    self.finishSoundTouchIfNeeded(
                        generation: generation
                    )
                } else if let session = self.soundTouchSession {
                    self.requestNextSoundTouchBuffer(
                        session: session,
                        generation: generation
                    )
                }
            }
        }

        if soundTouchShouldPlay,
           !soundTouchPlayerNode.isPlaying {
            soundTouchMixer.outputVolume = 1.0
            soundTouchPlayerNode.play()
            playbackState = .playing
        }
    }

    private func finishSoundTouchIfNeeded(generation: UInt64) {
        guard soundTouchGeneration == generation,
              soundTouchSourceEnded,
              soundTouchScheduledBuffers == 0,
              playbackState == .playing else {
            return
        }

        soundTouchMixer.outputVolume = 0.0
        soundTouchSession = nil
        lastKnownPlaybackPosition = currentTrackDuration
        playbackState = .stopped
        savePlaybackProgressImmediately()
        onPlaybackEnded?()
    }

    private func stopSignalsmithPlayback() {
        signalsmithGeneration &+= 1
        let oldSession = signalsmithSession
        signalsmithSession = nil
        oldSession?.cancelAndWait()
        signalsmithScheduledBuffers = 0
        signalsmithSourceEnded = false
        signalsmithShouldPlay = false
        signalsmithPlayerNode.stop()
        signalsmithPlayerNode.reset()
        signalsmithMixer.outputVolume = 0.0
    }


    private func startSignalsmithPlayback(
        file: AVAudioFile,
        position: TimeInterval,
        shouldPlay: Bool
    ) throws {
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else {
            return
        }

        let duration = Double(file.length) / sampleRate
        let clampedPosition = min(
            max(position, 0.0),
            max(duration - 0.001, 0.0)
        )

        // Mute and stop every route before activating Signalsmith.
        deactivateAllPlaybackPipelines()

        let session = try SignalsmithStreamSession(
            file: file,
            startPosition: clampedPosition,
            speed: speed,
            pitchSemitones: playbackPitchOverride ?? pitch
        )

        signalsmithGeneration &+= 1
        let generation = signalsmithGeneration
        activePipeline = .signalsmith
        signalsmithSession = session
        signalsmithScheduledBuffers = 0
        signalsmithSourceEnded = false
        signalsmithShouldPlay = shouldPlay
        signalsmithSourceStartPosition = clampedPosition
        signalsmithPlaybackSpeed = min(max(speed, 0.1), 3.0)
        playbackPositionOffset = clampedPosition
        lastKnownPlaybackPosition = clampedPosition

        speedFixLaneMixerA.outputVolume = 0.0
        speedFixLaneMixerB.outputVolume = 0.0
        signalsmithMixer.outputVolume = 0.0
        soundTouchMixer.outputVolume = 0.0

        try configurePlaybackGraph(for: file)

        // configurePlaybackGraph configures the System lane's mixer for normal
        // playback, so reassert mutual exclusion after graph configuration.
        speedFixLaneMixerA.outputVolume = 0.0
        speedFixLaneMixerB.outputVolume = 0.0
        soundTouchMixer.outputVolume = 0.0
        signalsmithMixer.outputVolume = 0.0

        for _ in 0..<3 {
            requestNextSignalsmithBuffer(
                session: session,
                generation: generation
            )
        }
    }

    private func requestNextSignalsmithBuffer(
        session: SignalsmithStreamSession,
        generation: UInt64
    ) {
        let playerBox = WeakPlayerBox(self)
        session.requestBuffer { buffer, isEnd in
            guard let self = playerBox.player,
                  self.signalsmithGeneration == generation,
                  self.signalsmithSession === session else {
                return
            }

            if let buffer {
                self.scheduleSignalsmithBuffer(
                    buffer,
                    generation: generation
                )
            }

            if isEnd {
                self.signalsmithSourceEnded = true
                self.finishSignalsmithIfNeeded(generation: generation)
            }
        }
    }

    private func scheduleSignalsmithBuffer(
        _ buffer: AVAudioPCMBuffer,
        generation: UInt64
    ) {
        guard signalsmithGeneration == generation else {
            return
        }

        signalsmithScheduledBuffers += 1
        let playerBox = WeakPlayerBox(self)

        signalsmithPlayerNode.scheduleBuffer(
            buffer,
            at: nil,
            options: [],
            completionCallbackType: .dataPlayedBack
        ) { _ in
            DispatchQueue.main.async {
                guard let self = playerBox.player,
                      self.signalsmithGeneration == generation else {
                    return
                }

                self.signalsmithScheduledBuffers = max(
                    self.signalsmithScheduledBuffers - 1,
                    0
                )

                if self.signalsmithSourceEnded {
                    self.finishSignalsmithIfNeeded(
                        generation: generation
                    )
                } else if let session = self.signalsmithSession {
                    self.requestNextSignalsmithBuffer(
                        session: session,
                        generation: generation
                    )
                }
            }
        }

        if signalsmithShouldPlay,
           !signalsmithPlayerNode.isPlaying {
            signalsmithMixer.outputVolume = 1.0
            signalsmithPlayerNode.play()
            playbackState = .playing
        }
    }

    private func finishSignalsmithIfNeeded(generation: UInt64) {
        guard signalsmithGeneration == generation,
              signalsmithSourceEnded,
              signalsmithScheduledBuffers == 0,
              playbackState == .playing else {
            return
        }

        signalsmithMixer.outputVolume = 0.0
        signalsmithSession = nil
        lastKnownPlaybackPosition = currentTrackDuration
        playbackState = .stopped
        savePlaybackProgressImmediately()
        onPlaybackEnded?()
    }

    private func stopSpeedFixLanes() {
        invalidatePlaybackSchedule()
        playerNode.stop()
        speedFixPlayerNodeB.stop()
        speedFixLaneMixerA.outputVolume = 1.0
        speedFixLaneMixerB.outputVolume = 0.0
        speedFixActiveLane = 0
    }

    private func updatePitch() {
        guard playbackProcessingMode == .processed else { return }
        let effectivePitch = playbackPitchOverride ?? pitch

        if audioProcessingAlgorithm == .soundTouch {
            soundTouchSession?.updateParameters(
                speed: speed,
                pitchSemitones: effectivePitch
            )
            return
        }
        if audioProcessingAlgorithm == .signalsmith {
            signalsmithSession?.updateParameters(
                speed: speed,
                pitchSemitones: effectivePitch
            )
            return
        }

        if speedFixEnabled {
            let processor = speedFixActiveLane == 0 ? timePitch : speedFixTimePitchB
            processor.pitch = Float(min(max(effectivePitch, -12.0), 12.0) * 100.0)
            return
        }

        timePitch.pitch = Float(min(max(effectivePitch, -12.0), 12.0) * 100.0)
    }

    private func updateSpeed() {
        guard playbackProcessingMode == .processed else { return }
        let clampedSpeed = min(max(speed, 0.1), 3.0)
        let clampedRate = Float(clampedSpeed)
        let effectivePitch = playbackPitchOverride ?? pitch

        if audioProcessingAlgorithm == .soundTouch {
            guard let session = soundTouchSession else { return }
            if playbackState == .playing {
                let position = currentPlaybackPosition(
                    shouldAutoSave: false,
                    detectPlaybackEnd: false
                ) ?? lastKnownPlaybackPosition
                let oldSpeed = max(soundTouchPlaybackSpeed, 0.1)
                let elapsedOutput = max(position - soundTouchSourceStartPosition, 0.0) / oldSpeed
                soundTouchSourceStartPosition = position - elapsedOutput * clampedSpeed
            }
            soundTouchPlaybackSpeed = clampedSpeed
            session.updateParameters(speed: clampedSpeed, pitchSemitones: effectivePitch)
            return
        }
        if audioProcessingAlgorithm == .signalsmith {
            guard let session = signalsmithSession else { return }
            if playbackState == .playing {
                let position = currentPlaybackPosition(
                    shouldAutoSave: false,
                    detectPlaybackEnd: false
                ) ?? lastKnownPlaybackPosition
                let oldSpeed = max(signalsmithPlaybackSpeed, 0.1)
                let elapsedOutput = max(position - signalsmithSourceStartPosition, 0.0) / oldSpeed
                signalsmithSourceStartPosition = position - elapsedOutput * clampedSpeed
            }
            signalsmithPlaybackSpeed = clampedSpeed
            session.updateParameters(speed: clampedSpeed, pitchSemitones: effectivePitch)
            return
        }

        if speedFixEnabled {
            guard let audioFile, playbackState == .playing || playbackState == .paused else { return }
            let position = currentPlaybackPosition(shouldAutoSave: false, detectPlaybackEnd: false) ?? lastKnownPlaybackPosition
            let wasPlaying = playbackState == .playing
            let targetLane = speedFixActiveLane == 0 ? 1 : 0
            do {
                try startSpeedFixLane(lane: targetLane, file: audioFile, position: position, shouldPlay: wasPlaying)
            } catch { }
        } else {
            timePitch.rate = clampedRate
        }
    }
}
