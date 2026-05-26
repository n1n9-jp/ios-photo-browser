//
//  AlbumDetailViewModel.swift
//  iOSPhotoBrowser
//

import Foundation
import Combine

@MainActor
final class AlbumDetailViewModel: ObservableObject {
    @Published private(set) var photos: [PhotoItem] = []
    @Published private(set) var allAlbums: [Album] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSelectionMode = false
    @Published private(set) var selectedPhotoIDs: Set<UUID> = []
    @Published private(set) var isPerformingBatchAction = false
    @Published var showingAlbumSelector = false
    @Published var error: Error?
    @Published var showingError = false

    let album: Album
    private let albumRepository: AlbumRepositoryProtocol
    private let imageRepository: ImageRepositoryProtocol

    init(
        album: Album,
        albumRepository: AlbumRepositoryProtocol,
        imageRepository: ImageRepositoryProtocol
    ) {
        self.album = album
        self.albumRepository = albumRepository
        self.imageRepository = imageRepository
    }

    var canRemoveFromAlbum: Bool {
        !album.isSystemSmartAlbum
    }

    var canRemoveFavoriteFlag: Bool {
        album.isFavoriteSmartAlbum
    }

    var canBatchAddToAlbum: Bool {
        album.isUnregisteredSmartAlbum
    }

    var selectedPhotoCount: Int {
        selectedPhotoIDs.count
    }

    var hasSelection: Bool {
        !selectedPhotoIDs.isEmpty
    }

    var areAllPhotosSelected: Bool {
        !photos.isEmpty && selectedPhotoIDs.count == photos.count
    }

    func loadPhotos() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if album.isFavoriteSmartAlbum {
                photos = try await imageRepository.fetchFavorites()
            } else if album.isUnregisteredSmartAlbum {
                photos = try await imageRepository.fetchUnassignedImages()
            } else {
                photos = try await imageRepository.fetchImages(inAlbum: album.id)
            }
            selectedPhotoIDs = selectedPhotoIDs.intersection(Set(photos.map(\.id)))
            if selectedPhotoIDs.isEmpty && photos.isEmpty {
                isSelectionMode = false
            }
        } catch {
            self.error = error
            showingError = true
        }
    }

    func startSelectionMode() {
        guard canBatchAddToAlbum else { return }
        isSelectionMode = true
    }

    func cancelSelection() {
        isSelectionMode = false
        selectedPhotoIDs.removeAll()
    }

    func toggleSelection(for photo: PhotoItem) {
        if selectedPhotoIDs.contains(photo.id) {
            selectedPhotoIDs.remove(photo.id)
        } else {
            selectedPhotoIDs.insert(photo.id)
        }
    }

    func isSelected(_ photo: PhotoItem) -> Bool {
        selectedPhotoIDs.contains(photo.id)
    }

    func toggleSelectAll() {
        if areAllPhotosSelected {
            selectedPhotoIDs.removeAll()
        } else {
            selectedPhotoIDs = Set(photos.map(\.id))
        }
    }

    func openAlbumSelector() async {
        guard hasSelection else { return }

        do {
            allAlbums = try await albumRepository.fetchAll()
            showingAlbumSelector = true
        } catch {
            self.error = error
            showingError = true
        }
    }

    func addSelectedPhotos(to destinationAlbum: Album) async {
        guard hasSelection else { return }

        isPerformingBatchAction = true
        defer { isPerformingBatchAction = false }

        do {
            for photoId in selectedPhotoIDs {
                try await albumRepository.addImage(photoId, to: destinationAlbum.id)
            }
            showingAlbumSelector = false
            cancelSelection()
            await loadPhotos()
        } catch {
            self.error = error
            showingError = true
        }
    }

    func removeImage(_ photo: PhotoItem) async {
        guard canRemoveFromAlbum else { return }

        do {
            try await albumRepository.removeImage(photo.id, from: album.id)
            photos.removeAll { $0.id == photo.id }
        } catch {
            self.error = error
            showingError = true
        }
    }

    func removeFavorite(_ photo: PhotoItem) async {
        guard canRemoveFavoriteFlag else { return }

        do {
            try await imageRepository.setFavorite(false, for: photo.id)
            photos.removeAll { $0.id == photo.id }
        } catch {
            self.error = error
            showingError = true
        }
    }
}
