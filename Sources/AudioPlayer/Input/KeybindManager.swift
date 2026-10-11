import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

final class KeybindManager {

    private(set) var quickKeysEnabled: Bool
    private(set) var arrowKeySeekingEnabled: Bool
    private(set) var quickTrackNavigationEnabled: Bool
    private(set) var f7RestartBehaviorEnabled: Bool
    private(set) var quickPlayPauseEnabled: Bool
    private(set) var mouseSideButtonsEnabled: Bool
    private(set) var mouseSideButtonsReversed: Bool
    private(set) var shiftF7F9SideButtonsEnabled: Bool

    private var eventTap: CFMachPort?
    private var hasRequestedAccessibilityPermission = false

    var onAction: ((KeybindAction) -> Void)?

    init(settings: SettingsState) {
        quickKeysEnabled =
            settings.quickKeysEnabled
        arrowKeySeekingEnabled =
            settings.arrowKeySeekingEnabled
        quickTrackNavigationEnabled =
            settings.quickTrackNavigationEnabled
        f7RestartBehaviorEnabled =
            settings.f7RestartBehaviorEnabled
        quickPlayPauseEnabled =
            settings.quickPlayPauseEnabled
        mouseSideButtonsEnabled =
            settings.mouseSideButtonsEnabled

        mouseSideButtonsReversed =
            settings.mouseSideButtonsReversed
        shiftF7F9SideButtonsEnabled =
            settings.shiftF7F9SideButtonsEnabled
        if quickKeysEnabled &&
            (mouseSideButtonsEnabled ||
             shiftF7F9SideButtonsEnabled ||
             arrowKeySeekingEnabled) {
            startMonitoring()
        }
    }

    func updateSettings(_ settings: SettingsState) {
        quickKeysEnabled =
            settings.quickKeysEnabled
        arrowKeySeekingEnabled =
            settings.arrowKeySeekingEnabled
        quickTrackNavigationEnabled =
            settings.quickTrackNavigationEnabled
        f7RestartBehaviorEnabled =
            settings.f7RestartBehaviorEnabled
        quickPlayPauseEnabled =
            settings.quickPlayPauseEnabled
        mouseSideButtonsEnabled =
            settings.mouseSideButtonsEnabled

        mouseSideButtonsReversed =
            settings.mouseSideButtonsReversed
        shiftF7F9SideButtonsEnabled =
            settings.shiftF7F9SideButtonsEnabled
        if quickKeysEnabled &&
            (mouseSideButtonsEnabled ||
             shiftF7F9SideButtonsEnabled ||
             arrowKeySeekingEnabled) {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    var isAccessibilityPermissionGranted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func refreshAccessibilityPermission() -> Bool {
        let granted = AXIsProcessTrusted()

        if granted {
            startMonitoring()
        }

        return granted
    }

    func canApplySettings(_ settings: SettingsState) -> Bool {
        guard requiresEventMonitoring(settings) else {
            return true
        }

        guard !AXIsProcessTrusted() else {
            return true
        }

        guard !hasRequestedAccessibilityPermission else {
            return true
        }

        hasRequestedAccessibilityPermission = true

        let accessibilityOptions = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary

        _ = AXIsProcessTrustedWithOptions(accessibilityOptions)
        return true
    }

    func openAccessibilitySettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )!
        NSWorkspace.shared.open(url)
    }

    func startMonitoring() {
        guard
            quickKeysEnabled &&
            (mouseSideButtonsEnabled ||
             shiftF7F9SideButtonsEnabled ||
             arrowKeySeekingEnabled)
        else {
            return
        }

        guard eventTap == nil else {
            return
        }

        guard AXIsProcessTrusted() else {
            
            return
        }

        let otherMouseDownMask =
            CGEventMask(1) << CGEventType.otherMouseDown.rawValue

        let systemDefinedType =
            CGEventType(rawValue: 14)!

        let systemDefinedMask =
            CGEventMask(1) << systemDefinedType.rawValue

        let keyDownMask =
            CGEventMask(1) << CGEventType.keyDown.rawValue

        let eventsOfInterest =
            otherMouseDownMask | systemDefinedMask | keyDownMask

        let callback: CGEventTapCallBack = {
            _, type, event, userInfo in

            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let manager =
                Unmanaged<KeybindManager>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()

            if type == .otherMouseDown {
                if manager.handleOtherMouseDownEvent(event) {
                    return nil
                }
            }

            if type.rawValue == 14 {
                if manager.handleSystemDefinedEvent(event) {
                    return nil
                }
            }

            if type == .keyDown {
                if manager.handleKeyDownEvent(event) {
                    return nil
                }
            }

            return Unmanaged.passUnretained(event)
        }

        let userInfo =
            Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventsOfInterest,
            callback: callback,
            userInfo: userInfo
        ) else {
            
            return
        }

        eventTap = tap

        let source =
            CFMachPortCreateRunLoopSource(
                nil,
                tap,
                0
            )

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            source,
            .commonModes
        )

        CGEvent.tapEnable(
            tap: tap,
            enable: true
        )
    }

    private func handleKeyDownEvent(_ event: CGEvent) -> Bool {
        guard
            quickKeysEnabled,
            arrowKeySeekingEnabled,
            event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
            event.flags.intersection([
                .maskCommand,
                .maskControl,
                .maskAlternate,
                .maskShift
            ]).isEmpty
        else {
            return false
        }

        let keyCode =
            event.getIntegerValueField(.keyboardEventKeycode)

        switch keyCode {
        case 123:
            onAction?(.seekBackward)
            return true

        case 124:
            onAction?(.seekForward)
            return true

        default:
            return false
        }
    }

    private func requiresEventMonitoring(_ settings: SettingsState) -> Bool {
        settings.quickKeysEnabled &&
            (settings.mouseSideButtonsEnabled ||
             settings.shiftF7F9SideButtonsEnabled ||
             settings.arrowKeySeekingEnabled)
    }

    func stopMonitoring() {
        guard let tap = eventTap else {
            return
        }

        CGEvent.tapEnable(
            tap: tap,
            enable: false
        )

        CFMachPortInvalidate(tap)

        eventTap = nil
    }

    deinit {
        stopMonitoring()
    }

    private func handleSystemDefinedEvent(
        _ event: CGEvent
    ) -> Bool {
        guard
            quickKeysEnabled &&
            shiftF7F9SideButtonsEnabled
        else {
            return false
        }

        guard let nsEvent = NSEvent(cgEvent: event) else {
            return false
        }

        guard nsEvent.subtype.rawValue == 8 else {
            return false
        }

        let data1 = nsEvent.data1
        let commandGroup =
            (data1 >> 16) & 0xFF
        let key =
            (data1 >> 8) & 0xFF

        if commandGroup == 0x14,
           key == 0x0A,
           !event.flags.contains(.maskShift),
           !event.flags.contains(.maskCommand),
           quickTrackNavigationEnabled,
           f7RestartBehaviorEnabled {
            onAction?(.f7PreviousTrack)
            return true
        }

        guard key == 0x0A else {
            return false
        }

        guard event.flags.contains(.maskShift) else {
            return false
        }

        switch commandGroup {
        case 0x14:
            
            onAction?(.mouseSideButtonDown)
            return true

        case 0x13:
            
            onAction?(.mouseSideButtonUp)
            return true

        default:
            return false
        }
    }

    private func handleOtherMouseDownEvent(
        _ event: CGEvent
    ) -> Bool {

        let buttonNumber =
            event.getIntegerValueField(
                .mouseEventButtonNumber
            )

        switch buttonNumber {
        case 3:
            guard
                quickKeysEnabled &&
                mouseSideButtonsEnabled
            else {
                return false
            }

            

            onAction?(
                mouseSideButtonsReversed
                    ? .mouseSideButtonUp
                    : .mouseSideButtonDown
            )

            return true

        case 4:
            guard
                quickKeysEnabled &&
                mouseSideButtonsEnabled
            else {
                return false
            }

            

            onAction?(
                mouseSideButtonsReversed
                    ? .mouseSideButtonDown
                    : .mouseSideButtonUp
            )

            return true

        default:
            return false
        }
    }
}
