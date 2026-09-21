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

// MARK: - App Shortcuts Provider (Automatic Siri integration)
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
  }
}
