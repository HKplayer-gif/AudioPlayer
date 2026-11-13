import AppKit
import Carbon
import SwiftUI

struct ScreenEffectHotKeyCaptureField: NSViewRepresentable {
    let keyLabel: String
    let onCapture: (UInt32, String, Bool) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ScreenEffectKeyCaptureNSView {
        let view = ScreenEffectKeyCaptureNSView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        view.keyLabel = keyLabel
        return view
    }

    func updateNSView(
        _ view: ScreenEffectKeyCaptureNSView,
        context: Context
    ) {
        view.onCapture = onCapture
        view.onCancel = onCancel
        view.keyLabel = keyLabel
        view.needsDisplay = true
    }
}

final class ScreenEffectKeyCaptureNSView: NSView {
    var onCapture: ((UInt32, String, Bool) -> Void)?
    var onCancel: (() -> Void)?
    var keyLabel = "?"
    private var isCapturing = false

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        isCapturing = true
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        guard isCapturing else { return }
        isCapturing = false
        onCancel?()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            isCapturing = false
            onCancel?()
            needsDisplay = true
            return
        }

        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let characters = event.characters,
              let scalar = characters.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar) else {
            NSSound.beep()
            return
        }

        isCapturing = false
        onCapture?(
            UInt32(event.keyCode),
            String(characters).uppercased(),
            event.modifierFlags.contains(.shift)
        )
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let background = NSBezierPath(
            roundedRect: bounds,
            xRadius: 7,
            yRadius: 7
        )

        (isCapturing
            ? NSColor.controlAccentColor.withAlphaComponent(0.16)
            : NSColor.controlBackgroundColor
        ).setFill()
        background.fill()

        (isCapturing ? NSColor.controlAccentColor : NSColor.separatorColor)
            .setStroke()
        background.lineWidth = 1
        background.stroke()

        let text = isCapturing
            ? "Press a key… (Esc to cancel)"
            : "⌘ + \(keyLabel)   ·   Click to change"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(
                x: (bounds.width - size.width) / 2,
                y: (bounds.height - size.height) / 2
            ),
            withAttributes: attributes
        )
    }
}
