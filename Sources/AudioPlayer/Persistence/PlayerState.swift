import Foundation

struct PlayerState: Codable {
    var volume: Double
    var pitch: Double
    var speed: Double
    var currentTrackURL: URL?
    var playbackProgress: Int?

    static let `default` = PlayerState(
        volume: 1.0,
        pitch: 0.0,
        speed: 1.0,
        currentTrackURL: nil,
        playbackProgress: nil
    )
}
