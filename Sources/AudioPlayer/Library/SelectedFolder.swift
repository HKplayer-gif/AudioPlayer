import Foundation
import Observation

@Observable
final class SelectedFolder {

    private let stateStore: StateStore
    private let stateFileName = "selected-folder.json"

    let history: SelectedFolderHistory

    private(set) var folderURL: URL?
    private(set) var folderWasNotFound = false

    init(
        stateStore: StateStore = StateStore(),
        history: SelectedFolderHistory? = nil
    ) {
        self.stateStore = stateStore
        self.history = history ?? SelectedFolderHistory(
            stateStore: stateStore
        )
        restore()
    }

    var folderName: String {
        folderURL?.lastPathComponent ?? "No Folder Selected"
    }

    var hasFolder: Bool {
        folderURL != nil
    }

    func select(_ url: URL) throws {

        guard isValidFolder(url) else {
            throw SelectedFolderError.invalidFolder
        }

        let standardizedURL = url.standardizedFileURL

        folderURL = standardizedURL
        folderWasNotFound = false

        try save()

        history.recordSelection(standardizedURL)
    }

    func refresh() -> Bool {

        guard let folderURL else {
            return false
        }

        guard isValidFolder(folderURL) else {

            self.folderURL = nil
            folderWasNotFound = true

            try? save()

            return false
        }

        return true
    }

    func clearSelection() {

        folderURL = nil
        folderWasNotFound = false

        try? save()
    }

    func clearFolderNotFoundState() {
        folderWasNotFound = false
    }

    private func restore() {

        guard let savedURL = stateStore.load(
            URL.self,
            from: stateFileName
        ) else {

            folderURL = nil
            folderWasNotFound = false

            return
        }

        guard isValidFolder(savedURL) else {

            folderURL = nil
            folderWasNotFound = true

            try? save()

            return
        }

        folderURL = savedURL.standardizedFileURL
        folderWasNotFound = false

        if !history.contains(folderURL!) {
            history.recordSelection(folderURL!)
        }
    }

    private func save() throws {

        if let folderURL {

            try stateStore.save(
                folderURL,
                to: stateFileName
            )

        } else {

            try stateStore.remove(stateFileName)
        }
    }

    private func isValidFolder(_ url: URL) -> Bool {

        var isDirectory: ObjCBool = false

        let exists = FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        )

        return exists && isDirectory.boolValue
    }
}

enum SelectedFolderError: LocalizedError {

    case invalidFolder

    var errorDescription: String? {

        switch self {

        case .invalidFolder:
            return "The selected location is not a valid folder."
        }
    }
}
