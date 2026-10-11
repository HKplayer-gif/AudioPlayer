import Foundation

enum ProgressSaveMode: String, Codable {
    case never
    case everySecond
    case everyFiveSeconds
    case everyTenSeconds
}