import Foundation
import Observation

struct PlaylistAddResult {
    let failedURLs: [URL]
    let duplicateURLs: [URL]
}

@MainActor
@Observable
final class PlaylistStore {

    static let maximumPlaylistCount = 10

    private let stateStore: StateStore
    private let stateFileName = "playlists.json"

    private(set) var playlists: [Playlist]

    private(set) var unavailableURLs: [UUID: Set<URL>] = [:]

    init(stateStore: StateStore = StateStore()) {

        self.stateStore = stateStore

        self.playlists =
            stateStore.load(
                [Playlist].self,
                from: stateFileName
            ) ?? []

        if playlists.count > Self.maximumPlaylistCount {

            playlists = Array(
                playlists.prefix(Self.maximumPlaylistCount)
            )

            save()
        }

        refreshAll()
    }

    func playlist(
        with id: UUID
    ) -> Playlist? {

        playlists.first {
            $0.id == id
        }
    }

    @discardableResult
    func create(
        name: String
    ) -> Playlist? {

        guard playlists.count
                < Self.maximumPlaylistCount
        else {
            return nil
        }

        let trimmedName =
            name.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        let playlist = Playlist(
            id: UUID(),
            name:
                trimmedName.isEmpty
                ? "Playlist \(playlists.count + 1)"
                : trimmedName,
            items: []
        )

        playlists.append(playlist)

        unavailableURLs[playlist.id] = []

        save()

        return playlist
    }

    func rename(
        _ id: UUID,
        to name: String
    ) {

        guard let index =
                playlists.firstIndex(where: {
                    $0.id == id
                })
        else {
            return
        }

        let trimmedName =
            name.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !trimmedName.isEmpty else {
            return
        }

        playlists[index].name = trimmedName

        save()
    }

    func delete(
        _ id: UUID
    ) {

        playlists.removeAll {
            $0.id == id
        }

        unavailableURLs.removeValue(
            forKey: id
        )

        save()
    }

    func deleteAll() {
        guard !playlists.isEmpty else {
            return
        }

        playlists.removeAll()
        unavailableURLs.removeAll()
        save()
    }

    func clear(
        _ id: UUID
    ) {

        guard let index =
                playlists.firstIndex(where: {
                    $0.id == id
                })
        else {
            return
        }

        playlists[index].items.removeAll()

        unavailableURLs[id] = []

        save()
    }

    @discardableResult
    func add(
        _ urls: [URL],
        to playlistID: UUID,
        allowsDuplicates: Bool
    ) async -> PlaylistAddResult {
        guard let index =
                playlists.firstIndex(where: {
                    $0.id == playlistID
                })
        else {
            return PlaylistAddResult(
                failedURLs: urls,
                duplicateURLs: []
            )
        }

        var failedURLs: [URL] = []
        var duplicateURLs: [URL] = []

        var existingURLs = Set(
            playlists[index].items.map {
                normalizedURL($0.url)
            }
        )

        for url in urls {
            let normalized = normalizedURL(url)

            guard await LibraryScanner.scanFile(fileURL: url) != nil else {
                failedURLs.append(url)
                continue
            }

            if !allowsDuplicates && existingURLs.contains(normalized) {
                duplicateURLs.append(url)
                continue
            }

            playlists[index].items.append(
                PlaylistItem(
                    url: normalized
                )
            )

            existingURLs.insert(normalized)
        }

        refresh(playlistID)
        save()

        return PlaylistAddResult(
            failedURLs: failedURLs,
            duplicateURLs: duplicateURLs
        )
    }


    func remove(
        _ itemIDs: [UUID],
        from playlistID: UUID
    ) {

        guard let index =
                playlists.firstIndex(where: {
                    $0.id == playlistID
                })
        else {
            return
        }

        let targets = Set(itemIDs)

        playlists[index].items.removeAll {
            targets.contains($0.id)
        }

        refresh(playlistID)

        save()
    }

    func moveToTop(
        _ itemIDs: [UUID],
        in playlistID: UUID
    ) {

        move(
            itemIDs,
            in: playlistID,
            toTop: true
        )
    }

    func moveToBottom(
        _ itemIDs: [UUID],
        in playlistID: UUID
    ) {

        move(
            itemIDs,
            in: playlistID,
            toTop: false
        )
    }

    func movePlaylistToTop(
        _ playlistID: UUID
    ) {

        guard let index =
                playlists.firstIndex(where: {
                    $0.id == playlistID
                })
        else {
            return
        }

        guard index > 0 else {
            return
        }

        let playlist = playlists.remove(
            at: index
        )

        playlists.insert(
            playlist,
            at: 0
        )

        save()
    }

    func movePlaylistToBottom(
        _ playlistID: UUID
    ) {

        guard let index =
                playlists.firstIndex(where: {
                    $0.id == playlistID
                })
        else {
            return
        }

        guard index < playlists.count - 1 else {
            return
        }

        let playlist = playlists.remove(
            at: index
        )

        playlists.append(
            playlist
        )

        save()
    }

    func refreshAll() {

        for playlist in playlists {
            refresh(playlist.id)
        }
    }

    func refresh(
        _ playlistID: UUID
    ) {

        guard let playlist =
                playlist(with: playlistID)
        else {
            return
        }

        var unavailable: Set<URL> = []

        for item in playlist.items {

            let url = item.url

            var isDirectory: ObjCBool = false

            let exists =
                FileManager.default.fileExists(
                    atPath: url.path,
                    isDirectory: &isDirectory
                )

            if !exists || isDirectory.boolValue {

                unavailable.insert(
                    normalizedURL(url)
                )
            }
        }

        unavailableURLs[playlistID] =
            unavailable
    }

    func removeMissing(
        from playlistID: UUID
    ) {

        refresh(playlistID)

        guard let index =
                playlists.firstIndex(where: {
                    $0.id == playlistID
                })
        else {
            return
        }

        let missing =
            unavailableURLs[playlistID] ?? []

        guard !missing.isEmpty else {
            return
        }

        playlists[index].items.removeAll {
            missing.contains(
                normalizedURL($0.url)
            )
        }

        refresh(playlistID)

        save()
    }

    func isUnavailable(
        _ url: URL,
        in playlistID: UUID
    ) -> Bool {

        unavailableURLs[playlistID]?.contains(
            normalizedURL(url)
        ) ?? false
    }

    private func move(
        _ itemIDs: [UUID],
        in playlistID: UUID,
        toTop: Bool
    ) {

        guard let index =
                playlists.firstIndex(where: {
                    $0.id == playlistID
                })
        else {
            return
        }

        let selected = Set(itemIDs)

        guard !selected.isEmpty else {
            return
        }

        let current =
            playlists[index].items

        let selectedItems =
            current.filter {
                selected.contains($0.id)
            }

        guard !selectedItems.isEmpty else {
            return
        }

        let remaining =
            current.filter {
                !selected.contains($0.id)
            }

        playlists[index].items =
            toTop
            ? selectedItems + remaining
            : remaining + selectedItems

        save()
    }

    private func normalizedURL(
        _ url: URL
    ) -> URL {

        url.standardizedFileURL
    }

    private func save() {

        do {

            try stateStore.save(
                playlists,
                to: stateFileName
            )

        } catch {

            
        }
    }
}
