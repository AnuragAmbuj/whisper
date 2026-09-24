//
//  GoogleDriveConfig.swift
//  Whisper
//
//  Created by Anurag Ambuj on 24/09/26.
//

import Foundation
import Security

/// Secure configuration and credential management for Google Drive integration.
/// Obfuscates built-in credentials and protects tokens in Apple Keychain.
/// Eliminates any need for the end-user to configure developer API keys.
final class GoogleDriveConfig: @unchecked Sendable {
    static let shared = GoogleDriveConfig()
    
    private let keychainService = "com.anuragambuj.whisper.gdrive"
    private let keychainAccount = "client_id"
    
    // Obfuscation salt & key for built-in Whisper OAuth Client ID
    private let salt: [UInt8] = Array("WhisperGDriveOAuth2".utf8)
    private let scrambledClientID: [UInt8] = [
        98, 93, 95, 67, 66, 84, 68, 113, 114, 65, 94, 79, 72, 63, 36, 30,
        69, 9, 3, 51, 29, 13, 6, 66, 3, 70, 127, 115, 66, 14, 16, 80,
        120, 42, 65, 5, 29, 90, 50, 9, 26, 6, 3, 22, 6, 105, 37, 2,
        25, 5, 75, 40, 46, 26, 19, 4, 87, 34, 27, 12, 1, 19, 10, 28,
        51, 33, 28, 29, 88, 6, 32, 44
    ]
    
    // Fallback bundled client ID for Whisper
    private let defaultBundledClientID = "556021666379-pek1a1dudu2f4870gf57k4quheasusst.apps.googleusercontent.com"
    
    private init() {}
    
    /// The resolved Client ID used for Google OAuth 2.0 PKCE.
    /// Precedence:
    /// 1. Info.plist (`GIDClientID` or `GoogleClientID`)
    /// 2. Environment variable (`GOOGLE_CLIENT_ID`)
    /// 3. Keychain stored client ID
    /// 4. De-obfuscated secure built-in credential
    nonisolated var clientID: String {
        // 1. Info.plist
        if let plistID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
           !plistID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return plistID.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let plistID = Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String,
           !plistID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return plistID.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 2. Environment variable
        if let envID = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_ID"],
           !envID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return envID.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 3. Keychain
        if let keychainID = getKeychainClientID(), !keychainID.isEmpty {
            return keychainID
        }
        
        // 4. Deobfuscate built-in
        let deobfuscated = deobfuscateClientID()
        if !deobfuscated.isEmpty {
            return deobfuscated
        }
        
        return defaultBundledClientID
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
        return defaultBundledClientID
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
