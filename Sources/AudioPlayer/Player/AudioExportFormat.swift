import Foundation

enum AudioExportFormat: String, CaseIterable, Identifiable {
    case wav
    case aiff
    case m4a
    case mp3
    case flac
    case ogg
    case aac

    var id: Self { self }

    var displayName: String {
        switch self {
        case .wav:
            return "WAV"
        case .aiff:
            return "AIFF"
        case .m4a:
            return "M4A (AAC)"
        case .mp3:
            return "MP3"
        case .flac:
            return "FLAC"
        case .ogg:
            return "OGG (Vorbis)"
        case .aac:
            return "AAC"
        }
    }

    var fileExtension: String {
        switch self {
        case .wav:
            return "wav"
        case .aiff:
            return "aiff"
        case .m4a:
            return "m4a"
        case .mp3:
            return "mp3"
        case .flac:
            return "flac"
        case .ogg:
            return "ogg"
        case .aac:
            return "aac"
        }
    }

    var fileType: String {
        switch self {
        case .wav:
            return "wav"
        case .aiff:
            return "aiff"
        case .m4a:
            return "m4a"
        case .mp3:
            return "mp3"
        case .flac:
            return "flac"
        case .ogg:
            return "ogg"
        case .aac:
            return "aac"
        }
    }
}

enum AudioExportError: LocalizedError {
    case noTrack
    case unsupportedAlgorithm
    case unsupportedFormat
    case invalidAudioFormat
    case codecBackendUnavailable
    case codecEncodingFailed(String)
    case renderFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .noTrack:
            return "There is no track available to export."
        case .unsupportedAlgorithm:
            return "The selected processing algorithm is not available for export."
        case .unsupportedFormat:
            return "This export format is not currently supported by the native exporter."
        case .invalidAudioFormat:
            return "The source audio format could not be converted to a supported PCM format."
        case .codecBackendUnavailable:
            return "The required export codec backend is not available on this Mac."
        case .codecEncodingFailed(let detail):
            return "The export codec failed: \(detail)"
        case .renderFailed:
            return "The processed audio could not be rendered."
        case .writeFailed:
            return "The rendered audio could not be written to the selected file."
        }
    }
}
