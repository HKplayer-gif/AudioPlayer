import Foundation
import MediaPlayer

final class NowPlayingController {

    private let commandCenter =
        MPRemoteCommandCenter.shared()

    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onTogglePlayPause: (() -> Void)?
    var onPreviousTrack: (() -> Void)?
    var onNextTrack: (() -> Void)?

    init() {
        configureRemoteCommands()
    }

    private func configureRemoteCommands() {
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true

        commandCenter.playCommand.addTarget { [weak self] _ in
            
            self?.onPlay?()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            
            self?.onPause?()
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            
            self?.onTogglePlayPause?()
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            
            self?.onPreviousTrack?()
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            
            self?.onNextTrack?()
            return .success
        }
    }

    func update(
        playbackState: Player.PlaybackState,
        currentTrackURL: URL?,
        currentTrackDuration: TimeInterval
    ) {
        let infoCenter =
            MPNowPlayingInfoCenter.default()

        if let currentTrackURL {
            let title =
                currentTrackURL
                    .deletingPathExtension()
                    .lastPathComponent

            infoCenter.nowPlayingInfo = [
                MPMediaItemPropertyTitle: title,
                MPMediaItemPropertyPlaybackDuration:
                    currentTrackDuration,
                MPNowPlayingInfoPropertyPlaybackRate:
                    1.0
            ]
        }

        switch playbackState {
        case .playing:
            infoCenter.playbackState = .playing

        case .paused:
            infoCenter.playbackState = .paused

        case .stopped:
            infoCenter.playbackState = .stopped
        }
    }
}
