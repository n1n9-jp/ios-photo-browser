//
//  AlbumsViewModel.swift
//  iOSPhotoBrowser
//

import Foundation
import Combine

@MainActor
final class AlbumsViewModel: ObservableObject {
    @Published private(set) var albums: [Album] = []
    @Published private(set) var albumImageCounts: [UUID: Int] = [:]
    @Published private(set) var favoriteAlbumCount = 0
    @Published private(set) var unregisteredAlbumCount = 0
    @Published private(set) var isLoading = false
    @Published var showingCreateSheet = false
    @Published var newAlbumName = ""
    @Published var error: Error?
    @Published var showingError = false

    private let albumRepository: AlbumRepositoryProtocol
    private let imageRepository: ImageRepositoryProtocol

    init(
        albumRepository: AlbumRepositoryProtocol,
        imageRepository: ImageRepositoryProtocol
    ) {
        self.albumRepository = albumRepository
        self.imageRepository = imageRepository
    }

    var displayedAlbums: [Album] {
        var displayed: [Album] = []
        if favoriteAlbumCount > 0 {
            displayed.append(.favorites)
        }
        if unregisteredAlbumCount > 0 {
            displayed.append(.unregistered)
        }
        return displayed + albums
    }

    var canCreateAlbum: Bool {
        let name = normalizedNewAlbumName
        return !name.isEmpty && !Album.reservedNames.contains(name)
    }

    func loadAlbums() async {
        isLoading = true
        defer { isLoading = false }

        do {
            albums = try await albumRepository.fetchAll()
            albumImageCounts.removeAll()

            // Load image counts for each album
            for album in albums {
                let count = try await albumRepository.fetchImageCount(for: album.id)
                albumImageCounts[album.id] = count
            }

            favoriteAlbumCount = try await imageRepository.fetchFavoriteCount()
            albumImageCounts[Album.favoritesAlbumId] = favoriteAlbumCount
            unregisteredAlbumCount = try await imageRepository.fetchUnassignedImageCount()
            albumImageCounts[Album.unregisteredAlbumId] = unregisteredAlbumCount
        } catch {
            self.error = error
            showingError = true
        }
    }

    func createAlbum() async {
        guard !normalizedNewAlbumName.isEmpty else { return }
        guard canCreateAlbum else {
            error = AlbumValidationError.reservedName
            showingError = true
            return
        }

        let album = Album(name: normalizedNewAlbumName)

        do {
            try await albumRepository.save(album)
            await loadAlbums()
            newAlbumName = ""
            showingCreateSheet = false
        } catch {
            self.error = error
            showingError = true
        }
    }

    func deleteAlbum(_ album: Album) async {
        do {
            try await albumRepository.delete(album)
            await loadAlbums()
        } catch {
            self.error = error
            showingError = true
        }
    }

    func updateAlbum(_ album: Album, name: String) async {
        var updatedAlbum = album
        updatedAlbum.name = name
        updatedAlbum.updatedAt = Date()

        do {
            try await albumRepository.update(updatedAlbum)
            await loadAlbums()
        } catch {
            self.error = error
            showingError = true
        }
    }

    private var normalizedNewAlbumName: String {
        newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum AlbumValidationError: LocalizedError {
    case reservedName

    var errorDescription: String? {
        switch self {
        case .reservedName:
            return "「お気に入り」「未登録」はシステム用アルバム名のため作成できません"
        }
    }
}
