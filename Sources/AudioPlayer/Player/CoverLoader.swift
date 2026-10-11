import Foundation
import AVFoundation

struct CoverLoader {
    static func load(from url: URL) async -> Cover? {
        let asset = AVURLAsset(url: url)

        guard let metadata = try? await asset.load(.commonMetadata) else {
            return nil
        }

        for item in metadata {
            guard item.commonKey == .commonKeyArtwork else { continue }
            if let data = try? await item.load(.dataValue),
               !data.isEmpty {
                return Cover(data: data)
            }
        }

        return nil
    }
}
