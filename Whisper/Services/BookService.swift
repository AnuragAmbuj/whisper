//
//  BookService.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import Foundation
import SwiftData

class BookService {
  static let shared = BookService()

  private init() {}

  func generateMockBooks() -> [Book] {
    return [
      Book(
        title: "Pride and Prejudice",
        author: "Jane Austen",
        coverImageName: "pride_cover",
        content:
          "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.",
        progress: 0.0
      ),
      Book(
        title: "The Hobbit",
        author: "J.R.R. Tolkien",
        coverImageName: "hobbit_cover",
        content: "In a hole in the ground there lived a hobbit.",
        progress: 0.8
      ),
      Book(
        title: "Amazing Adventures",
        author: "Stan Lee",
        coverImageName: "coverComic",
        content: "A mock comic book.",
        progress: 0.0,
        format: .comic,
        sampleImages: ["cover1", "cover2", "cover1", "cover2"]  // Assuming these assets exist or placeholders
      ),
      Book(
        title: "User Manual",
        author: "System",
        coverImageName: "coverPDF",
        content: "A PDF manual.",
        progress: 0.0,
        format: .pdf,
        url: URL(string: "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf")
      ),
    ]
  }
  func checkForSeeding(context: ModelContext) {
    // Check if we already have books
    let descriptor = FetchDescriptor<Book>()
    do {
      let count = try context.fetchCount(descriptor)
      if count == 0 {
        // Seed
        let mocks = generateMockBooks()
        for book in mocks {
          context.insert(book)
        }
        try? context.save()
      }
    } catch {
      print("Error checking for existing books: \(error)")
    }
  }
}
