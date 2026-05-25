//
//  Album.swift
//  iOSPhotoBrowser
//

import Foundation

struct Album: Identifiable, Hashable {
    static let unregisteredAlbumId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let unregisteredAlbumName = "未登録"

    let id: UUID
    var name: String
    let createdAt: Date
    var updatedAt: Date
    var coverImageId: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        coverImageId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.coverImageId = coverImageId
    }

    static var unregistered: Album {
        Album(
            id: unregisteredAlbumId,
            name: unregisteredAlbumName,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
    }

    var isUnregisteredSmartAlbum: Bool {
        id == Self.unregisteredAlbumId
    }
}
