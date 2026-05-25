//
//  PhotoLibraryService.swift
//  iOSPhotoBrowser
//

import Foundation
import Photos
import UIKit

struct PhotoLibraryAlbum: Identifiable, Hashable {
    let id: String
    let title: String
    let assetCount: Int
}

final class PhotoLibraryService {
    static let shared = PhotoLibraryService()

    private init() {}

    func fetchImageData(from asset: PHAsset) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data = data else {
                    continuation.resume(throwing: PhotoLibraryError.dataNotAvailable)
                    return
                }

                continuation.resume(returning: data)
            }
        }
    }

    func fetchImage(from asset: PHAsset, targetSize: CGSize = PHImageManagerMaximumSize) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options) { image, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let image = image else {
                    continuation.resume(throwing: PhotoLibraryError.imageNotAvailable)
                    return
                }

                continuation.resume(returning: image)
            }
        }
    }

    func getOriginalFileName(from asset: PHAsset) -> String? {
        let resources = PHAssetResource.assetResources(for: asset)
        return resources.first?.originalFilename
    }

    func fetchAlbums() -> [PhotoLibraryAlbum] {
        var albums: [PhotoLibraryAlbum] = []
        var seenIdentifiers = Set<String>()

        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        func appendAlbum(_ collection: PHAssetCollection) {
            let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
            guard assets.count > 0 else { return }

            let identifier = collection.localIdentifier
            guard seenIdentifiers.insert(identifier).inserted else { return }

            albums.append(
                PhotoLibraryAlbum(
                    id: identifier,
                    title: collection.localizedTitle ?? "名称未設定",
                    assetCount: assets.count
                )
            )
        }

        let userLibrary = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: nil)
        userLibrary.enumerateObjects { collection, _, _ in
            appendAlbum(collection)
        }

        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            appendAlbum(collection)
        }

        return albums.sorted { lhs, rhs in
            lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    func fetchAssets(in albumId: String) -> [PHAsset] {
        let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumId], options: nil)
        guard let collection = collections.firstObject else {
            return []
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
        var results: [PHAsset] = []
        results.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            results.append(asset)
        }
        return results
    }
}

enum PhotoLibraryError: Error {
    case dataNotAvailable
    case imageNotAvailable
    case accessDenied
}
