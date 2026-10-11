import Foundation

struct AppState: Codable {

    var sidebarSection: String?

    var nowPlayingSection: String?
    var settingsSection: String?
    var librarySource: String?
    var librarySortOrder: String?
    var historySortOrder: String?
    var playbackMode: String?

    static let `default` = AppState(
        sidebarSection: nil,
        nowPlayingSection: "currentlyPlaying",
        settingsSection: "nowPlaying",
        librarySource: "history",
        librarySortOrder: "nameAscending",
        historySortOrder: "nameAscending",
        playbackMode: "single"
    )
}
