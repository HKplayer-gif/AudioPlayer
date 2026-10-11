import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class QuickSearchController {

    private var eventMonitor: Any?

    private(set) var buffer = ""

    func start() {
        stopMonitoringOnly()

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard let self else {
                return event
            }

            return self.handle(event) ? nil : event
        }
    }

    func stop() {
        stopMonitoringOnly()
        clear()
    }

    func clear() {
        buffer = ""
    }

    private func stopMonitoringOnly() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              !event.isARepeat else {
            return false
        }

        if event.keyCode == 53 {
            guard !buffer.isEmpty else {
                return false
            }

            clear()
            return true
        }

        if event.keyCode == 51 {
            guard !buffer.isEmpty else {
                return false
            }

            buffer.removeLast()
            return true
        }

        guard event.modifierFlags.intersection([
            .command,
            .control,
            .option
        ]).isEmpty else {
            return false
        }

        guard let characters = event.characters,
              !characters.isEmpty,
              characters.allSatisfy({ character in
                  character.unicodeScalars.allSatisfy {
                      $0.value >= 0x20 && $0.value <= 0x7E
                  }
              }) else {
            return false
        }

        buffer.append(contentsOf: characters)
        return true
    }

}
