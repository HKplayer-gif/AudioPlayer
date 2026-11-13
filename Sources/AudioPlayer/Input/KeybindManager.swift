import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation

final class KeybindManager {

    private(set) var quickKeysEnabled: Bool
    private(set) var arrowKeySeekingEnabled: Bool
    private(set) var quickTrackNavigationEnabled: Bool
    private(set) var quickPlayPauseEnabled: Bool
    private(set) var mouseSideButtonsEnabled: Bool
    private(set) var mouseSideButtonsReversed: Bool
    private(set) var shiftF7F9SideButtonsEnabled: Bool

    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private(set) var isEventTapActive = false
    private var applicationIsActive = true
    private let keyboardHotKeyManager = KeyboardHotKeyManager()

    var onAction: ((KeybindAction) -> Void)? {
        didSet {
            keyboardHotKeyManager.onAction = { [weak self] action in
                self?.onAction?(action)
            }
        }
    }

    init(settings: SettingsState) {
        quickKeysEnabled = settings.quickKeysEnabled
        arrowKeySeekingEnabled = settings.arrowKeySeekingEnabled
        quickTrackNavigationEnabled = settings.quickTrackNavigationEnabled
        quickPlayPauseEnabled = settings.quickPlayPauseEnabled
        mouseSideButtonsEnabled = settings.mouseSideButtonsEnabled
        mouseSideButtonsReversed = settings.mouseSideButtonsReversed
        shiftF7F9SideButtonsEnabled = settings.shiftF7F9SideButtonsEnabled
        startMonitoring()
    }

    func updateSettings(_ settings: SettingsState) {
        quickKeysEnabled = settings.quickKeysEnabled
        arrowKeySeekingEnabled = settings.arrowKeySeekingEnabled
        quickTrackNavigationEnabled = settings.quickTrackNavigationEnabled
        quickPlayPauseEnabled = settings.quickPlayPauseEnabled
        mouseSideButtonsEnabled = settings.mouseSideButtonsEnabled
        mouseSideButtonsReversed = settings.mouseSideButtonsReversed
        shiftF7F9SideButtonsEnabled = settings.shiftF7F9SideButtonsEnabled
        startMonitoring()
    }

    var isAccessibilityPermissionGranted: Bool {
        AXIsProcessTrusted()
    }

    var accessibilityListenerStatus: String {
        guard requiresAccessibilityPermission else { return "Not Required" }
        return isAccessibilityPermissionGranted && isEventTapActive
            ? "Permitted"
            : "Not Permitted"
    }

    var accessibilityRequirementDescription: String? {
        guard requiresAccessibilityPermission else { return nil }
        return isAccessibilityPermissionGranted && isEventTapActive
            ? "Used for * settings"
            : "Required for * settings"
    }

    // Accessibility is mandatory for global mouse side-button monitoring.
    // Carbon keyboard shortcuts remain independent of this permission.
    var requiresAccessibilityPermission: Bool {
        quickKeysEnabled && (mouseSideButtonsEnabled || shiftF7F9SideButtonsEnabled)
    }

    private var needsAuxiliaryEventTap: Bool {
        requiresAccessibilityPermission
    }

    @discardableResult
    func refreshAccessibilityPermission() -> Bool {
        stopMouseMonitoring()

        guard needsAuxiliaryEventTap else {
            return AXIsProcessTrusted()
        }

        // Re-query TCC, then validate the actual event tap rather than
        // treating a trusted-process result as proof that listening works.
        let granted = AXIsProcessTrusted()
        guard granted else {
            return false
        }

        startMouseMonitoring()
        return isEventTapActive
    }

    func canApplySettings(_ settings: SettingsState) -> Bool {
        // Always re-read the live TCC state before requesting. This avoids
        // prompting again when macOS has granted permission but the UI has
        // not refreshed yet.
        // Refresh the live system state first. This also revalidates an
        // existing tap and catches a permission grant made moments ago.
        let permissionGranted = refreshAccessibilityPermission()
        let willNeedAuxiliaryTap = settings.quickKeysEnabled &&
            (settings.mouseSideButtonsEnabled || settings.shiftF7F9SideButtonsEnabled)

        guard willNeedAuxiliaryTap, !permissionGranted else {
            return true
        }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        let statusAfterPrompt = AXIsProcessTrusted()
        NSLog(
            "AudioPlayer Keybind: Accessibility prompt requested; trusted after refresh=%@.",
            statusAfterPrompt ? "YES" : "NO"
        )
        return true
    }

    func openAccessibilitySettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )!
        NSWorkspace.shared.open(url)
    }

    func setApplicationActive(_ active: Bool) {
        applicationIsActive = active
        startMonitoring()
    }

    func startMonitoring() {
        keyboardHotKeyManager.update(
            quickKeysEnabled: quickKeysEnabled,
            trackNavigationEnabled: quickTrackNavigationEnabled,
            playPauseEnabled: quickPlayPauseEnabled,
            arrowSeekingEnabled: arrowKeySeekingEnabled,
            applicationActive: applicationIsActive
        )
        startMouseMonitoring()
    }

    private func startMouseMonitoring() {
        guard needsAuxiliaryEventTap else {
            stopMouseMonitoring()
            return
        }

        if eventTap != nil {
            stopMouseMonitoring()
        }

        guard AXIsProcessTrusted() else {
            NSLog("AudioPlayer Keybind: Accessibility is unavailable; Carbon keyboard shortcuts remain active, auxiliary input fallback is not started.")
            return
        }

        // Global auxiliary input: mouse side buttons and Shift-modified
        // system media commands (NX_SYSDEFINED / event type 14).
        let systemDefinedType = CGEventType(rawValue: 14)!
        let mask = (CGEventMask(1) << CGEventType.otherMouseDown.rawValue) |
            (CGEventMask(1) << systemDefinedType.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let manager = Unmanaged<KeybindManager>
                .fromOpaque(userInfo)
                .takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                manager.reenableDisabledEventTap()
                return Unmanaged.passUnretained(event)
            }

            if type == .otherMouseDown, manager.handleOtherMouseDownEvent(event) {
                return nil
            }
            if type.rawValue == 14, manager.handleShiftMediaKeyEvent(event) {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userInfo
        ) else {
            NSLog("AudioPlayer Keybind: auxiliary input CGEventTap creation failed.")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        eventTapRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isEventTapActive = CGEvent.tapIsEnabled(tap: tap)
        NSLog("AudioPlayer Keybind: auxiliary event tap active=%@.", isEventTapActive ? "YES" : "NO")
    }

    private func reenableDisabledEventTap() {
        guard let eventTap, !CGEvent.tapIsEnabled(tap: eventTap) else {
            return
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func stopMouseMonitoring() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        if let source = eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTapRunLoopSource = nil
        eventTap = nil
        isEventTapActive = false
    }

    private func handleShiftMediaKeyEvent(_ event: CGEvent) -> Bool {
        guard quickKeysEnabled && shiftF7F9SideButtonsEnabled,
              let systemEvent = NSEvent(cgEvent: event),
              systemEvent.subtype.rawValue == 8 else {
            return false
        }

        // NX_SYSDEFINED media-key data1:
        // bits 16...31 = NX key type, bits 8...15 = key state.
        // 0xA is key-down; 0xB is key-up. Shift is read from the
        // system media event flags, not from a physical function key.
        let packedData = UInt32(bitPattern: Int32(systemEvent.data1))
        let mediaKey = (packedData >> 16) & 0xFFFF
        let keyState = (packedData >> 8) & 0xFF
        guard keyState == 0x0A,
              systemEvent.modifierFlags.contains(.shift),
              !systemEvent.modifierFlags.contains(.command),
              !systemEvent.modifierFlags.contains(.control),
              !systemEvent.modifierFlags.contains(.option) else {
            return false
        }

        switch mediaKey {
        case 0x12, 0x14: // NX_KEYTYPE_PREVIOUS / alternate previous
            onAction?(mouseSideButtonsReversed ? .mouseSideButtonUp : .mouseSideButtonDown)
            return true
        case 0x11, 0x13: // NX_KEYTYPE_NEXT / alternate next
            onAction?(mouseSideButtonsReversed ? .mouseSideButtonDown : .mouseSideButtonUp)
            return true
        default:
            return false
        }
    }

    private func handleOtherMouseDownEvent(_ event: CGEvent) -> Bool {
        guard quickKeysEnabled && mouseSideButtonsEnabled else { return false }

        switch event.getIntegerValueField(.mouseEventButtonNumber) {
        case 3:
            onAction?(mouseSideButtonsReversed ? .mouseSideButtonUp : .mouseSideButtonDown)
            return true
        case 4:
            onAction?(mouseSideButtonsReversed ? .mouseSideButtonDown : .mouseSideButtonUp)
            return true
        default:
            return false
        }
    }

    deinit {
        stopMouseMonitoring()
        keyboardHotKeyManager.shutdown()
    }
}

private final class KeyboardHotKeyManager {
    var onAction: ((KeybindAction) -> Void)?

    private var eventHandler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []
    private var actions: [UInt32: KeybindAction] = [:]

    func update(
        quickKeysEnabled: Bool,
        trackNavigationEnabled: Bool,
        playPauseEnabled: Bool,
        arrowSeekingEnabled: Bool,
        applicationActive: Bool
    ) {
        unregisterAll()
        guard quickKeysEnabled else { return }
        installEventHandler()

        // F7/F8/F9 are deliberately NOT registered as Carbon hotkeys.
        // Their physical media-key events belong to macOS/MPRemoteCommandCenter,
        // allowing the system to route them to the active media session.
        guard applicationActive else { return }

        if arrowSeekingEnabled {
            register(keyCode: UInt32(kVK_LeftArrow), modifiers: 0, id: 4, action: .seekBackward)
            register(keyCode: UInt32(kVK_RightArrow), modifiers: 0, id: 5, action: .seekForward)
        }
        NSLog(
            "AudioPlayer Keybind: Carbon registrations active=%ld; QuickKeys=%@ ArrowSeek=%@ AppActive=%@. Media keys use system commands; Shift+Previous/Next use the auxiliary tap.",
            hotKeys.count,
            quickKeysEnabled ? "ON" : "OFF",
            arrowSeekingEnabled ? "ON" : "OFF",
            applicationActive ? "YES" : "NO"
        )
    }

    private func installEventHandler() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
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
                  hotKeyID.signature == OSType(0x41504B42) else {
                return OSStatus(eventNotHandledErr)
            }
            let manager = Unmanaged<KeyboardHotKeyManager>
                .fromOpaque(userData)
                .takeUnretainedValue()
            guard let action = manager.actions[hotKeyID.id] else {
                return OSStatus(eventNotHandledErr)
            }
            manager.onAction?(action)
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
            NSLog("AudioPlayer Keybind: Carbon keyboard event handler installation failed: %d.", status)
        }
    }

    private func register(
        keyCode: UInt32,
        modifiers: UInt32,
        id: UInt32,
        action: KeybindAction
    ) {
        guard eventHandler != nil else { return }
        let hotKeyID = EventHotKeyID(signature: OSType(0x41504B42), id: id)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            NSLog("AudioPlayer Keybind: Carbon registration failed for key ID %u (status %d).", id, status)
            return
        }
        hotKeys.append(reference)
        actions[id] = action
    }

    private func unregisterAll() {
        for hotKey in hotKeys {
            UnregisterEventHotKey(hotKey)
        }
        hotKeys.removeAll()
        actions.removeAll()
    }

    func shutdown() {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        eventHandler = nil
    }

    deinit {
        shutdown()
    }
}
