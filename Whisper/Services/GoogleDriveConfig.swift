//
//  GoogleDriveConfig.swift
//  Whisper
//
//  Created by Anurag Ambuj on 24/09/26.
//

import Foundation
import Security

/// Secure configuration and secret management for Google Drive integration.
/// Reads credentials from gitignored local files (Secrets.plist / Secrets.xcconfig),
/// environment variables, or Apple Keychain without committing private secrets to GitHub.
final class GoogleDriveConfig: @unchecked Sendable {
    static let shared = GoogleDriveConfig()
    
    private let keychainService = "com.anuragambuj.whisper.gdrive"
    private let keychainAccount = "client_id"
    
    // Obfuscation salt & placeholder scrambled sequence (safe for git)
    private let salt: [UInt8] = Array("WhisperGDriveOAuth2".utf8)
    private let scrambledClientID: [UInt8] = [
        38, 77, 81, 79, 97, 85, 87, 86, 73, 76, 75, 78, 107, 72, 85, 74,
        83, 70, 77, 97, 87, 94, 88, 81, 91, 64, 73, 91, 74, 89, 87, 83
    ]
    
    private let defaultPlaceholderClientID = ""
    
    private init() {}
    
    /// The resolved Client ID used for Google OAuth 2.0 PKCE.
    /// Priority order:
    /// 1. Gitignored local Secrets.plist (bundled or workspace during dev)
    /// 2. Info.plist (`GIDClientID` or `GoogleClientID`)
    /// 3. Environment variable (`GOOGLE_CLIENT_ID`)
    /// 4. Apple Keychain stored client ID
    /// 5. De-obfuscated secure credential
    nonisolated var clientID: String {
        // 1. Check local gitignored Secrets.plist (Bundle)
        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let plistKey = dict["GOOGLE_CLIENT_ID"] as? String,
           !plistKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return plistKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 1b. Check local gitignored Secrets.plist (Development source tree)
        let devSecretsURL = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // Whisper
            .appendingPathComponent("Secrets.plist")
        if FileManager.default.fileExists(atPath: devSecretsURL.path),
           let dict = NSDictionary(contentsOfFile: devSecretsURL.path) as? [String: Any],
           let devKey = dict["GOOGLE_CLIENT_ID"] as? String,
           !devKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return devKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 2. Info.plist
        if let plistID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String {
            let trimmed = plistID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.contains("$(") && !trimmed.contains("YOUR_") {
                return trimmed
            }
        }
        if let plistID = Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String {
            let trimmed = plistID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.contains("$(") && !trimmed.contains("YOUR_") {
                return trimmed
            }
        }
        
        // 3. Environment variable
        if let envID = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_ID"],
           !envID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return envID.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 4. Keychain
        if let keychainID = getKeychainClientID(), !keychainID.isEmpty {
            return keychainID
        }
        
        // 5. Deobfuscate built-in
        let deobfuscated = deobfuscateClientID()
        if !deobfuscated.isEmpty {
            return deobfuscated
        }
        
        return defaultPlaceholderClientID
    }
    
    /// Reversed Client ID scheme required by Google iOS OAuth redirects
    nonisolated var reversedClientID: String {
        let currentID = clientID
        if currentID.contains(".apps.googleusercontent.com") {
            let prefix = currentID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
            return "com.googleusercontent.apps.\(prefix)"
        }
        return "whisper"
    }
    
    /// Primary OAuth redirect URI
    nonisolated var redirectURI: String {
        return "\(reversedClientID):/oauth2redirect"
    }
    
    /// Secondary fallback redirect URI
    nonisolated var fallbackRedirectURI: String {
        return "whisper:/oauth2redirect"
    }
    
    // MARK: - Secret De-obfuscation
    
    nonisolated private func deobfuscateClientID() -> String {
        guard !salt.isEmpty else { return "" }
        var result = [UInt8]()
        result.reserveCapacity(scrambledClientID.count)
        for (i, byte) in scrambledClientID.enumerated() {
            let s = salt[i % salt.count]
            result.append(byte ^ s)
        }
        let recovered = String(decoding: result, as: UTF8.self).trimmingCharacters(in: .controlCharacters)
        if recovered.contains(".apps.googleusercontent.com") {
            return recovered
        }
        return ""
    }
    
    // MARK: - Keychain
    
    nonisolated private func getKeychainClientID() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let id = String(data: data, encoding: .utf8) else {
            return nil
        }
        return id
    }
    
    nonisolated func setKeychainClientID(_ newID: String) {
        let trimmed = newID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var newQuery = query
            newQuery[kSecValueData as String] = data
            SecItemAdd(newQuery as CFDictionary, nil)
        }
    }
}
