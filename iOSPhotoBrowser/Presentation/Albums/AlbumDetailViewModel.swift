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
    @Published private(set) var album: Album
    @Published private(set) var isLoading = false
    @Published private(set) var isSelectionMode = false
    @Published private(set) var selectedPhotoIDs: Set<UUID> = []
    @Published private(set) var isPerformingBatchAction = false
    @Published var showingAlbumSelector = false
    @Published var error: Error?
    @Published var showingError = false

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

    var canMovePhotosToAnotherAlbum: Bool {
        !album.isSystemSmartAlbum
    }

    var canSelectPhotosForAlbumAction: Bool {
        album.isUnregisteredSmartAlbum || canMovePhotosToAnotherAlbum
    }

    var canSetCoverImage: Bool {
        !album.isSystemSmartAlbum
    }

    var canRenameAlbum: Bool {
        !album.isSystemSmartAlbum
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

    var albumSelectorTitle: String {
        canMovePhotosToAnotherAlbum ? "アルバムへ移動" : "アルバムに追加"
    }

    var albumSelectorSectionTitle: String {
        canMovePhotosToAnotherAlbum ? "移動先のアルバム" : "追加先のアルバム"
    }

    var albumActionButtonTitle: String {
        canMovePhotosToAnotherAlbum ? "アルバム移動" : "アルバム追加"
    }

    var albumActionProgressTitle: String {
        canMovePhotosToAnotherAlbum ? "移動中..." : "追加中..."
    }

    func loadPhotos() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if canSetCoverImage, let latestAlbum = try await albumRepository.fetch(byId: album.id) {
                album = latestAlbum
            }

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
        guard canSelectPhotosForAlbumAction else { return }
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

    func openAlbumSelector(preselectedPhotoIDs: Set<UUID>? = nil) async {
        if let preselectedPhotoIDs {
            selectedPhotoIDs = preselectedPhotoIDs
        }

        guard hasSelection else { return }

        do {
            let albums = try await albumRepository.fetchAll()
            if canMovePhotosToAnotherAlbum {
                allAlbums = albums.filter { $0.id != album.id }
            } else {
                allAlbums = albums
            }
            showingAlbumSelector = true
        } catch {
            self.error = error
            showingError = true
        }
    }

    func applySelectedPhotosToAlbum(_ destinationAlbum: Album) async {
        guard hasSelection else { return }

        isPerformingBatchAction = true
        defer { isPerformingBatchAction = false }

        do {
            for photoId in selectedPhotoIDs {
                try await albumRepository.addImage(photoId, to: destinationAlbum.id)
                if canMovePhotosToAnotherAlbum {
                    try await albumRepository.removeImage(photoId, from: album.id)
                }
            }
            showingAlbumSelector = false
            cancelSelection()
            await loadPhotos()
        } catch {
            self.error = error
            showingError = true
        }
    }

    func movePhotoToAnotherAlbum(_ photo: PhotoItem) async {
        guard canMovePhotosToAnotherAlbum else { return }
        await openAlbumSelector(preselectedPhotoIDs: Set([photo.id]))
    }

    func setCoverImage(_ photo: PhotoItem) async {
        guard canSetCoverImage else { return }

        var updatedAlbum = album
        updatedAlbum.coverImageId = photo.id
        updatedAlbum.updatedAt = Date()

        do {
            try await albumRepository.update(updatedAlbum)
            album = updatedAlbum
        } catch {
            self.error = error
            showingError = true
        }
    }

    func renameAlbum(to name: String) async -> Bool {
        guard canRenameAlbum else { return false }

        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            error = AlbumRenameValidationError.emptyName
            showingError = true
            return false
        }

        guard !Album.reservedNames.contains(normalizedName) else {
            error = AlbumRenameValidationError.reservedName
            showingError = true
            return false
        }

        if normalizedName == album.name {
            return true
        }

        var updatedAlbum = album
        updatedAlbum.name = normalizedName
        updatedAlbum.updatedAt = Date()

        do {
            try await albumRepository.update(updatedAlbum)
            album = updatedAlbum
            return true
        } catch {
            self.error = error
            showingError = true
            return false
        }
    }

    func isCoverImage(_ photo: PhotoItem) -> Bool {
        album.coverImageId == photo.id
    }

    func removeImage(_ photo: PhotoItem) async {
        guard canRemoveFromAlbum else { return }

        do {
            try await albumRepository.removeImage(photo.id, from: album.id)
            photos.removeAll { $0.id == photo.id }
            if let latestAlbum = try await albumRepository.fetch(byId: album.id) {
                album = latestAlbum
            }
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


private enum AlbumRenameValidationError: LocalizedError {
    case emptyName
    case reservedName

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "アルバム名を入力してください"
        case .reservedName:
            return "「お気に入り」「未登録」はシステム用アルバム名のため使用できません"
        }
    }
}
