//
//  DetailViewModel.swift
//  iOSPhotoBrowser
//

import Foundation
import Combine
import UIKit

@MainActor
final class DetailViewModel: ObservableObject {
    @Published private(set) var photo: PhotoItem?
    @Published private(set) var allAlbums: [Album] = []
    @Published private(set) var isLoading = false
    @Published var newTagName = ""
    @Published var showingTagEditor = false
    @Published var showingAlbumSelector = false
    @Published var showingDeleteConfirmation = false
    @Published var error: Error?
    @Published var showingError = false

    // OCR関連
    @Published private(set) var isProcessingOCR = false
    @Published private(set) var ocrMessage: String?
    @Published var showingBookInfoEditor = false
    @Published var editingBookInfo: BookInfo?

    // タイトル検索関連
    @Published var showingTitleSearchSheet = false
    @Published var showingSearchResults = false
    @Published var searchKeyword = ""
    @Published private(set) var searchResults: [BookInfo] = []
    @Published private(set) var isSearching = false

    let photoId: UUID
    private let imageRepository: ImageRepositoryProtocol
    private let tagRepository: TagRepositoryProtocol
    private let albumRepository: AlbumRepositoryProtocol
    private let bookInfoRepository: BookInfoRepositoryProtocol
    private let deleteImageUseCase: DeleteImageUseCase
    private let ocrService: OCRService
    private let bookInfoService: BookInfoService

    init(
        photoId: UUID,
        imageRepository: ImageRepositoryProtocol,
        tagRepository: TagRepositoryProtocol,
        albumRepository: AlbumRepositoryProtocol,
        bookInfoRepository: BookInfoRepositoryProtocol,
        deleteImageUseCase: DeleteImageUseCase,
        ocrService: OCRService,
        bookInfoService: BookInfoService
    ) {
        self.photoId = photoId
        self.imageRepository = imageRepository
        self.tagRepository = tagRepository
        self.albumRepository = albumRepository
        self.bookInfoRepository = bookInfoRepository
        self.deleteImageUseCase = deleteImageUseCase
        self.ocrService = ocrService
        self.bookInfoService = bookInfoService
    }

    func loadPhoto() async {
        isLoading = true
        defer { isLoading = false }

        do {
            photo = try await imageRepository.fetch(byId: photoId)
        } catch {
            self.error = error
            showingError = true
        }
    }

    func addTag() async {
        guard !newTagName.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let tagName = newTagName.trimmingCharacters(in: .whitespaces)
        let tag = Tag(name: tagName)

        do {
            try await tagRepository.addTag(tag, to: photoId)
            await loadPhoto()
            newTagName = ""
        } catch {
            self.error = error
            showingError = true
        }
    }

    func removeTag(_ tag: Tag) async {
        do {
            try await tagRepository.removeTag(tag, from: photoId)
            await loadPhoto()
        } catch {
            self.error = error
            showingError = true
        }
    }

    func deletePhoto() async -> Bool {
        guard let photo = photo else { return false }

        do {
            try await deleteImageUseCase.execute(photo)
            return true
        } catch {
            self.error = error
            showingError = true
            return false
        }
    }

    func loadImage() -> UIImage? {
        guard let photo = photo else { return nil }
        return FileStorageManager.shared.loadImage(fileName: photo.filePath)
    }

    func loadAlbums() async {
        do {
            allAlbums = try await albumRepository.fetchAll()
        } catch {
            self.error = error
            showingError = true
        }
    }

    func addToAlbum(_ album: Album) async {
        do {
            try await albumRepository.addImage(photoId, to: album.id)
            await loadPhoto()
        } catch {
            self.error = error
            showingError = true
        }
    }

    func removeFromAlbum(_ album: Album) async {
        do {
            try await albumRepository.removeImage(photoId, from: album.id)
            await loadPhoto()
        } catch {
            self.error = error
            showingError = true
        }
    }

    func isInAlbum(_ album: Album) -> Bool {
        photo?.albums.contains { $0.id == album.id } ?? false
    }

    // MARK: - OCR & Book Info

    func performOCRAndFetchBookInfo() async {
        guard let image = loadImage() else {
            ocrMessage = "画像の読み込みに失敗しました"
            return
        }

        isProcessingOCR = true
        ocrMessage = nil
        defer { isProcessingOCR = false }

        do {
            // Step 1: OCR（Apple Intelligence補正が利用可能なら自動適用）
            let extractedText = try await ocrService.recognizeTextWithCorrection(from: image)

            // Save extracted text
            try await imageRepository.updateExtractedText(
                imageId: photoId,
                text: extractedText,
                processedAt: Date()
            )

            await loadPhoto()

            // Step 2: Extract ISBN
            if let isbn = await ocrService.extractISBN(from: extractedText) {
                // ISBN found - try openBD API
                if let bookInfo = try await bookInfoService.fetchBookInfo(isbn: isbn) {
                    // Save book info
                    try await bookInfoRepository.save(bookInfo, for: photoId)
                    ocrMessage = nil
                    await loadPhoto()
                    return
                } else {
                    ocrMessage = "書誌情報が見つかりませんでした（ISBN: \(isbn)）"
                }
            }

            // ISBN not found or book info not found - show title search sheet
            ocrMessage = "ISBNが検出できませんでした。タイトルで検索してください。"
            showingTitleSearchSheet = true

        } catch {
            self.error = error
            showingError = true
        }
    }

    func startEditingBookInfo() {
        guard let bookInfo = photo?.bookInfo else { return }
        editingBookInfo = bookInfo
        showingBookInfoEditor = true
    }

    func updateBookInfo() async {
        guard let bookInfo = editingBookInfo else { return }

        do {
            try await bookInfoRepository.update(bookInfo)
            showingBookInfoEditor = false
            editingBookInfo = nil
            await loadPhoto()
        } catch {
            self.error = error
            showingError = true
        }
    }

    func deleteBookInfo() async {
        do {
            try await bookInfoRepository.delete(for: photoId)
            await loadPhoto()
        } catch {
            self.error = error
            showingError = true
        }
    }

    // MARK: - Title Search

    func startTitleSearch() {
        searchKeyword = ""
        searchResults = []
        showingTitleSearchSheet = true
    }

    func searchByTitle() async {
        let keyword = searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }

        isSearching = true
        defer { isSearching = false }

        do {
            searchResults = try await bookInfoService.searchByTitle(keyword: keyword)
            if searchResults.isEmpty {
                ocrMessage = "「\(keyword)」に一致する書籍が見つかりませんでした"
            } else {
                showingTitleSearchSheet = false
                showingSearchResults = true
            }
        } catch {
            self.error = error
            showingError = true
        }
    }

    func selectBookInfo(_ bookInfo: BookInfo) async {
        do {
            try await bookInfoRepository.save(bookInfo, for: photoId)
            showingSearchResults = false
            searchResults = []
            searchKeyword = ""
            ocrMessage = nil
            await loadPhoto()
        } catch {
            self.error = error
            showingError = true
        }
    }

    func cancelTitleSearch() {
        showingTitleSearchSheet = false
        showingSearchResults = false
        searchResults = []
        searchKeyword = ""
    }
}
