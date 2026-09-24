//
//  WhisperIntents.swift
//  Whisper
//
//  Created by Anurag Ambuj on 22/09/26.
//

import AppIntents
import Foundation
import SwiftUI

// MARK: - Open Book Intent (Siri & Shortcuts)
struct OpenBookIntent: AppIntent {
  static var title: LocalizedStringResource = "Open Book in Whisper"
  static var description = IntentDescription("Opens a specific book or comic in Whisper.")
  static var openAppWhenRun: Bool = true

  @Parameter(title: "Book")
  var book: BookEntity

  @MainActor
  func perform() async throws -> some IntentResult {
    NotificationCenter.default.post(
      name: .whisperOpenBookById,
      object: book.id
    )
    return .result()
  }
}

// MARK: - Resume Reading Intent (Siri & Shortcuts)
struct ResumeReadingIntent: AppIntent {
  static var title: LocalizedStringResource = "Resume Reading"
  static var description = IntentDescription("Resumes reading the most recent book in Whisper.")
  static var openAppWhenRun: Bool = true

  @MainActor
  func perform() async throws -> some IntentResult {
    NotificationCenter.default.post(
      name: .whisperResumeReading,
      object: nil
    )
    return .result()
  }
}

// MARK: - Bookmark Current Page Intent
struct BookmarkCurrentPageIntent: AppIntent {
  static var title: LocalizedStringResource = "Bookmark Current Page"
  static var description = IntentDescription("Toggles a bookmark on the currently opened book.")
  static var openAppWhenRun: Bool = false

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    guard let book = BookService.shared.fetchLatestBook() else {
      return .result(value: "No book currently open.")
    }
    NotificationCenter.default.post(
      name: .whisperToggleBookmark,
      object: nil
    )
    return .result(value: "Bookmarked \(book.title)")
  }
}

// MARK: - What Book Am I Reading Intent
struct GetCurrentReadingBookIntent: AppIntent {
  static var title: LocalizedStringResource = "What Am I Reading?"
  static var description = IntentDescription("Checks the current reading book and progress in Whisper.")

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard let book = BookService.shared.fetchLatestBook() else {
      return .result(dialog: "You have not started any books in Whisper yet.")
    }
    
    let percent = Int(book.progress * 100)
    let authorText = book.author.isEmpty ? "" : " by \(book.author)"
    let message = "You are currently reading \"\(book.title)\"\(authorText) at \(percent)% complete."
    return .result(dialog: IntentDialog(stringLiteral: message))
  }
}

// MARK: - Summarize Current Chapter Intent (Apple Intelligence)
struct SummarizeCurrentChapterIntent: AppIntent {
  static var title: LocalizedStringResource = "Summarize Current Book"
  static var description = IntentDescription("Uses on-device Apple Intelligence to summarize the current book in Whisper.")

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard let book = BookService.shared.fetchLatestBook() else {
      return .result(dialog: "No active book found in Whisper to summarize.")
    }
    
    let content = book.content.isEmpty ? book.resolveSearchableContent() : book.content
    let insights = await AISummarizerService.shared.generateInsights(for: content, bookTitle: book.title)
    
    let summaryText = insights.executiveSummary.isEmpty ? "No text available to summarize." : insights.executiveSummary
    let dialogText = "Here is the AI synopsis for \(book.title): \(summaryText)"
    return .result(dialog: IntentDialog(stringLiteral: dialogText))
  }
}

// MARK: - App Shortcuts Provider (Automatic Siri Integration)
struct WhisperShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: ResumeReadingIntent(),
      phrases: [
        "Continue reading in \(.applicationName)",
        "Resume reading in \(.applicationName)",
        "Read next in \(.applicationName)"
      ],
      shortTitle: "Resume Reading",
      systemImageName: "book.fill"
    )
    AppShortcut(
      intent: OpenBookIntent(),
      phrases: [
        "Read \(\.$book) in \(.applicationName)",
        "Open \(\.$book) in \(.applicationName)"
      ],
      shortTitle: "Open Book",
      systemImageName: "book"
    )
    AppShortcut(
      intent: GetCurrentReadingBookIntent(),
      phrases: [
        "What am I reading in \(.applicationName)",
        "Current book in \(.applicationName)"
      ],
      shortTitle: "Current Book",
      systemImageName: "eyeglasses"
    )
    AppShortcut(
      intent: BookmarkCurrentPageIntent(),
      phrases: [
        "Bookmark this page in \(.applicationName)",
        "Add bookmark in \(.applicationName)"
      ],
      shortTitle: "Add Bookmark",
      systemImageName: "bookmark.fill"
    )
    AppShortcut(
      intent: SummarizeCurrentChapterIntent(),
      phrases: [
        "Summarize book in \(.applicationName)",
        "Give me AI summary in \(.applicationName)"
      ],
      shortTitle: "AI Summary",
      systemImageName: "sparkles"
    )
  }
}
