//
//  Album.swift
//  iOSPhotoBrowser
//

import Foundation

struct Album: Identifiable, Hashable {
    static let favoritesAlbumId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    static let favoritesAlbumName = "お気に入り"
    static let unregisteredAlbumId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let unregisteredAlbumName = "未登録"
    static let reservedNames: Set<String> = [favoritesAlbumName, unregisteredAlbumName]

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

    static var favorites: Album {
        Album(
            id: favoritesAlbumId,
            name: favoritesAlbumName,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
    }

    var isFavoriteSmartAlbum: Bool {
        id == Self.favoritesAlbumId
    }

    var isUnregisteredSmartAlbum: Bool {
        id == Self.unregisteredAlbumId
    }

    var isSystemSmartAlbum: Bool {
        isFavoriteSmartAlbum || isUnregisteredSmartAlbum
    }
}
