import Foundation
import Observation

struct HistoryRecord: Identifiable, Codable {
    let url: URL
    var lastPlayedAt: Date
    var id: URL { url }
}

@Observable
final class History {

    enum SortOrder {
        case nameAscending
        case nameDescending
        case lastPlayedAscending
        case lastPlayedDescending
    }

    private let stateStore: StateStore
    private let stateFileName = "history.json"

    private(set) var records: [HistoryRecord] = []

    private(set) var maximumCount: Int = 10

    var sortOrder: SortOrder = .nameAscending {
        didSet {
            
        }
    }
    init(
        maximumCount: Int = 10,
        stateStore: StateStore = StateStore()
    ) {
        self.maximumCount = max(maximumCount, 1)
        self.stateStore = stateStore
        restore()
    }

    func setMaximumCount(_ count: Int) {
        guard count > 0 else {
            return
        }

        maximumCount = count

        guard records.count > maximumCount else {
            return
        }

        enforceMaximumCount()
        save()
    }

    func record(_ url: URL) {

        let normalizedURL = url.standardizedFileURL
        let now = Date()

        if let index = records.firstIndex(
            where: { $0.url == normalizedURL }
        ) {
            records[index].lastPlayedAt = now
        } else {
            records.append(
                HistoryRecord(
                    url: normalizedURL,
                    lastPlayedAt: now
                )
            )
        }

        enforceMaximumCount()
        save()
    }

    func remove(_ url: URL) {

        let normalizedURL = url.standardizedFileURL

        let oldCount = records.count

        records.removeAll {
            $0.url == normalizedURL
        }

        guard records.count != oldCount else {
            return
        }

        save()
    }

    func clear() {

        guard !records.isEmpty else {
            return
        }

        records.removeAll()
        save()
    }

    func refresh() {

        let validRecords = records.filter {
            isValidFile($0.url)
        }

        guard validRecords.count != records.count else {
            return
        }

        records = validRecords
        save()
    }

    @discardableResult
    func validate(_ url: URL) -> Bool {

        let normalizedURL = url.standardizedFileURL

        guard records.contains(
            where: { $0.url == normalizedURL }
        ) else {
            return false
        }

        guard isValidFile(normalizedURL) else {

            remove(normalizedURL)

            return false
        }

        return true
    }

    var sortedRecords: [HistoryRecord] {

        switch sortOrder {

        case .nameAscending:

            return records.sorted {
                compareNames($0.url, $1.url)
                == .orderedAscending
            }

        case .nameDescending:

            return records.sorted {
                compareNames($0.url, $1.url)
                == .orderedDescending
            }

        case .lastPlayedAscending:

            return records.sorted {
                $0.lastPlayedAt < $1.lastPlayedAt
            }

        case .lastPlayedDescending:

            return records.sorted {
                $0.lastPlayedAt > $1.lastPlayedAt
            }
        }
    }

    private func enforceMaximumCount() {

        guard records.count > maximumCount else {
            return
        }

        records.sort {
            $0.lastPlayedAt > $1.lastPlayedAt
        }

        records = Array(
            records.prefix(maximumCount)
        )
    }

    private func restore() {

        guard let savedRecords = stateStore.load(
            [HistoryRecord].self,
            from: stateFileName
        ) else {

            records = []
            return
        }

        records = Array(
            savedRecords
                .map {
                    HistoryRecord(
                        url: $0.url.standardizedFileURL,
                        lastPlayedAt: $0.lastPlayedAt
                    )
                }
                .prefix(maximumCount)
        )

        enforceMaximumCount()
    }

    private func save() {

        do {

            try stateStore.save(
                records,
                to: stateFileName
            )

        } catch {

            
        }
    }

    private func isValidFile(
        _ url: URL
    ) -> Bool {

        var isDirectory: ObjCBool = false

        let exists = FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        )

        return exists && !isDirectory.boolValue
    }

    private func name(
        of url: URL
    ) -> String {

        url
            .deletingPathExtension()
            .lastPathComponent
    }

    private func compareNames(
        _ lhsURL: URL,
        _ rhsURL: URL
    ) -> ComparisonResult {

        let lhs = name(of: lhsURL)
        let rhs = name(of: rhsURL)

        return lhs.compare(
            rhs,
            options: [.caseInsensitive],
            range: nil,
            locale: Locale.current
        )
    }
}
