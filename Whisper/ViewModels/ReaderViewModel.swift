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
    var fontName: String = "Serif"
    var isBookmarked: Bool = false
    var currentLocation: Int = 0
    
    private let keyThemeStyle = "reader_theme_style"
    private let keyFontSize = "reader_fontSize"
    private let keyLineHeight = "reader_lineHeight"
    private let keyFontName = "reader_font_name"
    
    init(book: Book) {
        self.book = book
        self.theme = AppTheme()
        // Apply latest reading state from iCloud if newer
        CloudSyncService.shared.applyLatestCloudReadingProgress(for: book)
        self.currentLocation = Int(book.progress * 100)
        loadSettings()
        checkIfBookmarked()
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
        
        if let savedFontName = UserDefaults.standard.string(forKey: keyFontName), !savedFontName.isEmpty {
            fontName = savedFontName
            theme.fontName = savedFontName
        }
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(theme.style.rawValue, forKey: keyThemeStyle)
        UserDefaults.standard.set(fontSize, forKey: keyFontSize)
        UserDefaults.standard.set(lineHeight, forKey: keyLineHeight)
        UserDefaults.standard.set(fontName, forKey: keyFontName)
    }
    
    func updateProgress(_ newProgress: Double) {
        book.progress = min(max(newProgress, 0.0), 1.0)
        book.lastReadDate = Date()
        CloudSyncService.shared.saveReadingProgress(for: book)
    }
    
    func updateLocation(_ location: Int) {
        currentLocation = location
        checkIfBookmarked()
    }
    
    func checkIfBookmarked() {
        isBookmarked = (book.bookmarks ?? []).contains(where: { $0.pageOrLocation == currentLocation })
    }
    
    func toggleTheme() {
        let allStyles = AppTheme.ThemeStyle.allCases
        if let currentIndex = allStyles.firstIndex(of: theme.style) {
            let nextIndex = (currentIndex + 1) % allStyles.count
            setTheme(allStyles[nextIndex])
        } else {
            setTheme(.default)
        }
    }
    
    func setTheme(_ style: AppTheme.ThemeStyle) {
        theme = AppTheme(style: style)
        theme.fontSize = fontSize
        theme.lineHeight = lineHeight
        theme.fontName = fontName
        saveSettings()
    }
    
    func setFontName(_ name: String) {
        fontName = name
        theme.fontName = name
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
        if isBookmarked {
            if let index = (book.bookmarks ?? []).firstIndex(where: { $0.pageOrLocation == currentLocation }) {
                book.bookmarks?.remove(at: index)
            } else if !(book.bookmarks ?? []).isEmpty {
                book.bookmarks?.removeLast()
            }
            isBookmarked = false
        } else {
            let noteText: String
            switch book.format ?? .text {
            case .pdf, .comic:
                noteText = "Page \(currentLocation + 1)"
            case .epub:
                noteText = "Chapter \(currentLocation + 1)"
            case .text:
                noteText = "\(currentLocation)% completed"
            }
            
            let newBookmark = Bookmark(
                pageOrLocation: currentLocation,
                note: "\(noteText) • \(Date().formatted(date: .abbreviated, time: .shortened))"
            )
            book.addBookmark(newBookmark)
            isBookmarked = true
        }
        CloudSyncService.shared.saveBookmarks(for: book)
    }
    
    func removeBookmark(_ bookmark: Bookmark) {
        if let index = (book.bookmarks ?? []).firstIndex(where: { $0.id == bookmark.id }) {
            book.bookmarks?.remove(at: index)
            if (book.bookmarks ?? []).isEmpty {
                isBookmarked = false
            }
            CloudSyncService.shared.saveBookmarks(for: book)
        }
    }
    
    func removeAllBookmarks() {
        book.bookmarks?.removeAll()
        isBookmarked = false
        CloudSyncService.shared.saveBookmarks(for: book)
    }
}
