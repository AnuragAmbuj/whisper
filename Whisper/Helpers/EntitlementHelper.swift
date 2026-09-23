//
//  EntitlementHelper.swift
//  Whisper
//
//  Created by Anurag Ambuj on 23/09/26.
//

import Foundation
#if os(macOS)
import Security
#endif

/// Safe, runtime capability detector to prevent crashes/faults
/// when running without provisioned iCloud / KVS entitlements.
public enum EntitlementHelper {
    
    /// Returns true if the app is currently running in a unit/UI test environment.
    public static var isTesting: Bool {
        NSClassFromString("XCTestCase") != nil ||
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
    
    /// Checks whether the running binary possesses the `com.apple.developer.ubiquity-kvstore-identifier` entitlement.
    public static let canUseKeyValueStore: Bool = {
        if isTesting { return false }
        #if targetEnvironment(simulator)
        return false
        #elseif os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        var error: Unmanaged<CFError>?
        let val = SecTaskCopyValueForEntitlement(task, "com.apple.developer.ubiquity-kvstore-identifier" as CFString, &error)
        return val != nil
        #else
        return checkMobileProvision(key: "com.apple.developer.ubiquity-kvstore-identifier")
        #endif
    }()
    
    /// Checks whether the running binary possesses the CloudKit entitlement in `com.apple.developer.icloud-services`.
    public static let canUseCloudKit: Bool = {
        if isTesting { return false }
        #if targetEnvironment(simulator)
        return false
        #elseif os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        var error: Unmanaged<CFError>?
        guard let val = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, &error) else { return false }
        if let array = val as? [String] {
            return array.contains("CloudKit") || array.contains("CloudKit-Anonymous")
        }
        return false
        #else
        return checkMobileProvisionArray(key: "com.apple.developer.icloud-services", contains: "CloudKit")
        #endif
    }()
    
    /// Checks whether the running binary possesses the CloudDocuments entitlement.
    public static let canUseCloudDocuments: Bool = {
        if isTesting { return false }
        #if targetEnvironment(simulator)
        return false
        #elseif os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        var error: Unmanaged<CFError>?
        guard let val = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, &error) else { return false }
        if let array = val as? [String] {
            return array.contains("CloudDocuments")
        }
        return false
        #else
        return checkMobileProvisionArray(key: "com.apple.developer.icloud-services", contains: "CloudDocuments")
        #endif
    }()
    
    public static var isEntitledForiCloud: Bool {
        canUseCloudKit || canUseKeyValueStore || canUseCloudDocuments
    }
    
    #if !os(macOS) && !targetEnvironment(simulator)
    private static func loadMobileProvisionEntitlements() -> [String: Any]? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let string = String(data: data, encoding: .isoLatin1) else { return nil }
        
        guard let start = string.range(of: "<!DOCTYPE plist"),
              let end = string.range(of: "</plist>", range: start.lowerBound..<string.endIndex) else { return nil }
        
        let plistString = String(string[start.lowerBound..<end.upperBound])
        guard let plistData = plistString.data(using: .utf8),
              let dict = (try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)) as? [String: Any],
              let entitlements = dict["Entitlements"] as? [String: Any] else { return nil }
        return entitlements
    }
    
    private static func checkMobileProvision(key: String) -> Bool {
        guard let entitlements = loadMobileProvisionEntitlements() else { return false }
        return entitlements[key] != nil
    }
    
    private static func checkMobileProvisionArray(key: String, contains target: String) -> Bool {
        guard let entitlements = loadMobileProvisionEntitlements(),
              let items = entitlements[key] as? [String] else { return false }
        return items.contains(target)
    }
    #endif
}
