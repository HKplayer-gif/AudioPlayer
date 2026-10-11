import Foundation

@MainActor
struct PitchCyclePlaybackContext {
    let isEnabled: () -> Bool
    let currentEffectivePitch: () -> Double?
    let advance: () -> Void
}

@MainActor
final class PlaybackQueue {

    private let player: Player
    let source: QueueSource
    var onStateChange: (() -> Void)?

    let urls: [URL]

    private(set) var currentIndex: Int

    var playbackMode: PlaybackMode = .single
    private let pitchCycleContext: PitchCyclePlaybackContext?

    init?(
        player: Player,
        urls: [URL],
        startingAt url: URL,
        source: QueueSource,
        pitchCycleContext: PitchCyclePlaybackContext? = nil
    ) {
        guard let index = urls.firstIndex(of: url) else {
            return nil
        }

        self.player = player
        self.urls = urls
        self.currentIndex = index
        self.source = source
        self.pitchCycleContext = pitchCycleContext
    }

    init?(
        player: Player,
        urls: [URL],
        startingAt index: Int,
        source: QueueSource,
        pitchCycleContext: PitchCyclePlaybackContext? = nil
    ) {
        guard urls.indices.contains(index) else {
            return nil
        }

        self.player = player
        self.urls = urls
        self.currentIndex = index
        self.source = source
        self.pitchCycleContext = pitchCycleContext
    }

    init?(player: Player, snapshot: QueueResumeSnapshot, pitchCycleContext: PitchCyclePlaybackContext? = nil) {
        guard !snapshot.urls.isEmpty else {
            return nil
        }

        let restoredIndex: Int

        if let currentURL = snapshot.currentURL,
           let index = snapshot.urls.firstIndex(of: currentURL) {
            restoredIndex = index
        } else if snapshot.urls.indices.contains(snapshot.currentIndex) {
            restoredIndex = snapshot.currentIndex
        } else {
            return nil
        }

        self.player = player
        self.urls = snapshot.urls
        self.currentIndex = restoredIndex
        self.source = snapshot.source
        self.pitchCycleContext = pitchCycleContext
    }

    var resumeSnapshot: QueueResumeSnapshot {
        QueueResumeSnapshot(
            version: 1,
            source: source,
            urls: urls,
            currentIndex: currentIndex,
            currentURL: currentURL
        )
    }

    private func notifyStateChange() {
        onStateChange?()
    }

    var currentURL: URL? {
        guard urls.indices.contains(currentIndex) else {
            return nil
        }

        return urls[currentIndex]
    }

    private enum SkipDirection {
        case forward
        case backward
    }

    @discardableResult
    private func playCurrentInternal(
        origin: PlaybackRequestOrigin
    ) throws -> Bool {
        guard let currentURL else {
            return false
        }

        let pitchCyclesAreActive =
            pitchCycleContext?.isEnabled() == true
            && (playbackMode == .repeatOne || playbackMode == .repeatList)

        if pitchCyclesAreActive,
           let cyclePitch = pitchCycleContext?.currentEffectivePitch() {
            player.setPlaybackPitchOverride(cyclePitch)
        } else {
            player.setPlaybackPitchOverride(nil)
        }

        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(
            atPath: currentURL.path,
            isDirectory: &isDirectory
        ), !isDirectory.boolValue else {
            throw PlaybackFailure.fileUnavailable(currentURL)
        }

        do {
            try player.play(currentURL)

            return true
        } catch {
            throw PlaybackFailure.playbackFailed(
                currentURL,
                error
            )
        }
    }

    @discardableResult
    private func playCurrentSkippingFailures(
        direction: SkipDirection,
        wraps: Bool,
        origin: PlaybackRequestOrigin
    ) -> Bool {
        guard !urls.isEmpty else {
            return false
        }

        var attemptedIndices: Set<Int> = []

        while true {
            guard urls.indices.contains(currentIndex) else {
                return false
            }

            if attemptedIndices.contains(currentIndex) {
                return false
            }

            attemptedIndices.insert(currentIndex)

            do {

                return try playCurrentInternal(origin: origin)
            } catch is PlaybackFailure {
                if case .directSelection = origin {
                    return false
                }
            } catch {
                if case .directSelection = origin {
                    return false
                }
            }

            let nextIndex: Int

            switch direction {
            case .forward:
                nextIndex = currentIndex + 1

            case .backward:
                nextIndex = currentIndex - 1
            }

            if urls.indices.contains(nextIndex) {
                currentIndex = nextIndex
                notifyStateChange()
                continue
            }

            guard wraps else {
                return false
            }

            switch direction {
            case .forward:
                currentIndex = urls.startIndex
                notifyStateChange()

            case .backward:
                currentIndex = urls.index(before: urls.endIndex)
                notifyStateChange()
            }
        }
    }

    func playCurrent(
        origin: PlaybackRequestOrigin = .directSelection
    ) throws {
        _ = try playCurrentInternal(origin: origin)
    }

    @discardableResult
    func select(index: Int) -> Bool {
        guard urls.indices.contains(index) else {
            return false
        }

        let previousIndex = currentIndex
        currentIndex = index
        notifyStateChange()

        do {
            return try playCurrentInternal(origin: .directSelection)
        } catch {
            currentIndex = previousIndex
            notifyStateChange()
            return false
        }
    }

    func next(wraps: Bool = true) {
        let nextIndex = currentIndex + 1

        if urls.indices.contains(nextIndex) {
            currentIndex = nextIndex
        } else {
            guard wraps else {
                return
            }

            currentIndex = urls.startIndex
        }

        notifyStateChange()

        _ = playCurrentSkippingFailures(
            direction: .forward,
            wraps: wraps,
            origin: .navigation
        )
    }

    func previous() {
        let previousIndex = currentIndex - 1

        if urls.indices.contains(previousIndex) {
            currentIndex = previousIndex
        } else {
            currentIndex = urls.index(before: urls.endIndex)
        }

        notifyStateChange()

        _ = playCurrentSkippingFailures(
            direction: .backward,
            wraps: true,
            origin: .navigation
        )
    }

    func playbackReachedEnd() throws {
        switch playbackMode {

        case .single:
            return

        case .repeatOne:
            if pitchCycleContext?.isEnabled() == true {
                pitchCycleContext?.advance()
            }

            do {
                _ = try playCurrentInternal(
                    origin: .automaticAdvance
                )
            } catch {

                _ = playCurrentSkippingFailures(
                    direction: .forward,
                    wraps: true,
                    origin: .automaticAdvance
                )
            }

        case .list:
            _ = playCurrentSkippingFailures(
                direction: .forward,
                wraps: false,
                origin: .automaticAdvance
            )

        case .repeatList:
            if pitchCycleContext?.isEnabled() == true {
                pitchCycleContext?.advance()
            }

            _ = playCurrentSkippingFailures(
                direction: .forward,
                wraps: true,
                origin: .automaticAdvance
            )
        }
    }

}
