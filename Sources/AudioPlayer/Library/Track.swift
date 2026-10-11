import Foundation

struct Track: Identifiable {
    let id: URL
    let title: String
    let artist: String?
    let album: String?
    let fileFormat: String
    let duration: TimeInterval
    let filePath: URL
}
