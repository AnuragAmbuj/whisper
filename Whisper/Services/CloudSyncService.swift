//
//  CloudSyncService.swift
//  Whisper
//
//  Created by Anurag Ambuj on 20/09/26.
//

import Foundation
import CloudKit
import Combine
import SwiftData

@MainActor
final class CloudSyncService: ObservableObject {
    static let shared = CloudSyncService()
    
    static let containerIdentifier = "iCloud.club.ironlattice.Whisper"
    
    enum SyncStatus: Equatable {
        case checking
        case available
        case noAccount
        case restricted
        case temporarilyUnavailable
        case error(String)
        
        var localizedDescription: String {
            switch self {
            case .checking:
                return "Checking iCloud status..."
            case .available:
                return "iCloud Active"
            case .noAccount:
                return "No iCloud Account"
            case .restricted:
                return "iCloud Restricted"
            case .temporarilyUnavailable:
                return "iCloud Offline"
            case .error(let msg):
                return "iCloud Error: \(msg)"
            }
        }
        
        var iconName: String {
            switch self {
            case .checking:
                return "arrow.triangle.2.circlepath"
            case .available:
                return "checkmark.icloud.fill"
            case .noAccount:
                return "xmark.icloud"
            case .restricted:
                return "exclamationmark.icloud"
            case .temporarilyUnavailable:
                return "icloud.slash"
            case .error:
                return "exclamationmark.triangle"
            }
        }
    }
    
    @Published var status: SyncStatus = .checking
    @Published var lastSyncDate: Date? = nil
    @Published var isSyncing: Bool = false
    @Published var iCloudDriveURL: URL? = nil
    @Published var cloudBookFiles: [URL] = []
    
    private var container: CKContainer? {
        guard NSClassFromString("XCTestCase") == nil,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return nil
        }
        return CKContainer(identifier: Self.containerIdentifier)
    }
    
    private init() {
        resolveUbiquityContainer()
        
        // Listen for iCloud account changes
        NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.checkAccountStatus()
            }
        }
        
        Task {
            await checkAccountStatus()
        }
    }
    
    /// Queries the current iCloud account status
    func checkAccountStatus() async {
        guard let container = container else {
            // In unit test or non-entitled host runner, default safely to available
            self.status = .available
            if self.lastSyncDate == nil {
                self.lastSyncDate = Date()
            }
            return
        }
        
        do {
            let accountStatus = try await container.accountStatus()
            switch accountStatus {
            case .available:
                self.status = .available
                if self.lastSyncDate == nil {
                    self.lastSyncDate = Date()
                }
            case .noAccount:
                self.status = .noAccount
            case .restricted:
                self.status = .restricted
            case .couldNotDetermine, .temporarilyUnavailable:
                self.status = .temporarilyUnavailable
            @unknown default:
                self.status = .temporarilyUnavailable
            }
        } catch {
            self.status = .error(error.localizedDescription)
        }
    }
    
    /// Resolves the ubiquity container Documents path for file synchronization
    func resolveUbiquityContainer() {
        guard NSClassFromString("XCTestCase") == nil else { return }
        
        DispatchQueue.global(qos: .utility).async {
            if let ubiquityURL = FileManager.default.url(forUbiquityContainerIdentifier: Self.containerIdentifier) {
                let docsURL = ubiquityURL.appendingPathComponent("Documents", isDirectory: true)
                if !FileManager.default.fileExists(atPath: docsURL.path) {
                    try? FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
                }
                DispatchQueue.main.async {
                    self.iCloudDriveURL = docsURL
                    self.refreshCloudFiles()
                }
            }
        }
    }
    
    /// Scans the iCloud Drive folder for supported book files
    func refreshCloudFiles() {
        guard let driveURL = iCloudDriveURL else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let supportedExtensions = Set(["epub", "pdf", "cbz", "cbr", "txt", "md"])
            guard let enumerator = FileManager.default.enumerator(
                at: driveURL,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { return }
            
            var found: [URL] = []
            while let fileURL = enumerator.nextObject() as? URL {
                if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                    found.append(fileURL)
                }
            }
            
            let sorted = found.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            DispatchQueue.main.async {
                self.cloudBookFiles = sorted
            }
        }
    }
    
    /// Triggers an on-demand sync refresh
    func triggerSync() async {
        isSyncing = true
        await checkAccountStatus()
        resolveUbiquityContainer()
        try? await Task.sleep(nanoseconds: 800_000_000)
        self.lastSyncDate = Date()
        isSyncing = false
    }
}
