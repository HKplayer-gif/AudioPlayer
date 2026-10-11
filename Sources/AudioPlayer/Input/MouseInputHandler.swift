import SwiftUI
import AppKit

struct MouseInputHandler: NSViewRepresentable {

    let onEvent: (InputEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onEvent: onEvent)
    }

    func makeNSView(context: Context) -> HandlerView {
        let view = HandlerView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(
        _ nsView: HandlerView,
        context: Context
    ) {
        nsView.coordinator = context.coordinator
    }

    @MainActor
    final class Coordinator {

        let onEvent: (InputEvent) -> Void

        init(
            onEvent: @escaping (InputEvent) -> Void
        ) {
            self.onEvent = onEvent
        }

        func send(_ event: InputEvent) {
            DispatchQueue.main.async {
                self.onEvent(event)
            }
        }
    }

    final class HandlerView: NSView {

        var coordinator: Coordinator?

        override func mouseDown(
            with event: NSEvent
        ) {

            guard let coordinator else {
                return
            }
            if event.buttonNumber == 1 {
                coordinator.send(.rightClick)
                return
            }


            let isShiftPressed =
                event.modifierFlags.contains(.shift)

            switch event.clickCount {
            case 1:
                coordinator.send(
                    .leftClick(
                        isShiftPressed: isShiftPressed
                    )
                )
            case 2:
                coordinator.send(
                    .leftDoubleClick(
                        isShiftPressed: isShiftPressed
                    )
                )
            default:
                break
            }
        }
    }
}
