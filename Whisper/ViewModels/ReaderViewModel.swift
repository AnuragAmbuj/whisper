//
//  ReaderViewModel.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import Foundation
import SwiftUI
import SwiftData

@Observable
class ReaderViewModel {
    var book: Book
    var theme: AppTheme = .default {
        didSet {
            if let encoded = try? JSONEncoder().encode(theme.style) {
                 UserDefaults.standard.set(encoded, forKey: "reader_theme_style")
            }
        }
    }
    var fontSize: Double {
        didSet {
            UserDefaults.standard.set(fontSize, forKey: "reader_fontSize")
        }
    }
    var isBookmarked: Bool = false
    
    // Advanced Settings
    var fontName: String = "Serif"
    var lineHeight: CGFloat = 8.0
    
    init(book: Book) {
        self.book = book
        self.fontSize = UserDefaults.standard.double(forKey: "reader_fontSize")
        if self.fontSize == 0 { self.fontSize = 18.0 }
        
        if let data = UserDefaults.standard.data(forKey: "reader_theme_style"),
           let style = try? JSONDecoder().decode(AppTheme.ThemeStyle.self, from: data) {
            self.theme = AppTheme(style: style)
        }
        
        // Load saved progress or settings if applicable
    }
    
    // Updates progress. Reference:
    // - .text: 0.0 to 1.0 (scroll percentage)
    // - .pdf/.comic: Page Index (e.g. 5.0 = Page 5)
    func updateProgress(_ newProgress: Double) {
        book.progress = newProgress
        book.lastReadDate = Date()
    }
    
    func toggleTheme() {
        switch theme.style {
        case .default:
            theme = .dark
        case .dark:
            theme = .sepia
        case .sepia:
            theme = .default
        }
    }
    
    func toggleBookmark() {
        // Create new bookmark
        let newBookmark = Bookmark(pageOrLocation: Int(book.progress * 100), note: "Saved at \(Date().formatted(date: .numeric, time: .shortened))")
        
        // Append to book
        book.bookmarks.append(newBookmark)
        isBookmarked = true
        
        // In SwiftData, appending to the relationship and keeping the object in the context should auto-save or wait for autosave.
        // However, we often want to ensure it's persisted, especially before closing.
        // We rely on the View's modelContext or the Book's own context reference if available.
        // Since `book` is a Model actor, changes are tracked.
    }
}
