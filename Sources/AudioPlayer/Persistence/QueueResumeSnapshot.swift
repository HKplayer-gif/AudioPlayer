import Foundation

enum QueueSource: String, Codable {
    case library
    case history
    case singleFile
    case playlist
}

struct QueueResumeSnapshot: Codable {
    var version: Int
    var source: QueueSource
    var urls: [URL]
    var currentIndex: Int
    var currentURL: URL?
}
