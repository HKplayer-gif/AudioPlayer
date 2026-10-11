import Foundation

enum AudioProcessingAlgorithm: String, Codable, CaseIterable, Equatable {
    case systemTimePitch
    case soundTouch
    case signalsmith

    var displayName: String {
        switch self {
        case .systemTimePitch:
            return "AVAudio"
        case .soundTouch:
            return "SoundTouch"
        case .signalsmith:
            return "Signalsmith Stretch"
        }
    }

    var isAvailable: Bool {
        true
    }
}
