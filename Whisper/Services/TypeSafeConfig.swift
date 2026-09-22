//
//  TypeSafeConfig.swift
//  Whisper
//
//  Created by Anurag Ambuj on 22/09/26.
//

import Foundation
import Security

/// Secure configuration and secret management for TypeSafe AI (System One).
/// Keeps API credentials protected via Apple Keychain and byte-scrambling.
final class TypeSafeConfig: @unchecked Sendable {
  static let shared = TypeSafeConfig()

  private let keychainService = "com.anuragambuj.whisper.typesafe"
  private let keychainAccount = "api_key"

  // Salt and obfuscated key sequence (prevents plain-text strings in compiled binary)
  private let salt: [UInt8] = Array("WhisperSystemOne".utf8)
  private let scrambledKey: [UInt8] = [
    54, 24, 0, 24, 21, 28, 45, 97, 79, 64, 67, 85, 11, 46, 89, 6,
    100, 81, 11, 68, 68, 1, 70, 103, 76, 69, 76, 87, 88, 43, 13, 4,
    102, 80, 81, 66, 21, 84, 70, 99, 77, 75, 43, 92, 93, 46, 95, 6,
    54, 9, 80, 18, 68, 0, 67, 106, 76, 70, 65, 6, 88, 122, 11, 3,
    97, 88, 10, 67, 17, 85, 71, 49, 73, 75, 16, 85, 92, 126, 12, 1,
    103, 81, 10, 71, 66, 84, 22, 102, 74, 22, 76, 83, 91, 42, 11, 4,
    51, 13, 93, 65, 20, 1, 68, 53, 24, 70, 22
  ]

  nonisolated let baseURL = URL(string: "https://api.typesafe.ai/v1/systemone")!
  nonisolated let defaultModel = "jev-latest"

  private init() {
    // Automatically seed into Keychain if not present
    if getKeychainAPIKey() == nil {
      let recovered = deobfuscateKey()
      if !recovered.isEmpty {
        setKeychainAPIKey(recovered)
      }
    }
  }

  /// Retrieves the TypeSafe API Key.
  /// Precedence:
  /// 1. Environment variable (`TYPESAFE_API_KEY`)
  /// 2. Apple Keychain entry
  /// 3. De-obfuscated secure seed
  nonisolated var apiKey: String {
    if let envKey = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"],
       !envKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return envKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    if let keychainKey = getKeychainAPIKey(), !keychainKey.isEmpty {
      return keychainKey
    }

    return deobfuscateKey()
  }

  nonisolated var isConfigured: Bool {
    return !apiKey.isEmpty
  }

  /// Updates or overrides the API key in Apple Keychain
  nonisolated func setCustomAPIKey(_ key: String) {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    setKeychainAPIKey(trimmed)
  }

  // MARK: - Secret De-obfuscation

  nonisolated private func deobfuscateKey() -> String {
    guard !salt.isEmpty else { return "" }
    var result = [UInt8]()
    result.reserveCapacity(scrambledKey.count)
    for (i, byte) in scrambledKey.enumerated() {
      let s = salt[i % salt.count]
      result.append(byte ^ s)
    }
    return String(decoding: result, as: UTF8.self)
  }

  // MARK: - Apple Keychain Operations

  nonisolated private func getKeychainAPIKey() -> String? {
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
          let key = String(data: data, encoding: .utf8) else {
      return nil
    }
    return key
  }

  nonisolated private func setKeychainAPIKey(_ key: String) {
    guard let data = key.data(using: .utf8) else { return }

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount
    ]

    let attributesToUpdate: [String: Any] = [
      kSecValueData as String: data
    ]

    let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
    if updateStatus == errSecItemNotFound {
      var newItem = query
      newItem[kSecValueData as String] = data
      #if os(iOS)
      newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      #endif
      SecItemAdd(newItem as CFDictionary, nil)
    }
  }
}
