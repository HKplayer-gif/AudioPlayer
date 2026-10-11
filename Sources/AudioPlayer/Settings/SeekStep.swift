import Foundation

enum SeekStep: Int, Codable, CaseIterable, Equatable {
    case fiveSeconds = 5
    case tenSeconds = 10
    case fifteenSeconds = 15

    var seconds: TimeInterval {
        TimeInterval(rawValue)
    }

    var displayName: String {
        "\(rawValue)s"
    }
}
