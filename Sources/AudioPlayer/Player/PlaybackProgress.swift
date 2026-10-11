import Foundation
import Observation

@Observable
final class PlaybackProgress {

    private(set) var position: TimeInterval = 0.0

    private(set) var duration: TimeInterval = 0.0

    private var lastStablePosition: TimeInterval = 0.0

    func update(
        position: TimeInterval,
        duration: TimeInterval
    ) {
        self.duration = max(
            0.0,
            duration
        )

        self.position = max(
            0.0,
            min(position, self.duration)
        )

        lastStablePosition = self.position
    }

    func preserveCurrentPosition() {
        position = lastStablePosition
    }

    func reset() {
        position = 0.0
        duration = 0.0
        lastStablePosition = 0.0
    }

    var displayPosition: Int {
        max(0, Int(position))
    }
}
