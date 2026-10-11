import Foundation
import Observation

@MainActor
@Observable
final class Browser {

    private let stateStore: StateStore
    private let stateFileName = "browser.json"

    private(set) var track: Track?

    init(stateStore: StateStore = StateStore()) {
        self.stateStore = stateStore
        Task { @MainActor in
            await restore()
        }
    }

    func select(_ url: URL) async -> Bool {
        guard let track = await LibraryScanner.scanFile(fileURL: url) else {
            return false
        }

        self.track = track
        save(url: track.filePath)
        return true
    }

    func clear() {
        guard track != nil else {
            return
        }

        track = nil
        try? stateStore.remove(stateFileName)
    }

    func refresh() async {
        guard let savedURL = stateStore.load(
            URL.self,
            from: stateFileName
        ) else {
            track = nil
            return
        }

        guard let track = await LibraryScanner.scanFile(
            fileURL: savedURL
        ) else {
            track = nil
            try? stateStore.remove(stateFileName)
            return
        }

        self.track = track
    }

    private func restore() async {
        guard let savedURL = stateStore.load(
            URL.self,
            from: stateFileName
        ) else {
            track = nil
            return
        }

        guard let track = await LibraryScanner.scanFile(
            fileURL: savedURL
        ) else {
            track = nil
            try? stateStore.remove(stateFileName)
            return
        }

        self.track = track
    }

    private func save(url: URL) {
        do {
            try stateStore.save(
                url,
                to: stateFileName
            )
        } catch {
            
        }
    }
}
