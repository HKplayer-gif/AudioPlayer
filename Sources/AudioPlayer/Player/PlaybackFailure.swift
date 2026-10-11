import Foundation

enum PlaybackRequestOrigin {
    case directSelection
    case navigation
    case automaticAdvance
}

enum PlaybackFailure: Error {
    case fileUnavailable(URL)
    case playbackFailed(URL, Error)
}
