import Foundation
import Observation

@Observable
final class SelectedFolderHistory {

    struct Entry: Codable, Identifiable, Hashable {
        let id: URL
        let url: URL
        var lastSelectedAt: Date
        var isPinned: Bool
        var pinnedAt: Date?

        init(
            url: URL,
            lastSelectedAt: Date = Date(),
            isPinned: Bool = false,
            pinnedAt: Date? = nil
        ) {
            let standardizedURL = url.standardizedFileURL
            self.id = standardizedURL
            self.url = standardizedURL
            self.lastSelectedAt = lastSelectedAt
            self.isPinned = isPinned
            self.pinnedAt = pinnedAt
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case url
            case lastSelectedAt
            case isPinned
            case pinnedAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(
                keyedBy: CodingKeys.self
            )

            self.id = try container.decode(URL.self, forKey: .id)
            self.url = try container.decode(URL.self, forKey: .url)
            self.lastSelectedAt = try container.decode(
                Date.self,
                forKey: .lastSelectedAt
            )
            self.isPinned = try container.decode(
                Bool.self,
                forKey: .isPinned
            )
            self.pinnedAt = try container.decodeIfPresent(
                Date.self,
                forKey: .pinnedAt
            )
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(
                keyedBy: CodingKeys.self
            )

            try container.encode(id, forKey: .id)
            try container.encode(url, forKey: .url)
            try container.encode(
                lastSelectedAt,
                forKey: .lastSelectedAt
            )
            try container.encode(
                isPinned,
                forKey: .isPinned
            )
            try container.encodeIfPresent(
                pinnedAt,
                forKey: .pinnedAt
            )
        }
    }

    private struct StoredState: Codable {
        var entries: [Entry]
        var fallbackEntry: Entry?
    }

    private let stateStore: StateStore
    private let stateFileName = "selected-folder-history.json"

    private(set) var entries: [Entry] = []
    private(set) var fallbackEntry: Entry?

    static let maximumRecentCount = 4

    init(stateStore: StateStore = StateStore()) {
        self.stateStore = stateStore
        restore()
    }

    var recentEntries: [Entry] {
        entries
    }

    func recordSelection(_ url: URL) {
        let standardizedURL = url.standardizedFileURL

        // A fallback entry is only allowed when all visible
        // Recent Folder positions are occupied by pinned entries.
        if allRecentEntriesArePinned {

            if let index = entries.firstIndex(
                where: { $0.url == standardizedURL }
            ) {
                entries[index].lastSelectedAt = Date()
                fallbackEntry = nil
            } else {

                fallbackEntry = Entry(
                    url: standardizedURL
                )
            }

            save()
            return
        }

        // Normal four-slot Recent Folder behavior.
        fallbackEntry = nil

        if let index = entries.firstIndex(
            where: { $0.url == standardizedURL }
        ) {
            entries[index].lastSelectedAt = Date()
        } else {
            entries.append(
                Entry(url: standardizedURL)
            )
        }

        normalize()
        save()
    }

    func pin(_ url: URL) {
        let standardizedURL = url.standardizedFileURL

        guard let index = entries.firstIndex(
            where: { $0.url == standardizedURL }
        ) else {
            return
        }

        entries[index].isPinned = true
        entries[index].pinnedAt = Date()

        normalize()
        save()
    }

    func unpin(_ url: URL) {
        let standardizedURL = url.standardizedFileURL

        guard let index = entries.firstIndex(
            where: { $0.url == standardizedURL }
        ) else {
            return
        }

        entries[index].isPinned = false
        entries[index].pinnedAt = nil

        normalize()
        save()
    }

    func delete(_ url: URL) {
        let standardizedURL = url.standardizedFileURL

        entries.removeAll {
            $0.url == standardizedURL
        }

        if fallbackEntry?.url == standardizedURL {
            fallbackEntry = nil
        }

        normalize()
        save()
    }

    func clearAll() {
        entries.removeAll()
        fallbackEntry = nil
        save()
    }

    func contains(_ url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL

        if entries.contains(where: {
            $0.url == standardizedURL
        }) {
            return true
        }

        return fallbackEntry?.url == standardizedURL
    }

    func isPinned(_ url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL

        return entries.first {
            $0.url == standardizedURL
        }?.isPinned ?? false
    }

    private var allRecentEntriesArePinned: Bool {
        entries.count == Self.maximumRecentCount &&
        entries.allSatisfy { $0.isPinned }
    }

    private func normalize() {

        entries.sort { lhs, rhs in

            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }

            if lhs.isPinned && rhs.isPinned {
                return (
                    lhs.pinnedAt ?? lhs.lastSelectedAt
                ) > (
                    rhs.pinnedAt ?? rhs.lastSelectedAt
                )
            }

            return lhs.lastSelectedAt > rhs.lastSelectedAt
        }

        let pinnedEntries = entries.filter {
            $0.isPinned
        }

        let unpinnedEntries = entries.filter {
            !$0.isPinned
        }

        // There is normally room for four Recent entries.
        let remainingCapacity =
            max(
                0,
                Self.maximumRecentCount - pinnedEntries.count
            )

        let retainedUnpinned =
            Array(
                unpinnedEntries.prefix(remainingCapacity)
            )

        entries = pinnedEntries + retainedUnpinned

        // If the four visible positions are no longer
        // completely pinned, the hidden fallback can return
        // to normal Recent history.
        if !allRecentEntriesArePinned,
           let fallbackEntry {

            if !entries.contains(where: {
                $0.url == fallbackEntry.url
            }) {

                entries.append(
                    Entry(
                        url: fallbackEntry.url,
                        lastSelectedAt: fallbackEntry.lastSelectedAt,
                        isPinned: false
                    )
                )
            }

            self.fallbackEntry = nil

            entries.sort { lhs, rhs in

                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned && !rhs.isPinned
                }

                if lhs.isPinned && rhs.isPinned {
                    return (
                        lhs.pinnedAt ?? lhs.lastSelectedAt
                    ) > (
                        rhs.pinnedAt ?? rhs.lastSelectedAt
                    )
                }

                return lhs.lastSelectedAt > rhs.lastSelectedAt
            }

            let pinned = entries.filter {
                $0.isPinned
            }

            let unpinned = entries.filter {
                !$0.isPinned
            }

            let capacity =
                max(
                    0,
                    Self.maximumRecentCount - pinned.count
                )

            entries =
                pinned +
                Array(unpinned.prefix(capacity))
        }
    }

    private func restore() {

        guard let storedState = stateStore.load(
            StoredState.self,
            from: stateFileName
        ) else {
            entries = []
            fallbackEntry = nil
            return
        }

        entries = storedState.entries
        fallbackEntry = storedState.fallbackEntry

        normalize()
    }

    private func save() {

        do {
            try stateStore.save(
                StoredState(
                    entries: entries,
                    fallbackEntry: fallbackEntry
                ),
                to: stateFileName
            )
        } catch {
            
        }
    }
}
