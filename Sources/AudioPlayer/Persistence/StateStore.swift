import Foundation

final class StateStore {
    private let directoryURL: URL

    private static let migratedFileNames: Set<String> = [
        "state.json",
        "queue-resume.json",
        "selected-folder.json",
        "selected-folder-history.json",
        "browser.json",
        "history.json",
        "playlists.json",
        "pitch-cycles.json"
    ]

    private static var applicationSupportDirectory: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
    }

    private static var appDirectoryName: String {
        Bundle.main.bundleIdentifier == "com.audioplayer.internal-test"
            ? "AudioPlayer-Internal-Test"
            : "AudioPlayer"
    }

    static var userDataDirectoryURL: URL {
        applicationSupportDirectory
            .appendingPathComponent(appDirectoryName, isDirectory: true)
            .appendingPathComponent("User Data", isDirectory: true)
    }

    private static var legacyDirectoryURL: URL {
        applicationSupportDirectory
            .appendingPathComponent(appDirectoryName, isDirectory: true)
    }

    init() {
        directoryURL = Self.userDataDirectoryURL
    }

    func load<T: Decodable>(
        _ type: T.Type,
        from fileName: String
    ) -> T? {
        let fileURL = directoryURL.appendingPathComponent(fileName)

        if let data = try? Data(contentsOf: fileURL) {
            return try? JSONDecoder().decode(T.self, from: data)
        }

        guard Self.migratedFileNames.contains(fileName) else {
            return nil
        }

        let legacyURL = Self.legacyDirectoryURL
            .appendingPathComponent(fileName)

        guard let data = try? Data(contentsOf: legacyURL),
              let value = try? JSONDecoder().decode(T.self, from: data) else {
            return nil
        }

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try data.write(
                to: fileURL,
                options: .atomic
            )
            try FileManager.default.removeItem(at: legacyURL)
        } catch {
            
        }

        return value
    }

    func save<T: Encodable>(
        _ value: T,
        to fileName: String
    ) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let data = try JSONEncoder().encode(value)
        let fileURL = directoryURL.appendingPathComponent(fileName)

        try data.write(to: fileURL, options: .atomic)
    }

    func remove(_ fileName: String) throws {
        let fileURL = directoryURL.appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: fileURL)
    }

    static func deleteAllUserData() throws {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: userDataDirectoryURL.path) {
            try fileManager.removeItem(at: userDataDirectoryURL)
        }

        let legacyDirectory = legacyDirectoryURL

        for fileName in migratedFileNames + ["User Settings.json"] {
            let url = legacyDirectory.appendingPathComponent(fileName)

            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }
}
