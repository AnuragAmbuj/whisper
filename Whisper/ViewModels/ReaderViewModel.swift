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
class ReaderViewModel: ObservableObject {
    @Published var book: Book
    var theme: AppTheme = .default
    var fontSize: Double = 18.0
    var lineHeight: CGFloat = 1.8
    var isBookmarked: Bool = false
    
    var theme: AppTheme = AppTheme()
    
    private let keyThemeStyle = "reader_theme_style"
    private let keyFontSize = "reader_fontSize"
    private let keyLineHeight = "reader_lineHeight"
    
    init(book: Book) {
        self.book = book
        loadSettings()
    }
    
    private func loadSettings() {
        if let styleString = UserDefaults.standard.string(forKey: keyThemeStyle),
           let style = AppTheme.ThemeStyle(rawValue: styleString) {
            theme = AppTheme(style: style)
        } else {
            theme = AppTheme()
        }
        
        theme.fontSize = UserDefaults.standard.double(forKey: keyFontSize)
        if theme.fontSize == 0 { theme.fontSize = 18.0 }
        
        theme.lineHeight = UserDefaults.standard.double(forKey: keyLineHeight) ?? 1.8
    }
    
    // MARK: - Progress Management
    func updateProgress(_ newProgress: Double) {
        book.progress = newProgress
        book.lastReadDate = Date()
    }
    
    // MARK: - Theme Management
    func toggleTheme() {
        switch theme.style {
        case .default:
            theme = AppTheme(style: .dark)
        case .dark:
            theme = AppTheme(style: .sepia)
        case .sepia:
            theme = AppTheme(style: .default)
        case .light:
            theme = AppTheme(style: .default)
        }
    }
    
    // MARK: - Bookmark Management
    func toggleBookmark() {
        guard !isBookmarked else { return }
        
        let newBookmark = Bookmark(
            pageOrLocation: Int(book.progress * 100),
            note: "Saved at \(Date().formatted(date: .numeric, time: .shortened))"
        )
        
        book.bookmarks.append(newBookmark)
        isBookmarked = true
    }
    
    func removeBookmark(_ bookmark: Bookmark) {
        if let index = book.bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            book.bookmarks.remove(at: index)
            if book.bookmarks.isEmpty {
                isBookmarked = false
            }
        }
    }
    
    func removeAllBookmarks() {
        book.bookmarks.removeAll()
        isBookmarked = false
    }
}