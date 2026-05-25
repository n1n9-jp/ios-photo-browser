//
//  LibraryViewModel.swift
//  iOSPhotoBrowser
//

import Foundation
import Combine

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var photos: [PhotoItem] = []
    @Published private(set) var allAlbums: [Album] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSelectionMode = false
    @Published private(set) var selectedPhotoIDs: Set<UUID> = []
    @Published private(set) var isPerformingBatchAction = false
    @Published var sortOption: SortOption = .importedAtDescending
    @Published var newTagName = ""
    @Published var showingDeleteConfirmation = false
    @Published var showingTagEditor = false
    @Published var showingAlbumSelector = false
    @Published var error: Error?
    @Published var showingError = false

    private let imageRepository: ImageRepositoryProtocol
    private let tagRepository: TagRepositoryProtocol
    private let albumRepository: AlbumRepositoryProtocol
    private let deleteImageUseCase: DeleteImageUseCase

    init(
        imageRepository: ImageRepositoryProtocol,
        tagRepository: TagRepositoryProtocol,
        albumRepository: AlbumRepositoryProtocol,
        deleteImageUseCase: DeleteImageUseCase
    ) {
        self.imageRepository = imageRepository
        self.tagRepository = tagRepository
        self.albumRepository = albumRepository
        self.deleteImageUseCase = deleteImageUseCase
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
            photos = try await imageRepository.fetchAll(sortedBy: sortOption)
            selectedPhotoIDs = selectedPhotoIDs.intersection(Set(photos.map(\.id)))
            if selectedPhotoIDs.isEmpty && photos.isEmpty {
                isSelectionMode = false
            }
        } catch {
            self.error = error
            showingError = true
        }
    }

    func deletePhoto(_ photo: PhotoItem) async {
        do {
            try await deleteImageUseCase.execute(photo)
            photos.removeAll { $0.id == photo.id }
        } catch {
            self.error = error
            showingError = true
        }
    }

    func changeSortOption(_ option: SortOption) {
        sortOption = option
        Task {
            await loadPhotos()
        }
    }

    func startSelectionMode() {
        isSelectionMode = true
    }

    func cancelSelection() {
        isSelectionMode = false
        selectedPhotoIDs.removeAll()
        newTagName = ""
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
        do {
            allAlbums = try await albumRepository.fetchAll()
            showingAlbumSelector = true
        } catch {
            self.error = error
            showingError = true
        }
    }

    func deleteSelectedPhotos() async {
        let photosToDelete = photos.filter { selectedPhotoIDs.contains($0.id) }
        guard !photosToDelete.isEmpty else { return }

        isPerformingBatchAction = true
        defer { isPerformingBatchAction = false }

        do {
            for photo in photosToDelete {
                try await deleteImageUseCase.execute(photo)
            }
            cancelSelection()
            await loadPhotos()
        } catch {
            self.error = error
            showingError = true
        }
    }

    func addTagToSelectedPhotos() async {
        let tagName = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tagName.isEmpty, hasSelection else { return }

        isPerformingBatchAction = true
        defer { isPerformingBatchAction = false }

        let tag = Tag(name: tagName)

        do {
            for photoId in selectedPhotoIDs {
                try await tagRepository.addTag(tag, to: photoId)
            }
            newTagName = ""
            showingTagEditor = false
            await loadPhotos()
        } catch {
            self.error = error
            showingError = true
        }
    }

    func addSelectedPhotos(to album: Album) async {
        guard hasSelection else { return }

        isPerformingBatchAction = true
        defer { isPerformingBatchAction = false }

        do {
            for photoId in selectedPhotoIDs {
                try await albumRepository.addImage(photoId, to: album.id)
            }
            showingAlbumSelector = false
            await loadPhotos()
        } catch {
            self.error = error
            showingError = true
        }
    }
}
