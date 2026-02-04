//
//  BookInfo.swift
//  iOSPhotoBrowser
//

import Foundation

// MARK: - Reading Status

enum ReadingStatus: Int16, CaseIterable, Hashable {
    case unread = 0      // 未読
    case reading = 1     // 読書中
    case finished = 2    // 読了

    var displayName: String {
        switch self {
        case .unread: return "未読"
        case .reading: return "読書中"
        case .finished: return "読了"
        }
    }

    var iconName: String {
        switch self {
        case .unread: return "book.closed"
        case .reading: return "book"
        case .finished: return "checkmark.circle"
        }
    }
}

// MARK: - Ownership Status

enum OwnershipStatus: Int16, CaseIterable, Hashable {
    case notOwned = 0    // 持っていない
    case owned = 1       // 持っている

    var displayName: String {
        switch self {
        case .notOwned: return "持っていない"
        case .owned: return "持っている"
        }
    }

    var iconName: String {
        switch self {
        case .notOwned: return "xmark.circle"
        case .owned: return "checkmark.circle.fill"
        }
    }
}

// MARK: - BookInfo

struct BookInfo: Identifiable, Hashable {
    let id: UUID
    let isbn: String
    var title: String?
    var author: String?
    var publisher: String?
    var publishedDate: String?
    var coverUrl: String?
    var category: String?
    var readingStatus: ReadingStatus
    var ownershipStatus: OwnershipStatus
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        isbn: String,
        title: String? = nil,
        author: String? = nil,
        publisher: String? = nil,
        publishedDate: String? = nil,
        coverUrl: String? = nil,
        category: String? = nil,
        readingStatus: ReadingStatus = .unread,
        ownershipStatus: OwnershipStatus = .notOwned,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.isbn = isbn
        self.title = title
        self.author = author
        self.publisher = publisher
        self.publishedDate = publishedDate
        self.coverUrl = coverUrl
        self.category = category
        self.readingStatus = readingStatus
        self.ownershipStatus = ownershipStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
