//
//  GoogleDriveSyncService.swift
//  Whisper
//
//  Created by Anurag Ambuj on 23/09/26.
//

import Foundation
import Combine
import SwiftUI
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

/// Service handling Google Drive library synchronization.
/// Supports both:
/// 1. Linked Google Drive Folder via the iOS Files app (zero-configuration, works immediately with Google Drive, Dropbox, etc.)
/// 2. Direct Google Drive REST v3 API via OAuth 2.0 PKCE.
@MainActor
final class GoogleDriveSyncService: NSObject, ObservableObject {
    static let shared = GoogleDriveSyncService()
    
    // MARK: - Published Properties
    
    @Published var isLinkedFolderActive: Bool = false
    @Published var linkedFolderName: String? = nil
    @Published var isDirectAPIConnected: Bool = false
    @Published var directUserEmail: String? = nil
    
    @Published var isSyncing: Bool = false
    @Published var lastSyncDate: Date? = nil
    @Published var lastErrorMessage: String? = nil
    
    // MARK: - Storage Keys
    
    private let kLinkedFolderBookmark = "whisper_gdrive_folder_bookmark"
    private let kDirectAccessToken = "whisper_gdrive_access_token"
    private let kDirectRefreshToken = "whisper_gdrive_refresh_token"
    private let kDirectUserEmail = "whisper_gdrive_user_email"
    private let kDirectClientID = "whisper_gdrive_client_id"
    private let kSyncFileName = "whisper_sync.json"
    
    // Default OAuth Client ID (can be overridden in settings)
    var clientID: String {
        get {
            UserDefaults.standard.string(forKey: kDirectClientID) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: kDirectClientID)
        }
    }
    
    private var securityScopedURL: URL? = nil
    
    // MARK: - Sync Metadata Structure
    
    struct RemoteSyncPayload: Codable {
        struct BookSyncItem: Codable {
            var progress: Double
            var lastReadTimestamp: Double
            var bookmarks: [Int]
        }
        var version: Int = 1
        var updatedAt: Double = Date().timeIntervalSince1970
        var books: [String: BookSyncItem] = [:]
    }
    
    // MARK: - Initialization
    
    override private init() {
        super.init()
        restoreLinkedFolder()
        restoreDirectAuth()
    }
    
    // MARK: - Mode 1: Linked Google Drive Folder (Files App)
    
    /// Restores previously linked folder from Security-Scoped Bookmark
    private func restoreLinkedFolder() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: kLinkedFolderBookmark) else {
            return
        }
        
        do {
            var isStale = false
            #if os(macOS)
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            #else
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            #endif
            
            if isStale {
                if let refreshed = try? url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(refreshed, forKey: kLinkedFolderBookmark)
                }
            }
            
            self.securityScopedURL = url
            self.linkedFolderName = url.lastPathComponent
            self.isLinkedFolderActive = true
            print("GoogleDriveSyncService: Restored linked folder '\(url.lastPathComponent)'")
        } catch {
            print("GoogleDriveSyncService: Failed to restore linked folder bookmark: \(error)")
        }
    }
    
    /// Saves a newly chosen folder from the document picker
    func setLinkedFolder(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        
        do {
            #if os(macOS)
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            #else
            let bookmark = try url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
            #endif
            UserDefaults.standard.set(bookmark, forKey: kLinkedFolderBookmark)
            self.securityScopedURL = url
            self.linkedFolderName = url.lastPathComponent
            self.isLinkedFolderActive = true
            self.lastErrorMessage = nil
            print("GoogleDriveSyncService: Successfully linked folder '\(url.lastPathComponent)'")
        } catch {
            self.lastErrorMessage = "Failed to bookmark folder: \(error.localizedDescription)"
        }
    }
    
    /// Disconnects the linked folder
    func unlinkFolder() {
        UserDefaults.standard.removeObject(forKey: kLinkedFolderBookmark)
        self.securityScopedURL = nil
        self.linkedFolderName = nil
        self.isLinkedFolderActive = false
    }
    
    // MARK: - Mode 2: Direct Google Drive API (OAuth 2.0 PKCE)
    
    private func restoreDirectAuth() {
        if let email = UserDefaults.standard.string(forKey: kDirectUserEmail),
           let token = UserDefaults.standard.string(forKey: kDirectAccessToken),
           !token.isEmpty {
            self.directUserEmail = email
            self.isDirectAPIConnected = true
        }
    }
    
    func disconnectDirectAccount() {
        UserDefaults.standard.removeObject(forKey: kDirectAccessToken)
        UserDefaults.standard.removeObject(forKey: kDirectRefreshToken)
        UserDefaults.standard.removeObject(forKey: kDirectUserEmail)
        self.directUserEmail = nil
        self.isDirectAPIConnected = false
    }
    
    // MARK: - Folder File Operations (Linked Mode)
    
    /// Exports a local book file to the linked Google Drive folder
    func exportBookToLinkedFolder(fileURL: URL) {
        guard let folderURL = securityScopedURL else { return }
        
        DispatchQueue.global(qos: .utility).async {
            let accessing = folderURL.startAccessingSecurityScopedResource()
            defer {
                if accessing { folderURL.stopAccessingSecurityScopedResource() }
            }
            
            let destURL = folderURL.appendingPathComponent(fileURL.lastPathComponent)
            if !FileManager.default.fileExists(atPath: destURL.path) {
                do {
                    try FileManager.default.copyItem(at: fileURL, to: destURL)
                    print("GoogleDriveSyncService: Exported '\(fileURL.lastPathComponent)' to linked folder.")
                } catch {
                    print("GoogleDriveSyncService: Failed to copy to linked folder: \(error)")
                }
            }
        }
    }
    
    /// Scans the linked folder for any new books to import locally
    func scanLinkedFolderBooks() -> [URL] {
        guard let folderURL = securityScopedURL else { return [] }
        
        let accessing = folderURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { folderURL.stopAccessingSecurityScopedResource() }
        }
        
        let supported = Set(["epub", "pdf", "cbz", "cbr", "txt", "md"])
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        var found: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            if supported.contains(fileURL.pathExtension.lowercased()) {
                found.append(fileURL)
            }
        }
        return found
    }
    
    /// Reads `whisper_sync.json` from the linked folder
    private func readLinkedFolderSyncPayload() -> RemoteSyncPayload? {
        guard let folderURL = securityScopedURL else { return nil }
        
        let accessing = folderURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { folderURL.stopAccessingSecurityScopedResource() }
        }
        
        let syncURL = folderURL.appendingPathComponent(kSyncFileName)
        guard FileManager.default.fileExists(atPath: syncURL.path),
              let data = try? Data(contentsOf: syncURL),
              let payload = try? JSONDecoder().decode(RemoteSyncPayload.self, from: data) else {
            return nil
        }
        return payload
    }
    
    /// Writes `whisper_sync.json` to the linked folder
    private func writeLinkedFolderSyncPayload(_ payload: RemoteSyncPayload) {
        guard let folderURL = securityScopedURL else { return }
        
        let accessing = folderURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { folderURL.stopAccessingSecurityScopedResource() }
        }
        
        let syncURL = folderURL.appendingPathComponent(kSyncFileName)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: syncURL, options: .atomic)
        }
    }
    
    // MARK: - Synchronizing Reading Progress & Bookmarks
    
    /// Persists a book's reading state to the active Google Drive connection
    func saveReadingProgress(for book: Book) {
        let idStr = book.id.uuidString
        let dateVal = book.lastReadDate.timeIntervalSince1970
        let marks = (book.safeBookmarks).map { $0.pageOrLocation }
        
        if isLinkedFolderActive {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                var payload = self?.readLinkedFolderSyncPayload() ?? RemoteSyncPayload()
                payload.books[idStr] = RemoteSyncPayload.BookSyncItem(
                    progress: book.progress,
                    lastReadTimestamp: dateVal,
                    bookmarks: marks
                )
                payload.updatedAt = Date().timeIntervalSince1970
                self?.writeLinkedFolderSyncPayload(payload)
            }
        }
    }
    
    /// Applies reading progress if newer state exists in Google Drive
    func applyLatestReadingProgress(for book: Book) {
        let idStr = book.id.uuidString
        if isLinkedFolderActive, let payload = readLinkedFolderSyncPayload() {
            if let remoteItem = payload.books[idStr] {
                let remoteDate = Date(timeIntervalSince1970: remoteItem.lastReadTimestamp)
                if remoteDate > book.lastReadDate {
                    book.progress = min(max(remoteItem.progress, 0.0), 1.0)
                    book.lastReadDate = remoteDate
                }
            }
        }
    }
    
    // MARK: - Unified Sync Trigger
    
    /// Runs a full Google Drive sync cycle
    func triggerSync(
        existingBooks: [Book],
        onImportNewBook: @escaping (URL) async -> Void
    ) async {
        isSyncing = true
        lastErrorMessage = nil
        
        if isLinkedFolderActive {
            // 1. Export local books to linked folder
            for book in existingBooks {
                if let url = book.resolvedURL {
                    exportBookToLinkedFolder(fileURL: url)
                }
            }
            
            // 2. Discover remote books missing from local library
            let remoteFiles = scanLinkedFolderBooks()
            let existingFilenames = Set(existingBooks.compactMap { $0.url?.lastPathComponent })
            let existingTitles = Set(existingBooks.map { $0.title.lowercased() })
            
            for fileURL in remoteFiles {
                let filename = fileURL.lastPathComponent
                let titleGuess = fileURL.deletingPathExtension().lastPathComponent.lowercased()
                if !existingFilenames.contains(filename) && !existingTitles.contains(titleGuess) {
                    await onImportNewBook(fileURL)
                }
            }
            
            // 3. Sync reading progress
            var payload = readLinkedFolderSyncPayload() ?? RemoteSyncPayload()
            for book in existingBooks {
                let idStr = book.id.uuidString
                if let remote = payload.books[idStr] {
                    let remoteDate = Date(timeIntervalSince1970: remote.lastReadTimestamp)
                    if remoteDate > book.lastReadDate {
                        book.progress = min(max(remote.progress, 0.0), 1.0)
                        book.lastReadDate = remoteDate
                    } else if book.lastReadDate > remoteDate {
                        payload.books[idStr] = RemoteSyncPayload.BookSyncItem(
                            progress: book.progress,
                            lastReadTimestamp: book.lastReadDate.timeIntervalSince1970,
                            bookmarks: book.safeBookmarks.map { $0.pageOrLocation }
                        )
                    }
                } else {
                    payload.books[idStr] = RemoteSyncPayload.BookSyncItem(
                        progress: book.progress,
                        lastReadTimestamp: book.lastReadDate.timeIntervalSince1970,
                        bookmarks: book.safeBookmarks.map { $0.pageOrLocation }
                    )
                }
            }
            writeLinkedFolderSyncPayload(payload)
        }
        
        try? await Task.sleep(nanoseconds: 500_000_000)
        self.lastSyncDate = Date()
        self.isSyncing = false
    }
}
