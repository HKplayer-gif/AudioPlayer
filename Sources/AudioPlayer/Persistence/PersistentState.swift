import Foundation

struct PersistentState: Codable {
    var player: PlayerState
    var app: AppState

    static let `default` = PersistentState(
        player: .default,
        app: .default
    )
}
