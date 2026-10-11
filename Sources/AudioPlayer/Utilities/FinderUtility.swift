import AppKit

enum FinderUtility {

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting(
            [url.standardizedFileURL]
        )
    }
}
