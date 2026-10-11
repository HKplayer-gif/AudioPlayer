import Foundation
import AVFoundation

struct LibraryScanner {

    static func scanFile(fileURL: URL) async -> Track? {
        guard isSupportedAudioFile(fileURL) else {
            return nil
        }

        guard let values = try? fileURL.resourceValues(
            forKeys: [.isRegularFileKey]
        ),
        values.isRegularFile == true else {
            return nil
        }

        return await makeTrack(from: fileURL)
    }

    static func scan(folderURL: URL) async -> [Track] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var tracks: [Track] = []

        for url in contents {
            guard isSupportedAudioFile(url) else { continue }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            guard let track = await makeTrack(from: url) else { continue }
            tracks.append(track)
        }

        return tracks
    }

    private static func isSupportedAudioFile(_ url: URL) -> Bool {
        let supportedFormats: Set<String> = [
            "mp3", "wav", "flac", "ogg", "m4a", "aac", "aiff"
        ]
        return supportedFormats.contains(url.pathExtension.lowercased())
    }

    private static func makeTrack(from url: URL) async -> Track? {
        let asset = AVURLAsset(url: url)
        let duration: TimeInterval

        do {
            let loadedDuration = try await asset.load(.duration)
            duration = loadedDuration.seconds.isFinite && loadedDuration.seconds >= 0
                ? loadedDuration.seconds
                : 0.0
        } catch {
            return nil
        }

        let metadata = await metadataValues(from: asset)
        let fallbackTitle = url.deletingPathExtension().lastPathComponent

        return Track(
            id: url,
            title: metadata.title ?? fallbackTitle,
            artist: metadata.artist,
            album: metadata.album,
            fileFormat: url.pathExtension.lowercased(),
            duration: duration,
            filePath: url
        )
    }

    private static func metadataValues(from asset: AVAsset) async -> (
        title: String?, artist: String?, album: String?
    ) {
        var title: String?
        var artist: String?
        var album: String?

        guard let metadata = try? await asset.load(.commonMetadata) else {
            return (nil, nil, nil)
        }

        for item in metadata {
            guard let key = item.commonKey else { continue }
            switch key {
            case .commonKeyTitle:
                title = (try? await item.load(.stringValue)) ?? title
            case .commonKeyArtist:
                artist = (try? await item.load(.stringValue)) ?? artist
            case .commonKeyAlbumName:
                album = (try? await item.load(.stringValue)) ?? album
            default:
                break
            }
        }

        return (title, artist, album)
    }
}
