//
//  PhotoItem.swift
//  iOSPhotoBrowser
//

import Foundation

struct PhotoItem: Identifiable, Hashable {
    let id: UUID
    let fileName: String
    let filePath: String
    let thumbnailPath: String?
    let width: Int
    let height: Int
    let orientation: Int
    let capturedAt: Date?
    let importedAt: Date
    let latitude: Double?
    let longitude: Double?
    let cameraMake: String?
    let cameraModel: String?
    let fileSize: Int64
    var isFavorite: Bool
    var tags: [Tag]
    var albums: [Album]
    var extractedText: String?
    var ocrProcessedAt: Date?
    var bookInfo: BookInfo?

    init(
        id: UUID = UUID(),
        fileName: String,
        filePath: String,
        thumbnailPath: String? = nil,
        width: Int = 0,
        height: Int = 0,
        orientation: Int = 1,
        capturedAt: Date? = nil,
        importedAt: Date = Date(),
        latitude: Double? = nil,
        longitude: Double? = nil,
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        fileSize: Int64 = 0,
        isFavorite: Bool = false,
        tags: [Tag] = [],
        albums: [Album] = [],
        extractedText: String? = nil,
        ocrProcessedAt: Date? = nil,
        bookInfo: BookInfo? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.filePath = filePath
        self.thumbnailPath = thumbnailPath
        self.width = width
        self.height = height
        self.orientation = orientation
        self.capturedAt = capturedAt
        self.importedAt = importedAt
        self.latitude = latitude
        self.longitude = longitude
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.fileSize = fileSize
        self.isFavorite = isFavorite
        self.tags = tags
        self.albums = albums
        self.extractedText = extractedText
        self.ocrProcessedAt = ocrProcessedAt
        self.bookInfo = bookInfo
    }
}

extension PhotoItem {
    var isGIF: Bool {
        URL(fileURLWithPath: fileName).pathExtension.lowercased() == "gif"
    }

    var displayDate: Date {
        capturedAt ?? importedAt
    }

    var sizeDescription: String {
        "\(width) × \(height)"
    }

    var fileSizeDescription: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var hasLocation: Bool {
        latitude != nil && longitude != nil
    }

    var hasOCRProcessed: Bool {
        ocrProcessedAt != nil
    }

    var hasBookInfo: Bool {
        bookInfo != nil
    }
}
