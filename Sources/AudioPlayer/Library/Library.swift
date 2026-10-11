import Foundation
import Observation

@MainActor
@Observable
final class Library {

    enum SortOrder {
        case nameAscending
        case nameDescending
    }

    private(set) var tracks: [Track] = []

    var sortOrder: SortOrder = .nameAscending

    var sortedTracks: [Track] {
        switch sortOrder {
        case .nameAscending:
            return tracks.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title)
                    == .orderedAscending
            }

        case .nameDescending:
            return tracks.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title)
                    == .orderedDescending
            }
        }
    }

    func remove(_ url: URL) {
        let normalizedURL = url.standardizedFileURL
        tracks.removeAll {
            $0.filePath.standardizedFileURL == normalizedURL
        }
    }


    func clear() {
        tracks.removeAll()
    }

    func refresh(from folderURL: URL) async {
        tracks = await LibraryScanner.scan(folderURL: folderURL)
        applySorting()
    }

    private func applySorting() {
        tracks.sort { lhs, rhs in
            let result = lhs.title.localizedCaseInsensitiveCompare(rhs.title)

            switch sortOrder {
            case .nameAscending:
                return result == .orderedAscending

            case .nameDescending:
                return result == .orderedDescending
            }
        }
    }
}
