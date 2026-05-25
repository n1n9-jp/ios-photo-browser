//
//  FileStorageManager.swift
//  iOSPhotoBrowser
//

import Foundation
import UIKit

final class FileStorageManager {
    static let shared = FileStorageManager()

    private let fileManager = FileManager.default

    private var imagesDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let imagesPath = documentsPath.appendingPathComponent("images", isDirectory: true)

        if !fileManager.fileExists(atPath: imagesPath.path) {
            try? fileManager.createDirectory(at: imagesPath, withIntermediateDirectories: true)
        }

        return imagesPath
    }

    private var thumbnailsDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let thumbnailsPath = documentsPath.appendingPathComponent("thumbnails", isDirectory: true)

        if !fileManager.fileExists(atPath: thumbnailsPath.path) {
            try? fileManager.createDirectory(at: thumbnailsPath, withIntermediateDirectories: true)
        }

        BackupExclusionManager.excludeFromBackup(itemAt: thumbnailsPath)

        return thumbnailsPath
    }

    private init() {
        BackupExclusionManager.excludeDirectoryContentsFromBackup(at: thumbnailsDirectory)
    }

    // MARK: - Image Storage

    func saveImage(data: Data, id: UUID) throws -> String {
        let fileName = "\(id.uuidString).jpg"
        let filePath = imagesDirectory.appendingPathComponent(fileName)

        try data.write(to: filePath)
        return fileName
    }

    func saveImage(_ image: UIImage, id: UUID, compressionQuality: CGFloat = 0.9) throws -> String {
        guard let data = image.jpegData(compressionQuality: compressionQuality) else {
            throw StorageError.imageConversionFailed
        }
        return try saveImage(data: data, id: id)
    }

    func loadImage(fileName: String) -> UIImage? {
        let filePath = imagesDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: filePath) else {
            return nil
        }
        return UIImage(data: data)
    }

    func loadImageData(fileName: String) -> Data? {
        let filePath = imagesDirectory.appendingPathComponent(fileName)
        return try? Data(contentsOf: filePath)
    }

    func imageURL(for fileName: String) -> URL {
        imagesDirectory.appendingPathComponent(fileName)
    }

    func deleteImage(fileName: String) throws {
        let filePath = imagesDirectory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: filePath.path) {
            try fileManager.removeItem(at: filePath)
        }
    }

    // MARK: - Thumbnail Storage

    func saveThumbnail(_ image: UIImage, id: UUID) throws -> String {
        let fileName = "\(id.uuidString)_thumb.jpg"
        let filePath = thumbnailsDirectory.appendingPathComponent(fileName)

        guard let data = image.jpegData(compressionQuality: 0.7) else {
            throw StorageError.imageConversionFailed
        }

        try data.write(to: filePath)
        BackupExclusionManager.excludeFromBackup(itemAt: filePath)
        return fileName
    }

    func loadThumbnail(fileName: String) -> UIImage? {
        let filePath = thumbnailsDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: filePath) else {
            return nil
        }
        return UIImage(data: data)
    }

    func thumbnailURL(for fileName: String) -> URL {
        thumbnailsDirectory.appendingPathComponent(fileName)
    }

    func deleteThumbnail(fileName: String) throws {
        let filePath = thumbnailsDirectory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: filePath.path) {
            try fileManager.removeItem(at: filePath)
        }
    }

    // MARK: - Utility

    func fileSize(at fileName: String) -> Int64? {
        let filePath = imagesDirectory.appendingPathComponent(fileName)
        guard let attributes = try? fileManager.attributesOfItem(atPath: filePath.path) else {
            return nil
        }
        return attributes[.size] as? Int64
    }
}

enum StorageError: Error {
    case imageConversionFailed
    case saveFailed
    case deleteFailed
}

enum BackupExclusionManager {
    static func reconcileManagedDirectories() {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let managedDirectoryNames = ["thumbnails", "Models", "VLMModels"]
        for directoryName in managedDirectoryNames {
            let directoryURL = documentsDirectory.appendingPathComponent(directoryName, isDirectory: true)
            guard FileManager.default.fileExists(atPath: directoryURL.path) else {
                continue
            }
            excludeDirectoryContentsFromBackup(at: directoryURL)
        }
    }

    static func excludeFromBackup(itemAt url: URL) {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true

        var mutableURL = url
        try? mutableURL.setResourceValues(resourceValues)
    }

    static func excludeDirectoryContentsFromBackup(at directoryURL: URL) {
        excludeRecursivelyFromBackup(itemAt: directoryURL)
    }

    private static func excludeRecursivelyFromBackup(itemAt url: URL) {
        excludeFromBackup(itemAt: url)

        guard let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]),
              resourceValues.isDirectory == true,
              let children = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else {
            return
        }

        for childURL in children {
            excludeRecursivelyFromBackup(itemAt: childURL)
        }
    }
}
