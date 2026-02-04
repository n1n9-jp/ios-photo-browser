//
//  ExtractedTextsViewModel.swift
//  iOSPhotoBrowser
//

import Foundation
import Combine

// MARK: - Filter Options

enum ReadingStatusFilter: CaseIterable {
    case all
    case unread
    case reading
    case finished

    var displayName: String {
        switch self {
        case .all: return "すべて"
        case .unread: return "未読"
        case .reading: return "読書中"
        case .finished: return "読了"
        }
    }

    func matches(_ status: ReadingStatus) -> Bool {
        switch self {
        case .all: return true
        case .unread: return status == .unread
        case .reading: return status == .reading
        case .finished: return status == .finished
        }
    }
}

enum OwnershipStatusFilter: CaseIterable {
    case all
    case owned
    case notOwned

    var displayName: String {
        switch self {
        case .all: return "すべて"
        case .owned: return "持っている"
        case .notOwned: return "持っていない"
        }
    }

    func matches(_ status: OwnershipStatus) -> Bool {
        switch self {
        case .all: return true
        case .owned: return status == .owned
        case .notOwned: return status == .notOwned
        }
    }
}

// MARK: - ViewModel

@MainActor
final class ExtractedTextsViewModel: ObservableObject {
    @Published private(set) var items: [ExtractedTextItem] = []
    @Published private(set) var groupedItems: [CategoryGroup] = []
    @Published private(set) var isLoading = false
    @Published var error: Error?
    @Published var showingError = false

    // Filter states
    @Published var readingStatusFilter: ReadingStatusFilter = .all {
        didSet { applyFilters() }
    }
    @Published var ownershipStatusFilter: OwnershipStatusFilter = .all {
        didSet { applyFilters() }
    }

    private var allItems: [ExtractedTextItem] = []
    private let imageRepository: ImageRepositoryProtocol
    private let bookInfoRepository: BookInfoRepositoryProtocol

    init(imageRepository: ImageRepositoryProtocol, bookInfoRepository: BookInfoRepositoryProtocol) {
        self.imageRepository = imageRepository
        self.bookInfoRepository = bookInfoRepository
    }

    var hasActiveFilters: Bool {
        readingStatusFilter != .all || ownershipStatusFilter != .all
    }

    func clearFilters() {
        readingStatusFilter = .all
        ownershipStatusFilter = .all
    }

    func loadItems() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let photos = try await imageRepository.fetchAll(sortedBy: .importedAtDescending)
            // Filter photos that have extracted text or book info
            allItems = photos.compactMap { photo -> ExtractedTextItem? in
                let hasContent = (photo.extractedText != nil && !photo.extractedText!.isEmpty) || photo.hasBookInfo
                guard hasContent else { return nil }

                return ExtractedTextItem(
                    id: photo.id,
                    thumbnailPath: photo.thumbnailPath,
                    extractedText: photo.extractedText,
                    bookTitle: photo.bookInfo?.title,
                    bookAuthor: photo.bookInfo?.author,
                    bookPublisher: photo.bookInfo?.publisher,
                    bookISBN: photo.bookInfo?.isbn,
                    bookCategory: photo.bookInfo?.category,
                    readingStatus: photo.bookInfo?.readingStatus ?? .unread,
                    ownershipStatus: photo.bookInfo?.ownershipStatus ?? .notOwned,
                    ocrProcessedAt: photo.ocrProcessedAt
                )
            }

            applyFilters()
        } catch {
            self.error = error
            showingError = true
        }
    }

    private func applyFilters() {
        let filtered = allItems.filter { item in
            readingStatusFilter.matches(item.readingStatus) &&
            ownershipStatusFilter.matches(item.ownershipStatus)
        }
        items = filtered
        groupedItems = groupByCategory(filtered)
    }

    private func groupByCategory(_ items: [ExtractedTextItem]) -> [CategoryGroup] {
        var grouped: [String: [ExtractedTextItem]] = [:]
        let uncategorizedKey = "未分類"

        for item in items {
            let category = item.bookCategory ?? uncategorizedKey
            grouped[category, default: []].append(item)
        }

        // Sort categories: defined categories first (alphabetically), then uncategorized at the end
        let sortedKeys = grouped.keys.sorted { key1, key2 in
            if key1 == uncategorizedKey { return false }
            if key2 == uncategorizedKey { return true }
            return key1 < key2
        }

        return sortedKeys.map { CategoryGroup(category: $0, items: grouped[$0]!) }
    }

    // MARK: - Status Update

    func updateStatus(
        for itemId: UUID,
        readingStatus: ReadingStatus,
        ownershipStatus: OwnershipStatus
    ) async {
        do {
            // Fetch current book info
            guard var bookInfo = try await bookInfoRepository.fetch(for: itemId) else {
                return
            }

            // Update status
            bookInfo.readingStatus = readingStatus
            bookInfo.ownershipStatus = ownershipStatus

            // Save to repository
            try await bookInfoRepository.update(bookInfo)

            // Update local items
            if let index = allItems.firstIndex(where: { $0.id == itemId }) {
                let oldItem = allItems[index]
                allItems[index] = ExtractedTextItem(
                    id: oldItem.id,
                    thumbnailPath: oldItem.thumbnailPath,
                    extractedText: oldItem.extractedText,
                    bookTitle: oldItem.bookTitle,
                    bookAuthor: oldItem.bookAuthor,
                    bookPublisher: oldItem.bookPublisher,
                    bookISBN: oldItem.bookISBN,
                    bookCategory: oldItem.bookCategory,
                    readingStatus: readingStatus,
                    ownershipStatus: ownershipStatus,
                    ocrProcessedAt: oldItem.ocrProcessedAt
                )
                applyFilters()
            }
        } catch {
            self.error = error
            showingError = true
        }
    }
}

struct CategoryGroup: Identifiable {
    let id = UUID()
    let category: String
    let items: [ExtractedTextItem]
}

struct ExtractedTextItem: Identifiable {
    let id: UUID
    let thumbnailPath: String?
    let extractedText: String?
    let bookTitle: String?
    let bookAuthor: String?
    let bookPublisher: String?
    let bookISBN: String?
    let bookCategory: String?
    let readingStatus: ReadingStatus
    let ownershipStatus: OwnershipStatus
    let ocrProcessedAt: Date?

    var hasBookInfo: Bool {
        bookTitle != nil || bookAuthor != nil || bookPublisher != nil
    }

    var displayTitle: String {
        if let title = bookTitle {
            return title
        } else if let text = extractedText {
            // Return first line or first 50 characters
            let firstLine = text.components(separatedBy: .newlines).first ?? text
            if firstLine.count > 50 {
                return String(firstLine.prefix(50)) + "..."
            }
            return firstLine
        }
        return "（テキストなし）"
    }
}
