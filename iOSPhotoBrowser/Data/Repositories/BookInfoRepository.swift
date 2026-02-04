//
//  BookInfoRepository.swift
//  iOSPhotoBrowser
//

import Foundation
import CoreData

final class BookInfoRepository: BookInfoRepositoryProtocol {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func save(_ bookInfo: BookInfo, for imageId: UUID) async throws {
        try await context.perform {
            // Find the image entity
            let imageRequest = ImageEntity.fetchRequest()
            imageRequest.predicate = NSPredicate(format: "id == %@", imageId as CVarArg)
            imageRequest.fetchLimit = 1

            guard let imageEntity = try self.context.fetch(imageRequest).first else {
                throw RepositoryError.notFound
            }

            // Create new BookInfoEntity
            let entity = BookInfoEntity(context: self.context)
            entity.id = bookInfo.id
            entity.isbn = bookInfo.isbn
            entity.title = bookInfo.title
            entity.author = bookInfo.author
            entity.publisher = bookInfo.publisher
            entity.publishedDate = bookInfo.publishedDate
            entity.coverUrl = bookInfo.coverUrl
            entity.category = bookInfo.category
            entity.readingStatus = bookInfo.readingStatus.rawValue
            entity.ownershipStatus = bookInfo.ownershipStatus.rawValue
            entity.createdAt = bookInfo.createdAt
            entity.updatedAt = bookInfo.updatedAt

            // Set relationship
            entity.image = imageEntity
            imageEntity.bookInfo = entity

            try self.context.save()
        }
    }

    func fetch(for imageId: UUID) async throws -> BookInfo? {
        try await context.perform {
            let imageRequest = ImageEntity.fetchRequest()
            imageRequest.predicate = NSPredicate(format: "id == %@", imageId as CVarArg)
            imageRequest.fetchLimit = 1

            guard let imageEntity = try self.context.fetch(imageRequest).first,
                  let bookInfoEntity = imageEntity.bookInfo else {
                return nil
            }

            return self.toBookInfo(bookInfoEntity)
        }
    }

    func update(_ bookInfo: BookInfo) async throws {
        try await context.perform {
            let request = BookInfoEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", bookInfo.id as CVarArg)
            request.fetchLimit = 1

            guard let entity = try self.context.fetch(request).first else {
                throw RepositoryError.notFound
            }

            entity.title = bookInfo.title
            entity.author = bookInfo.author
            entity.publisher = bookInfo.publisher
            entity.publishedDate = bookInfo.publishedDate
            entity.coverUrl = bookInfo.coverUrl
            entity.category = bookInfo.category
            entity.readingStatus = bookInfo.readingStatus.rawValue
            entity.ownershipStatus = bookInfo.ownershipStatus.rawValue
            entity.updatedAt = Date()

            try self.context.save()
        }
    }

    func delete(for imageId: UUID) async throws {
        try await context.perform {
            let imageRequest = ImageEntity.fetchRequest()
            imageRequest.predicate = NSPredicate(format: "id == %@", imageId as CVarArg)
            imageRequest.fetchLimit = 1

            guard let imageEntity = try self.context.fetch(imageRequest).first,
                  let bookInfoEntity = imageEntity.bookInfo else {
                return
            }

            self.context.delete(bookInfoEntity)
            try self.context.save()
        }
    }

    // MARK: - Private Helpers

    private func toBookInfo(_ entity: BookInfoEntity) -> BookInfo {
        BookInfo(
            id: entity.id ?? UUID(),
            isbn: entity.isbn ?? "",
            title: entity.title,
            author: entity.author,
            publisher: entity.publisher,
            publishedDate: entity.publishedDate,
            coverUrl: entity.coverUrl,
            category: entity.category,
            readingStatus: ReadingStatus(rawValue: entity.readingStatus) ?? .unread,
            ownershipStatus: OwnershipStatus(rawValue: entity.ownershipStatus) ?? .notOwned,
            createdAt: entity.createdAt ?? Date(),
            updatedAt: entity.updatedAt ?? Date()
        )
    }
}
