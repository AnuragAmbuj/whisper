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
    var theme: AppTheme
    var fontSize: Double = 18.0
    var lineHeight: CGFloat = 1.8
    var isBookmarked: Bool = false
    
    private let keyThemeStyle = "reader_theme_style"
    private let keyFontSize = "reader_fontSize"
    private let keyLineHeight = "reader_lineHeight"
    
    init(book: Book) {
        self.book = book
        self.theme = AppTheme()
        loadSettings()
    }
    
    private func loadSettings() {
        if let styleString = UserDefaults.standard.string(forKey: keyThemeStyle),
           let style = AppTheme.ThemeStyle(rawValue: styleString) {
            theme = AppTheme(style: style)
        }
        
        let savedFontSize = UserDefaults.standard.double(forKey: keyFontSize)
        if savedFontSize > 0 {
            fontSize = savedFontSize
            theme.fontSize = savedFontSize
        }
        
        let savedLineHeight = UserDefaults.standard.double(forKey: keyLineHeight)
        if savedLineHeight > 0 {
            lineHeight = savedLineHeight
            theme.lineHeight = savedLineHeight
        }
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(theme.style.rawValue, forKey: keyThemeStyle)
        UserDefaults.standard.set(fontSize, forKey: keyFontSize)
        UserDefaults.standard.set(lineHeight, forKey: keyLineHeight)
    }
    
    func updateProgress(_ newProgress: Double) {
        book.progress = newProgress
        book.lastReadDate = Date()
    }
    
    func toggleTheme() {
        switch theme.style {
        case .default:
            theme = AppTheme(style: .dark)
        case .dark:
            theme = AppTheme(style: .sepia)
        case .sepia:
            theme = AppTheme(style: .light)
        case .light:
            theme = AppTheme(style: .default)
        }
        theme.fontSize = fontSize
        theme.lineHeight = lineHeight
        saveSettings()
    }
    
    func setTheme(_ style: AppTheme.ThemeStyle) {
        theme = AppTheme(style: style)
        theme.fontSize = fontSize
        theme.lineHeight = lineHeight
        saveSettings()
    }
    
    func increaseFontSize() {
        fontSize = min(fontSize + 2, 32)
        theme.fontSize = fontSize
        saveSettings()
    }
    
    func decreaseFontSize() {
        fontSize = max(fontSize - 2, 12)
        theme.fontSize = fontSize
        saveSettings()
    }
    
    func increaseLineHeight() {
        lineHeight = min(lineHeight + 0.2, 3.0)
        theme.lineHeight = lineHeight
        saveSettings()
    }
    
    func decreaseLineHeight() {
        lineHeight = max(lineHeight - 0.2, 1.0)
        theme.lineHeight = lineHeight
        saveSettings()
    }
    
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
