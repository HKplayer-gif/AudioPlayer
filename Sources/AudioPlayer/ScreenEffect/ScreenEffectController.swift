import AppKit
import Carbon
import CoreGraphics
import Foundation
import Observation
import QuartzCore

enum ScreenEffectStatus: Equatable, Sendable {
    case disabled
    case enabled

    var title: String {
        switch self {
        case .disabled: return "Disabled"
        case .enabled: return "Enabled"
        }
    }
}

@MainActor
@Observable
final class ScreenEffectController {
    private(set) var status: ScreenEffectStatus = .disabled

    var onToggleRequested: (() -> Void)?

    private let display = GammaDisplay()
    private let hotKeyManager = ScreenEffectHotKeyManager()

    private var settings: SettingsState
    private var analysisResult: BPMKeyAnalysisResult?
    private var analysisStatus: BPMKeyAnalysisStatus = .idle

    private var playbackPositionProvider: (() -> (TimeInterval?, Bool))?
    private var monitorTimer: Timer?
    private var pulseStart: CFTimeInterval?
    private var lastSourcePosition: TimeInterval?
    private var nextBeatIndex = 0
    private var scheduledPulseTimes: [TimeInterval] = []

    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var displayObserver: NSObjectProtocol?

    init(settings: SettingsState) {
        self.settings = settings

        hotKeyManager.onPressed = { [weak self] in
            self?.onToggleRequested?()
        }
        updateHotKeyRegistration()

        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleWillSleep()
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleDidWake()
            }
        }

        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleDisplayConfigurationChange()
            }
        }

        updateStatusAndMonitoring()
    }

    func setPlaybackPositionProvider(
        _ provider: @escaping () -> (TimeInterval?, Bool)
    ) {
        playbackPositionProvider = provider
        updateStatusAndMonitoring()
    }

    func updateSettings(_ newSettings: SettingsState) {
        let triggerChanged =
            settings.screenEffectTriggerKeyCode != newSettings.screenEffectTriggerKeyCode
            || settings.screenEffectTriggerShift != newSettings.screenEffectTriggerShift
        let bpmAvailabilityChanged = settings.bpmKeyEnabled != newSettings.bpmKeyEnabled
        let beatRateChanged = settings.screenEffectBeatRateMultiplier != newSettings.screenEffectBeatRateMultiplier

        settings = newSettings

        if beatRateChanged {
            stopPulseAndRestore()
            rebuildPulseSchedule()
            nextBeatIndex = 0
            lastSourcePosition = nil
        }

        if triggerChanged || bpmAvailabilityChanged {
            updateHotKeyRegistration()
        }

        updateStatusAndMonitoring()
    }

    func updateAnalysis(
        result: BPMKeyAnalysisResult?,
        status: BPMKeyAnalysisStatus
    ) {
        analysisResult = result
        analysisStatus = status
        rebuildPulseSchedule()
        nextBeatIndex = 0
        lastSourcePosition = nil
        updateStatusAndMonitoring()
    }

    func shutdown() {
        stopMonitoringAndRestore()
        hotKeyManager.shutdown()
        display.restore()

        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
            self.sleepObserver = nil
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let displayObserver {
            NotificationCenter.default.removeObserver(displayObserver)
            self.displayObserver = nil
        }
    }

    private func updateHotKeyRegistration() {
        guard settings.bpmKeyEnabled else {
            hotKeyManager.unregister()
            return
        }

        _ = hotKeyManager.register(
            keyCode: settings.screenEffectTriggerKeyCode,
            shift: settings.screenEffectTriggerShift
        )
    }

    private func updateStatusAndMonitoring() {
        status = settings.bpmKeyEnabled && settings.screenEffectEnabled
            ? .enabled
            : .disabled

        guard status == .enabled else {
            stopMonitoringAndRestore()
            return
        }

        guard display.isReady else {
            stopMonitoringAndRestore()
            return
        }

        if case .failed = analysisStatus {
            stopMonitoringAndRestore()
            return
        }

        guard let analysisResult,
              !analysisResult.beatTimes.isEmpty,
              !scheduledPulseTimes.isEmpty else {
            stopMonitoringAndRestore()
            return
        }

        if monitorTimer == nil {
            monitorTimer = Timer.scheduledTimer(
                withTimeInterval: 1.0 / 60.0,
                repeats: true
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.tick()
                }
            }
        }
    }

    private func tick() {
        guard settings.bpmKeyEnabled,
              settings.screenEffectEnabled,
              let playbackPositionProvider else {
            stopMonitoringAndRestore()
            return
        }

        let (position, isPlaying) = playbackPositionProvider()

        guard isPlaying, let position else {
            lastSourcePosition = nil
            stopPulseAndRestore()
            return
        }

        guard position.isFinite else {
            stopPulseAndRestore()
            return
        }

        guard let previousPosition = lastSourcePosition else {
            nextBeatIndex = firstPulseIndex(after: position)
            lastSourcePosition = position
            updatePulseEnvelope()
            return
        }

        let elapsedSourceTime = position - previousPosition

        // A backwards jump is a seek or loop. A large forward jump is treated
        // as a seek/stall so the scheduler does not emit a burst of old beats.
        if elapsedSourceTime < -0.05 || elapsedSourceTime > 0.5 {
            stopPulseAndRestore()
            nextBeatIndex = firstPulseIndex(after: position)
            lastSourcePosition = position
            return
        }

        while nextBeatIndex < scheduledPulseTimes.count,
              scheduledPulseTimes[nextBeatIndex] <= position {
            let pulseTime = scheduledPulseTimes[nextBeatIndex]
            if pulseTime > previousPosition { triggerPulse() }
            nextBeatIndex += 1
        }

        lastSourcePosition = position
        updatePulseEnvelope()

    }

    private func firstPulseIndex(after position: TimeInterval) -> Int {
        scheduledPulseTimes.firstIndex(where: { $0 > position }) ?? scheduledPulseTimes.count
    }

    private func rebuildPulseSchedule() {
        guard let beats = analysisResult?.beatTimes, !beats.isEmpty else {
            scheduledPulseTimes = []
            return
        }
        let multiplier = min(max(settings.screenEffectBeatRateMultiplier, 0.125), 4.0)
        let lastBeatPosition = Double(beats.count - 1)
        let lastEventIndex = Int(floor(lastBeatPosition * multiplier + 1e-9))
        scheduledPulseTimes = (0...lastEventIndex).compactMap { index in
            let beatPosition = Double(index) / multiplier
            let lower = Int(floor(beatPosition))
            let fraction = beatPosition - Double(lower)
            guard lower < beats.count else { return nil }
            guard lower + 1 < beats.count else { return beats[lower] }
            return beats[lower] + (beats[lower + 1] - beats[lower]) * fraction
        }
    }

    private func triggerPulse() {
        if pulseStart == nil, !display.captureCurrent() {
            return
        }

        pulseStart = CACurrentMediaTime()
        updatePulseEnvelope()
    }

    private func updatePulseEnvelope() {
        guard let pulseStart else { return }

        let elapsed = CACurrentMediaTime() - pulseStart
        let fadeIn = settings.screenEffectFadeInDuration
        let hold = settings.screenEffectHoldDuration
        let fadeOut = settings.screenEffectFadeOutDuration
        let strength = settings.screenEffectStrength
        let fadeInEnd = fadeIn
        let holdEnd = fadeIn + hold
        let totalDuration = max(fadeIn + hold + fadeOut, 1.0 / 60.0)

        let envelope: Double
        if fadeIn > 0, elapsed < fadeInEnd {
            envelope = min(1.0, elapsed / fadeIn)
        } else if elapsed < holdEnd {
            envelope = 1.0
        } else if fadeOut > 0, elapsed < totalDuration {
            let progress = min(1.0, (elapsed - holdEnd) / fadeOut)
            envelope = 1.0 - progress
        } else if elapsed < totalDuration {
            envelope = 1.0
        } else {
            stopPulseAndRestore()
            return
        }

        let redGain = 1.0 + (strength - 1.0) * settings.screenEffectRedMultiplier * envelope
        let greenGain = 1.0 + (strength - 1.0) * settings.screenEffectGreenMultiplier * envelope
        let blueGain = 1.0 + (strength - 1.0) * settings.screenEffectBlueMultiplier * envelope

        display.apply(
            redGain: redGain,
            greenGain: greenGain,
            blueGain: blueGain
        )
    }

    private func stopPulseAndRestore() {
        pulseStart = nil
        display.restore()
    }

    private func stopMonitoringAndRestore() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        lastSourcePosition = nil
        nextBeatIndex = 0
        stopPulseAndRestore()
    }

    private func handleWillSleep() {
        stopPulseAndRestore()
        lastSourcePosition = nil
    }

    private func handleDidWake() {
        _ = display.captureCurrent()
        updateStatusAndMonitoring()
    }

    private func handleDisplayConfigurationChange() {
        stopPulseAndRestore()
        display.refreshDisplay()
        lastSourcePosition = nil
        updateStatusAndMonitoring()
    }
}

private final class GammaDisplay {
    private var displayID = CGMainDisplayID()
    private let sampleCapacity: UInt32 = 4096
    private var sampleCount: UInt32 = 0
    private var originalRed: [CGGammaValue] = []
    private var originalGreen: [CGGammaValue] = []
    private var originalBlue: [CGGammaValue] = []
    private(set) var isReady = false

    init() {
        _ = captureCurrent()
    }

    @discardableResult
    func captureCurrent() -> Bool {
        var red = [CGGammaValue](repeating: 0, count: Int(sampleCapacity))
        var green = [CGGammaValue](repeating: 0, count: Int(sampleCapacity))
        var blue = [CGGammaValue](repeating: 0, count: Int(sampleCapacity))
        var count: UInt32 = 0

        let result = CGGetDisplayTransferByTable(
            displayID,
            sampleCapacity,
            &red,
            &green,
            &blue,
            &count
        )

        guard result == .success, count > 1 else {
            isReady = false
            NSLog("AudioPlayer Screen Effect: failed to read Gamma table: %d", result.rawValue)
            return false
        }

        sampleCount = count
        originalRed = Array(red.prefix(Int(count)))
        originalGreen = Array(green.prefix(Int(count)))
        originalBlue = Array(blue.prefix(Int(count)))
        isReady = true
        return true
    }

    func apply(
        redGain: Double,
        greenGain: Double,
        blueGain: Double
    ) {
        guard isReady else { return }
        var red = originalRed.map {
            CGGammaValue(min(max(Double($0) * redGain, 0.0), 1.0))
        }
        var green = originalGreen.map {
            CGGammaValue(min(max(Double($0) * greenGain, 0.0), 1.0))
        }
        var blue = originalBlue.map {
            CGGammaValue(min(max(Double($0) * blueGain, 0.0), 1.0))
        }

        let result = CGSetDisplayTransferByTable(
            displayID,
            sampleCount,
            &red,
            &green,
            &blue
        )
        if result != .success {
            NSLog("AudioPlayer Screen Effect: failed to apply Gamma table: %d", result.rawValue)
        }
    }

    func restore() {
        guard isReady else { return }

        var red = originalRed
        var green = originalGreen
        var blue = originalBlue
        let result = CGSetDisplayTransferByTable(
            displayID,
            sampleCount,
            &red,
            &green,
            &blue
        )
        if result != .success {
            NSLog("AudioPlayer Screen Effect: failed to restore Gamma table: %d", result.rawValue)
        }
    }

    func refreshDisplay() {
        restore()
        displayID = CGMainDisplayID()
        _ = captureCurrent()
    }
}

@MainActor
private final class ScreenEffectHotKeyManager {
    var onPressed: (() -> Void)?

    private var eventHandler: EventHandlerRef?
    private var hotKeyReference: EventHotKeyRef?

    init() {
        installEventHandler()
    }

    @discardableResult
    func register(keyCode: UInt32, shift: Bool) -> Bool {
        unregisterHotKey()

        guard eventHandler != nil else { return false }

        let hotKeyID = EventHotKeyID(
            signature: OSType(0x53454658),
            id: 1
        )
        let modifiers = UInt32(cmdKey) | (shift ? UInt32(shiftKey) : 0)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )

        return status == noErr
    }

    func unregister() {
        unregisterHotKey()
    }

    func shutdown() {
        unregisterHotKey()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        eventHandler = nil
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = UnsafeMutableRawPointer(
            Unmanaged.passUnretained(self).toOpaque()
        )

        let callback: EventHandlerProcPtr = { _, event, userData in
            guard let event, let userData else {
                return OSStatus(eventNotHandledErr)
            }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr,
                  hotKeyID.signature == OSType(0x53454658),
                  hotKeyID.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }

            let owner = Unmanaged<ScreenEffectHotKeyManager>
                .fromOpaque(userData)
                .takeUnretainedValue()

            Task { @MainActor in
                owner.onPressed?()
            }
            return noErr
        }

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            userData,
            &eventHandler
        )

        if status != noErr {
            eventHandler = nil
        }
    }

    private func unregisterHotKey() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
        }
        hotKeyReference = nil
    }
}
