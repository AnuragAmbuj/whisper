//
//  BookEntity.swift
//  Whisper
//
//  Created by Anurag Ambuj on 22/09/26.
//

import AppIntents
import Foundation

struct BookEntity: AppEntity, Identifiable {
  static var defaultQuery = BookEntityQuery()
  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Book"

  var id: UUID
  var title: String
  var author: String
  var format: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "\(title)",
      subtitle: "\(author) • \(format)"
    )
  }
}

struct BookEntityQuery: EntityQuery {
  @MainActor
  func entities(for identifiers: [UUID]) async throws -> [BookEntity] {
    let all = BookService.shared.fetchAllBooks()
    return all.filter { identifiers.contains($0.id) }.map { $0.toEntity() }
  }

  @MainActor
  func suggestedEntities() async throws -> [BookEntity] {
    return BookService.shared.fetchAllBooks().map { $0.toEntity() }
  }

  @MainActor
  func entities(matching string: String) async throws -> [BookEntity] {
    let all = BookService.shared.fetchAllBooks()
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return all.map { $0.toEntity() } }
    return all.filter {
      $0.title.localizedCaseInsensitiveContains(trimmed) ||
      $0.author.localizedCaseInsensitiveContains(trimmed)
    }.map { $0.toEntity() }
  }
}

extension Book {
  func toEntity() -> BookEntity {
    BookEntity(
      id: self.id,
      title: self.title,
      author: self.author,
      format: self.format?.displayName ?? "Book"
    )
  }
}
