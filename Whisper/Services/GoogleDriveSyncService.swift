//
//  GoogleDriveSyncService.swift
//  Whisper
//
//  Created by Anurag Ambuj on 23/09/26.
//

import Foundation
import Combine
import SwiftUI
import CryptoKit
import AuthenticationServices

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Direct Google Drive REST v3 API and Linked Folder synchronization service.
/// Connects natively to Google Drive via OAuth 2.0 PKCE and standard Google REST APIs.
@MainActor
final class GoogleDriveSyncService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleDriveSyncService()
    
    // MARK: - Published Properties
    
    @Published var isDirectAPIConnected: Bool = false
    @Published var directUserEmail: String? = nil
    @Published var isLinkedFolderActive: Bool = false
    @Published var linkedFolderName: String? = nil
    
    @Published var isSyncing: Bool = false
    @Published var syncStatusMessage: String? = nil
    @Published var lastSyncDate: Date? = nil
    @Published var lastErrorMessage: String? = nil
    
    // MARK: - Configuration & Storage Keys
    
    private let kKeychainService = "club.ironlattice.whisper.gdrive"
    private let kKeychainAccessToken = "access_token"
    private let kKeychainRefreshToken = "refresh_token"
    private let kUserDefaultsUserEmail = "whisper_gdrive_email"
    private let kUserDefaultsClientID = "whisper_gdrive_client_id"
    private let kUserDefaultsFolderID = "whisper_gdrive_folder_id"
    private let kLinkedFolderBookmark = "whisper_gdrive_folder_bookmark"
    private let kSyncFileName = "whisper_sync.json"
    
    // Google OAuth Endpoints & Scopes
    private let authURLString = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenURLString = "https://oauth2.googleapis.com/token"
    private let userinfoURLString = "https://www.googleapis.com/oauth2/v3/userinfo"
    private let driveFilesURLString = "https://www.googleapis.com/drive/v3/files"
    private let driveUploadURLString = "https://www.googleapis.com/upload/drive/v3/files"
    private let driveScope = "https://www.googleapis.com/auth/drive.file email"
    private let redirectURI = "whisper:/oauth2redirect"
    
    /// User or App OAuth Client ID
    var clientID: String {
        get {
            UserDefaults.standard.string(forKey: kUserDefaultsClientID) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: kUserDefaultsClientID)
        }
    }
    
    private var rootFolderID: String? {
        get { UserDefaults.standard.string(forKey: kUserDefaultsFolderID) }
        set { UserDefaults.standard.set(newValue, forKey: kUserDefaultsFolderID) }
    }
    
    private var securityScopedURL: URL? = nil
    private var authSession: ASWebAuthenticationSession?
    
    // MARK: - Sync Payload Format
    
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
        restoreAuthTokens()
        restoreLinkedFolder()
    }
    
    // MARK: - ASWebAuthenticationPresentationContextProviding
    
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let window = scene.windows.first(where: { $0.isKeyWindow }) {
                return window
            }
        }
        return ASPresentationAnchor()
        #elseif os(macOS)
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #endif
    }
    
    // MARK: - OAuth 2.0 PKCE Direct Login
    
    /// Generates high-entropy cryptographic code verifier
    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    /// Computes SHA-256 base64url challenge for PKCE
    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        let hashed = SHA256.hash(data: data)
        return Data(hashed).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    /// Starts direct Google sign-in using Apple's ASWebAuthenticationSession
    func signInWithGoogle() async throws {
        let activeClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !activeClientID.isEmpty else {
            throw NSError(
                domain: "GoogleDriveSync",
                code: 101,
                userInfo: [NSLocalizedDescriptionKey: "Please enter your Google Cloud OAuth Client ID in Settings."]
            )
        }
        
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        
        var components = URLComponents(string: authURLString)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: activeClientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: driveScope),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "access_type", value: "offline")
        ]
        
        guard let authURL = components.url else {
            throw NSError(domain: "GoogleDriveSync", code: 102, userInfo: [NSLocalizedDescriptionKey: "Invalid OAuth URL"])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "whisper"
            ) { [weak self] callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let callbackURL = callbackURL,
                      let urlComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let authCode = urlComponents.queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: NSError(
                        domain: "GoogleDriveSync",
                        code: 103,
                        userInfo: [NSLocalizedDescriptionKey: "Missing authorization code from Google."]
                    ))
                    return
                }
                
                Task { @MainActor [weak self] in
                    do {
                        try await self?.exchangeCodeForTokens(code: authCode, codeVerifier: codeVerifier)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }
    }
    
    /// Exchanges authorization code for access and refresh tokens
    private func exchangeCodeForTokens(code: String, codeVerifier: String) async throws {
        guard let url = URL(string: tokenURLString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let activeClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyParameters: [String: String] = [
            "code": code,
            "client_id": activeClientID,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": codeVerifier
        ]
        
        let bodyString = bodyParameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown token error"
            throw NSError(domain: "GoogleDriveSync", code: 104, userInfo: [NSLocalizedDescriptionKey: errorText])
        }
        
        struct TokenResponse: Codable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int
        }
        
        let tokenData = try JSONDecoder().decode(TokenResponse.self, from: data)
        saveKeychainItem(key: kKeychainAccessToken, value: tokenData.access_token)
        if let refresh = tokenData.refresh_token {
            saveKeychainItem(key: kKeychainRefreshToken, value: refresh)
        }
        
        // Fetch user profile email
        await fetchUserProfile(accessToken: tokenData.access_token)
        self.isDirectAPIConnected = true
        self.lastErrorMessage = nil
    }
    
    /// Retrieves user email from Google
    private func fetchUserProfile(accessToken: String) async {
        guard let url = URL(string: userinfoURLString) else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        if let (data, response) = try? await URLSession.shared.data(for: request),
           let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let email = json["email"] as? String {
            self.directUserEmail = email
            UserDefaults.standard.set(email, forKey: kUserDefaultsUserEmail)
        }
    }
    
    /// Restores authentication from Keychain on app launch
    private func restoreAuthTokens() {
        if let token = getKeychainItem(key: kKeychainAccessToken), !token.isEmpty {
            self.directUserEmail = UserDefaults.standard.string(forKey: kUserDefaultsUserEmail)
            self.isDirectAPIConnected = true
        }
    }
    
    /// Sign out and delete tokens
    func signOutDirectAccount() {
        deleteKeychainItem(key: kKeychainAccessToken)
        deleteKeychainItem(key: kKeychainRefreshToken)
        UserDefaults.standard.removeObject(forKey: kUserDefaultsUserEmail)
        UserDefaults.standard.removeObject(forKey: kUserDefaultsFolderID)
        self.directUserEmail = nil
        self.rootFolderID = nil
        self.isDirectAPIConnected = false
    }
    
    /// Gets a valid access token, auto-refreshing via refresh_token if needed
    private func getValidAccessToken() async throws -> String {
        if let token = getKeychainItem(key: kKeychainAccessToken), !token.isEmpty {
            return token
        }
        
        guard let refreshToken = getKeychainItem(key: kKeychainRefreshToken), !refreshToken.isEmpty else {
            throw NSError(domain: "GoogleDriveSync", code: 401, userInfo: [NSLocalizedDescriptionKey: "Please sign in to Google Drive."])
        }
        
        // Refresh token
        guard let url = URL(string: tokenURLString) else {
            throw NSError(domain: "GoogleDriveSync", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid token URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParameters: [String: String] = [
            "refresh_token": refreshToken,
            "client_id": clientID.trimmingCharacters(in: .whitespacesAndNewlines),
            "grant_type": "refresh_token"
        ]
        
        let bodyString = bodyParameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "GoogleDriveSync", code: 401, userInfo: [NSLocalizedDescriptionKey: "Session expired. Please sign in again."])
        }
        
        struct RefreshResponse: Codable {
            let access_token: String
        }
        let refreshed = try JSONDecoder().decode(RefreshResponse.self, from: data)
        saveKeychainItem(key: kKeychainAccessToken, value: refreshed.access_token)
        return refreshed.access_token
    }
    
    // MARK: - Google Drive REST Operations
    
    /// Finds or creates the "Whisper Library" root folder in Google Drive
    private func getOrCreateWhisperFolder(token: String) async throws -> String {
        if let existing = self.rootFolderID {
            return existing
        }
        
        // 1. Search for existing folder
        var components = URLComponents(string: driveFilesURLString)!
        components.queryItems = [
            URLQueryItem(name: "q", value: "name = 'Whisper Library' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"),
            URLQueryItem(name: "fields", value: "files(id, name)")
        ]
        
        var searchReq = URLRequest(url: components.url!)
        searchReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: searchReq)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let files = json["files"] as? [[String: Any]],
           let first = files.first,
           let id = first["id"] as? String {
            self.rootFolderID = id
            return id
        }
        
        // 2. Create folder
        guard let createURL = URL(string: driveFilesURLString) else {
            throw NSError(domain: "GoogleDriveSync", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid drive files URL"])
        }
        
        var createReq = URLRequest(url: createURL)
        createReq.httpMethod = "POST"
        createReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        createReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let folderMeta: [String: Any] = [
            "name": "Whisper Library",
            "mimeType": "application/vnd.google-apps.folder"
        ]
        createReq.httpBody = try JSONSerialization.data(withJSONObject: folderMeta)
        
        let (createData, createResp) = try await URLSession.shared.data(for: createReq)
        guard let httpResp = createResp as? HTTPURLResponse, (200...299).contains(httpResp.statusCode),
              let createdJson = try? JSONSerialization.jsonObject(with: createData) as? [String: Any],
              let newID = createdJson["id"] as? String else {
            throw NSError(domain: "GoogleDriveSync", code: 501, userInfo: [NSLocalizedDescriptionKey: "Failed to create 'Whisper Library' folder."])
        }
        
        self.rootFolderID = newID
        return newID
    }
    
    /// Uploads a book file directly to Google Drive via multipart upload
    func uploadBookDirect(fileURL: URL) async throws {
        let token = try await getValidAccessToken()
        let folderId = try await getOrCreateWhisperFolder(token: token)
        let fileName = fileURL.lastPathComponent
        
        // Check if file already exists in folder
        var checkComponents = URLComponents(string: driveFilesURLString)!
        let escapedFileName = fileName.replacingOccurrences(of: "'", with: "\\'")
        checkComponents.queryItems = [
            URLQueryItem(name: "q", value: "name = '\(escapedFileName)' and '\(folderId)' in parents and trashed = false"),
            URLQueryItem(name: "fields", value: "files(id, name)")
        ]
        
        var checkReq = URLRequest(url: checkComponents.url!)
        checkReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let (checkData, _) = try? await URLSession.shared.data(for: checkReq),
           let checkJson = try? JSONSerialization.jsonObject(with: checkData) as? [String: Any],
           let files = checkJson["files"] as? [[String: Any]], !files.isEmpty {
            // Already uploaded
            return
        }
        
        // Multipart upload
        guard let uploadURL = URL(string: "\(driveUploadURLString)?uploadType=multipart") else { return }
        let boundary = "WhisperBoundary\(UUID().uuidString)"
        
        var uploadReq = URLRequest(url: uploadURL)
        uploadReq.httpMethod = "POST"
        uploadReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        uploadReq.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let metadata: [String: Any] = [
            "name": fileName,
            "parents": [folderId]
        ]
        
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        let fileData = try Data(contentsOf: fileURL)
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadataData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        uploadReq.httpBody = body
        
        let (_, uploadResp) = try await URLSession.shared.data(for: uploadReq)
        if let http = uploadResp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
            print("GoogleDriveSync: Successfully uploaded '\(fileName)' directly to Google Drive.")
        }
    }
    
    /// Synchronizes reading progress and bookmarks via `whisper_sync.json` directly in Google Drive
    func syncProgressDirect(localBooks: [Book]) async {
        guard let token = try? await getValidAccessToken(),
              let folderId = try? await getOrCreateWhisperFolder(token: token) else { return }
        
        // Search for existing whisper_sync.json
        var searchComp = URLComponents(string: driveFilesURLString)!
        searchComp.queryItems = [
            URLQueryItem(name: "q", value: "name = '\(kSyncFileName)' and '\(folderId)' in parents and trashed = false"),
            URLQueryItem(name: "fields", value: "files(id, name)")
        ]
        
        var searchReq = URLRequest(url: searchComp.url!)
        searchReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        var syncFileID: String? = nil
        var payload = RemoteSyncPayload()
        
        if let (sData, _) = try? await URLSession.shared.data(for: searchReq),
           let json = try? JSONSerialization.jsonObject(with: sData) as? [String: Any],
           let files = json["files"] as? [[String: Any]],
           let first = files.first,
           let id = first["id"] as? String {
            syncFileID = id
            
            // Download existing payload
            if let downloadURL = URL(string: "\(driveFilesURLString)/\(id)?alt=media") {
                var downReq = URLRequest(url: downloadURL)
                downReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                if let (downData, _) = try? await URLSession.shared.data(for: downReq),
                   let decoded = try? JSONDecoder().decode(RemoteSyncPayload.self, from: downData) {
                    payload = decoded
                }
            }
        }
        
        // Merge progress
        for book in localBooks {
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
        
        payload.updatedAt = Date().timeIntervalSince1970
        guard let payloadData = try? JSONEncoder().encode(payload) else { return }
        
        // Upload updated payload
        if let fileID = syncFileID {
            // Update file content
            if let updateURL = URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(fileID)?uploadType=media") {
                var updateReq = URLRequest(url: updateURL)
                updateReq.httpMethod = "PATCH"
                updateReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                updateReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                updateReq.httpBody = payloadData
                _ = try? await URLSession.shared.data(for: updateReq)
            }
        } else {
            // Create file
            if let createURL = URL(string: "\(driveUploadURLString)?uploadType=multipart") {
                let boundary = "SyncBoundary\(UUID().uuidString)"
                var createReq = URLRequest(url: createURL)
                createReq.httpMethod = "POST"
                createReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                createReq.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                
                let metadata: [String: Any] = [
                    "name": kSyncFileName,
                    "parents": [folderId]
                ]
                let metaData = (try? JSONSerialization.data(withJSONObject: metadata)) ?? Data()
                
                var body = Data()
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
                body.append(metaData)
                body.append("\r\n".data(using: .utf8)!)
                
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
                body.append(payloadData)
                body.append("\r\n".data(using: .utf8)!)
                body.append("--\(boundary)--\r\n".data(using: .utf8)!)
                
                createReq.httpBody = body
                _ = try? await URLSession.shared.data(for: createReq)
            }
        }
    }
    
    /// Queries remote books in Google Drive folder and auto-downloads any missing files
    func fetchRemoteBooksDirect(
        existingBooks: [Book],
        onImportNewBook: @escaping (URL) async -> Void
    ) async {
        guard let token = try? await getValidAccessToken(),
              let folderId = try? await getOrCreateWhisperFolder(token: token) else { return }
        
        var comp = URLComponents(string: driveFilesURLString)!
        comp.queryItems = [
            URLQueryItem(name: "q", value: "'\(folderId)' in parents and mimeType != 'application/vnd.google-apps.folder' and trashed = false"),
            URLQueryItem(name: "fields", value: "files(id, name, mimeType)")
        ]
        
        var req = URLRequest(url: comp.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]] else { return }
        
        let existingFilenames = Set(existingBooks.compactMap { $0.url?.lastPathComponent })
        let existingTitles = Set(existingBooks.map { $0.title.lowercased() })
        let supportedExtensions = Set(["epub", "pdf", "cbz", "cbr", "txt", "md"])
        
        for file in files {
            guard let name = file["name"] as? String,
                  let id = file["id"] as? String else { continue }
            
            if name == kSyncFileName { continue }
            
            let ext = (name as NSString).pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }
            
            let titleGuess = (name as NSString).deletingPathExtension.lowercased()
            if !existingFilenames.contains(name) && !existingTitles.contains(titleGuess) {
                // Download file
                guard let downURL = URL(string: "\(driveFilesURLString)/\(id)?alt=media") else { continue }
                var downReq = URLRequest(url: downURL)
                downReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                if let (fileContent, _) = try? await URLSession.shared.data(for: downReq) {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                    do {
                        try fileContent.write(to: tempURL, options: .atomic)
                        await onImportNewBook(tempURL)
                    } catch {
                        print("GoogleDriveSync: Failed to save downloaded book '\(name)': \(error)")
                    }
                }
            }
        }
    }
    
    // MARK: - Mode 2: Linked Folder Support
    
    private func restoreLinkedFolder() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: kLinkedFolderBookmark) else { return }
        var isStale = false
        #if os(macOS)
        let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
        #else
        let url = try? URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        #endif
        if let url = url {
            self.securityScopedURL = url
            self.linkedFolderName = url.lastPathComponent
            self.isLinkedFolderActive = true
        }
    }
    
    func setLinkedFolder(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        
        #if os(macOS)
        let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        let bookmark = try? url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
        if let bookmark = bookmark {
            UserDefaults.standard.set(bookmark, forKey: kLinkedFolderBookmark)
            self.securityScopedURL = url
            self.linkedFolderName = url.lastPathComponent
            self.isLinkedFolderActive = true
        }
    }
    
    func unlinkFolder() {
        UserDefaults.standard.removeObject(forKey: kLinkedFolderBookmark)
        self.securityScopedURL = nil
        self.linkedFolderName = nil
        self.isLinkedFolderActive = false
    }
    
    func exportBookToLinkedFolder(fileURL: URL) {
        guard let folderURL = securityScopedURL else { return }
        DispatchQueue.global(qos: .utility).async {
            let accessing = folderURL.startAccessingSecurityScopedResource()
            defer { if accessing { folderURL.stopAccessingSecurityScopedResource() } }
            
            let destURL = folderURL.appendingPathComponent(fileURL.lastPathComponent)
            if !FileManager.default.fileExists(atPath: destURL.path) {
                try? FileManager.default.copyItem(at: fileURL, to: destURL)
            }
        }
    }
    
    func scanLinkedFolderBooks() -> [URL] {
        guard let folderURL = securityScopedURL else { return [] }
        let accessing = folderURL.startAccessingSecurityScopedResource()
        defer { if accessing { folderURL.stopAccessingSecurityScopedResource() } }
        
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
    
    private func readLinkedFolderSyncPayload() -> RemoteSyncPayload? {
        guard let folderURL = securityScopedURL else { return nil }
        let accessing = folderURL.startAccessingSecurityScopedResource()
        defer { if accessing { folderURL.stopAccessingSecurityScopedResource() } }
        let syncURL = folderURL.appendingPathComponent(kSyncFileName)
        guard FileManager.default.fileExists(atPath: syncURL.path),
              let data = try? Data(contentsOf: syncURL),
              let payload = try? JSONDecoder().decode(RemoteSyncPayload.self, from: data) else { return nil }
        return payload
    }
    
    private func writeLinkedFolderSyncPayload(_ payload: RemoteSyncPayload) {
        guard let folderURL = securityScopedURL else { return }
        let accessing = folderURL.startAccessingSecurityScopedResource()
        defer { if accessing { folderURL.stopAccessingSecurityScopedResource() } }
        let syncURL = folderURL.appendingPathComponent(kSyncFileName)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: syncURL, options: .atomic)
        }
    }
    
    // MARK: - Synchronizing Reading Progress
    
    func saveReadingProgress(for book: Book) {
        let idStr = book.id.uuidString
        let dateVal = book.lastReadDate.timeIntervalSince1970
        let marks = (book.safeBookmarks).map { $0.pageOrLocation }
        
        if isDirectAPIConnected {
            Task {
                await syncProgressDirect(localBooks: [book])
            }
        } else if isLinkedFolderActive {
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
    
    func applyLatestReadingProgress(for book: Book) {
        let idStr = book.id.uuidString
        if isLinkedFolderActive, let payload = readLinkedFolderSyncPayload(),
           let remoteItem = payload.books[idStr] {
            let remoteDate = Date(timeIntervalSince1970: remoteItem.lastReadTimestamp)
            if remoteDate > book.lastReadDate {
                book.progress = min(max(remoteItem.progress, 0.0), 1.0)
                book.lastReadDate = remoteDate
            }
        }
    }
    
    // MARK: - Unified Sync Trigger
    
    func triggerSync(
        existingBooks: [Book],
        onImportNewBook: @escaping (URL) async -> Void
    ) async {
        isSyncing = true
        lastErrorMessage = nil
        syncStatusMessage = "Syncing with Google Drive..."
        
        if isDirectAPIConnected {
            // Direct REST API Sync
            do {
                // 1. Upload local books
                for book in existingBooks {
                    if let url = book.resolvedURL {
                        try? await uploadBookDirect(fileURL: url)
                    }
                }
                
                // 2. Discover & download remote books
                await fetchRemoteBooksDirect(existingBooks: existingBooks, onImportNewBook: onImportNewBook)
                
                // 3. Sync reading progress & bookmarks
                await syncProgressDirect(localBooks: existingBooks)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        } else if isLinkedFolderActive {
            // Linked Folder Sync
            for book in existingBooks {
                if let url = book.resolvedURL {
                    exportBookToLinkedFolder(fileURL: url)
                }
            }
            
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
        
        self.lastSyncDate = Date()
        self.isSyncing = false
        self.syncStatusMessage = nil
    }
    
    // MARK: - Keychain Helpers
    
    private func saveKeychainItem(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kKeychainService,
            kSecAttrAccount as String: key
        ]
        
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var newQuery = query
            newQuery[kSecValueData as String] = data
            SecItemAdd(newQuery as CFDictionary, nil)
        }
    }
    
    private func getKeychainItem(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kKeychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    private func deleteKeychainItem(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kKeychainService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
