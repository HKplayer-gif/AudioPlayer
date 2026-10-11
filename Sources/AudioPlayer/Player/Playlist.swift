import Foundation

struct PlaylistItem: Identifiable, Codable {

    let id: UUID

    var url: URL

    init(
        id: UUID = UUID(),
        url: URL
    ) {
        self.id = id
        self.url = url.standardizedFileURL
    }
}

struct Playlist: Identifiable, Codable {

    let id: UUID

    var name: String

    var items: [PlaylistItem]

    init(
        id: UUID,
        name: String,
        items: [PlaylistItem]
    ) {
        self.id = id
        self.name = name
        self.items = items
    }

    init(
        id: UUID = UUID(),
        name: String,
        urls: [URL]
    ) {
        self.id = id
        self.name = name
        self.items = urls.map {
            PlaylistItem(url: $0)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case items
        case urls
    }

    init(from decoder: Decoder) throws {

        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        id = try container.decode(
            UUID.self,
            forKey: .id
        )

        name = try container.decode(
            String.self,
            forKey: .name
        )

        if let items = try container.decodeIfPresent(
            [PlaylistItem].self,
            forKey: .items
        ) {
            self.items = items
            return
        }

        let urls = try container.decodeIfPresent(
            [URL].self,
            forKey: .urls
        ) ?? []

        self.items = urls.map {
            PlaylistItem(url: $0)
        }
    }

    func encode(
        to encoder: Encoder
    ) throws {

        var container = encoder.container(
            keyedBy: CodingKeys.self
        )

        try container.encode(
            id,
            forKey: .id
        )

        try container.encode(
            name,
            forKey: .name
        )

        try container.encode(
            items,
            forKey: .items
        )
    }
}
