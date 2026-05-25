//
//  ImportViewModel.swift
//  iOSPhotoBrowser
//

import Foundation
import Combine
import Photos
import PhotosUI
import SwiftUI

@MainActor
final class ImportViewModel: ObservableObject {
    @Published private(set) var isImporting = false
    @Published private(set) var isLoadingPhotoAlbums = false
    @Published private(set) var importProgress: Double = 0
    @Published private(set) var importedCount = 0
    @Published private(set) var failedCount = 0
    @Published private(set) var shouldDismiss = false
    @Published private(set) var photoAlbums: [PhotoLibraryAlbum] = []
    @Published var showingPhotoPicker = false
    @Published var showingFilePicker = false
    @Published var showingDirectoryPicker = false
    @Published var showingCamera = false
    @Published var showingPhotoAlbumImporter = false
    @Published var error: Error?
    @Published var showingError = false

    private let importImageUseCase: ImportImageUseCase
    private let permissionService = PermissionService.shared
    private let photoLibraryService = PhotoLibraryService.shared
    private let fileImportService = FileImportService.shared

    var permissionStatus: PHAuthorizationStatus {
        permissionService.photoLibraryStatus
    }

    init(importImageUseCase: ImportImageUseCase) {
        self.importImageUseCase = importImageUseCase
    }

    func requestPhotoAccess() async {
        _ = await permissionService.requestPhotoLibraryAccess()
    }

    func openPhotoAlbumImporter() async {
        error = nil
        showingError = false

        let status = permissionService.isPhotoLibraryAuthorized
            ? permissionService.photoLibraryStatus
            : await permissionService.requestPhotoLibraryAccess()

        guard status == .authorized || status == .limited else {
            error = ImportError.photoAlbumAccessRequired
            showingError = true
            return
        }

        isLoadingPhotoAlbums = true
        defer { isLoadingPhotoAlbums = false }

        photoAlbums = photoLibraryService.fetchAlbums()
        showingPhotoAlbumImporter = true
    }

    func importFromPhotoAlbum(_ album: PhotoLibraryAlbum) async {
        let assets = photoLibraryService.fetchAssets(in: album.id)
        guard !assets.isEmpty else {
            error = ImportError.noImportableImagesFound
            showingError = true
            return
        }

        showingPhotoAlbumImporter = false
        await importFromAssets(assets)
    }

    func importFromPhotos(results: [PHPickerResult]) async {
        guard !results.isEmpty else { return }

        isImporting = true
        importProgress = 0
        importedCount = 0
        failedCount = 0

        let total = results.count

        for (index, result) in results.enumerated() {
            do {
                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    let image = try await loadImage(from: result.itemProvider)
                    guard let data = image.jpegData(compressionQuality: 0.9) else {
                        failedCount += 1
                        continue
                    }

                    let fileName = result.itemProvider.suggestedName ?? "image_\(UUID().uuidString).jpg"
                    _ = try await importImageUseCase.execute(imageData: data, originalFileName: fileName)
                    importedCount += 1
                }
            } catch {
                failedCount += 1
                print("Import error: \(error)")
            }

            importProgress = Double(index + 1) / Double(total)
        }

        isImporting = false

        // Auto-dismiss after short delay if import succeeded
        if importedCount > 0 {
            try? await Task.sleep(for: .milliseconds(800))
            shouldDismiss = true
        }
    }

    func importFromFiles(urls: [URL]) async {
        guard !urls.isEmpty else { return }

        isImporting = true
        importProgress = 0
        importedCount = 0
        failedCount = 0

        let total = urls.count

        for (index, url) in urls.enumerated() {
            do {
                _ = try await importImageUseCase.execute(from: url)
                importedCount += 1
            } catch {
                failedCount += 1
                print("Import error: \(error)")
            }

            importProgress = Double(index + 1) / Double(total)
        }

        isImporting = false

        // Auto-dismiss after short delay if import succeeded
        if importedCount > 0 {
            try? await Task.sleep(for: .milliseconds(800))
            shouldDismiss = true
        }
    }

    func importFromDirectory(url: URL) async {
        do {
            let imageURLs = try fileImportService.findImportableImageURLs(in: url)
            guard !imageURLs.isEmpty else {
                error = ImportError.noImportableImagesFound
                showingError = true
                return
            }

            await importFromFiles(urls: imageURLs)
        } catch {
            self.error = error
            showingError = true
        }
    }

    func importFromPhotosPickerItems(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        isImporting = true
        importProgress = 0
        importedCount = 0
        failedCount = 0

        let total = items.count

        for (index, item) in items.enumerated() {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    let fileExtension = item.supportedContentTypes
                        .compactMap(\.preferredFilenameExtension)
                        .first ?? "jpg"
                    let fileName = "image_\(UUID().uuidString).\(fileExtension)"
                    _ = try await importImageUseCase.execute(
                        imageData: data,
                        originalFileName: fileName
                    )
                    importedCount += 1
                } else {
                    failedCount += 1
                }
            } catch {
                failedCount += 1
                print("Import error: \(error)")
            }

            importProgress = Double(index + 1) / Double(total)
        }

        isImporting = false

        // Auto-dismiss after short delay if import succeeded
        if importedCount > 0 {
            try? await Task.sleep(for: .milliseconds(800))
            shouldDismiss = true
        }
    }

    private func importFromAssets(_ assets: [PHAsset]) async {
        guard !assets.isEmpty else { return }

        isImporting = true
        importProgress = 0
        importedCount = 0
        failedCount = 0

        let total = assets.count

        for (index, asset) in assets.enumerated() {
            do {
                _ = try await importImageUseCase.execute(from: asset)
                importedCount += 1
            } catch {
                failedCount += 1
                print("Import error: \(error)")
            }

            importProgress = Double(index + 1) / Double(total)
        }

        isImporting = false

        if importedCount > 0 {
            try? await Task.sleep(for: .milliseconds(800))
            shouldDismiss = true
        }
    }

    func importFromCamera(_ image: UIImage) async {
        isImporting = true
        importProgress = 0
        importedCount = 0
        failedCount = 0

        do {
            guard let data = image.jpegData(compressionQuality: 0.9) else {
                failedCount = 1
                isImporting = false
                return
            }

            let fileName = "camera_\(UUID().uuidString).jpg"
            _ = try await importImageUseCase.execute(
                imageData: data,
                originalFileName: fileName
            )
            importedCount = 1
            importProgress = 1.0
        } catch {
            failedCount = 1
            print("Import error: \(error)")
        }

        isImporting = false

        // Auto-dismiss after short delay if import succeeded
        if importedCount > 0 {
            try? await Task.sleep(for: .milliseconds(800))
            shouldDismiss = true
        }
    }

    private func loadImage(from provider: NSItemProvider) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let image = object as? UIImage else {
                    continuation.resume(throwing: ImportError.invalidImage)
                    return
                }

                continuation.resume(returning: image)
            }
        }
    }
}

enum ImportError: Error {
    case invalidImage
    case accessDenied
    case noImportableImagesFound
    case photoAlbumAccessRequired
}

extension ImportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "画像の読み込みに失敗しました"
        case .accessDenied:
            return "アクセス権限がありません"
        case .noImportableImagesFound:
            return "取り込める画像が見つかりませんでした"
        case .photoAlbumAccessRequired:
            return "この機能は写真ライブラリへのアクセス許可が必要です。通常の「写真から選択」とは別に、アプリへの写真アクセスを許可してください"
        }
    }
}
