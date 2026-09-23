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

extension Notification.Name {
    static let whisperLibraryDidSync = Notification.Name("whisperLibraryDidSync")
}

@MainActor
final class CloudSyncService: ObservableObject {
    static let shared = CloudSyncService()
    
    nonisolated static let containerIdentifier = "iCloud.club.ironlattice.Whisper"
    
    nonisolated static var resolvedUbiquityDocumentsURL: URL? {
        if let specific = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) {
            return specific.appendingPathComponent("Documents", isDirectory: true)
        }
        if let fallback = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            return fallback.appendingPathComponent("Documents", isDirectory: true)
        }
        return nil
    }
    
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
                return "iCloud Not Entitled on Device"
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
    
    private var modelContainer: ModelContainer?
    private var kvStoreObserver: Any?
    private var testStore: [String: Any] = [:]
    
    private lazy var container: CKContainer? = {
        guard !EntitlementHelper.isTesting, EntitlementHelper.canUseCloudKit else { return nil }
        return CKContainer(identifier: Self.containerIdentifier)
    }()
    
    private init() {
        setupAccountObserver()
        setupKVStoreObserver()
        Task {
            await checkAccountStatus()
            resolveUbiquityContainer()
        }
    }
    
    func startSyncEngine(container: ModelContainer) {
        self.modelContainer = container
        Task {
            await checkAccountStatus()
            resolveUbiquityContainer()
        }
    }
    
    // MARK: - iCloud Account Monitoring
    
    private func setupAccountObserver() {
        guard !EntitlementHelper.isTesting, EntitlementHelper.canUseCloudKit else { return }
        NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.checkAccountStatus()
                self?.resolveUbiquityContainer()
            }
        }
    }
    
    /// Queries the current iCloud account status
    func checkAccountStatus() async {
        guard EntitlementHelper.canUseCloudKit, let container = container else {
            if EntitlementHelper.canUseCloudDocuments {
                self.status = .available
            } else if EntitlementHelper.isTesting {
                self.status = .available
            } else {
                self.status = .restricted
            }
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
    
    // MARK: - Ubiquity Container Management
    
    /// Resolves the ubiquity container Documents/Books path for cross-device file synchronization
    func resolveUbiquityContainer() {
        guard !EntitlementHelper.isTesting else { return }
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let docsURL = Self.resolvedUbiquityDocumentsURL else {
                return
            }
            
            let booksURL = docsURL.appendingPathComponent("Books", isDirectory: true)
            if !FileManager.default.fileExists(atPath: booksURL.path) {
                try? FileManager.default.createDirectory(at: booksURL, withIntermediateDirectories: true)
            }
            
            DispatchQueue.main.async {
                self?.iCloudDriveURL = docsURL
                self?.refreshCloudFiles()
                self?.syncLocalBooksToCloud()
                self?.importDiscoveredCloudBooks()
            }
        }
    }
    
    /// Scans the iCloud Drive folder for supported book files
    func refreshCloudFiles() {
        guard let driveURL = iCloudDriveURL else { return }
        let booksURL = driveURL.appendingPathComponent("Books", isDirectory: true)
        let searchURL = FileManager.default.fileExists(atPath: booksURL.path) ? booksURL : driveURL
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let supportedExtensions = Set(["epub", "pdf", "cbz", "cbr", "txt", "md"])
            guard let enumerator = FileManager.default.enumerator(
                at: searchURL,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .ubiquitousItemDownloadingStatusKey],
                options: [.skipsHiddenFiles]
            ) else { return }
            
            var found: [URL] = []
            while let fileURL = enumerator.nextObject() as? URL {
                if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                    found.append(fileURL)
                    
                    // Auto-trigger background download if item is a dataless cloud fault
                    if FileManager.default.isUbiquitousItem(at: fileURL) {
                        try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
                    }
                }
            }
            
            let sorted = found.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            DispatchQueue.main.async {
                self?.cloudBookFiles = sorted
            }
        }
    }
    
    // MARK: - Bidirectional Sync: Upload Local Books to iCloud
    
    /// Uploads/copies a local book file to the iCloud Drive container for cross-device sync
    func uploadBookToCloud(fileURL: URL) {
        guard fileURL.isFileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        
        DispatchQueue.global(qos: .utility).async {
            guard let docs = Self.resolvedUbiquityDocumentsURL else { return }
            let booksDir = docs.appendingPathComponent("Books", isDirectory: true)
            try? FileManager.default.createDirectory(at: booksDir, withIntermediateDirectories: true)
            
            let destinationURL = booksDir.appendingPathComponent(fileURL.lastPathComponent)
            
            if !FileManager.default.fileExists(atPath: destinationURL.path) {
                do {
                    try FileManager.default.copyItem(at: fileURL, to: destinationURL)
                    print("CloudSyncService: Uploaded '\(fileURL.lastPathComponent)' to iCloud Drive.")
                    DispatchQueue.main.async {
                        CloudSyncService.shared.refreshCloudFiles()
                    }
                } catch {
                    print("CloudSyncService: Failed to upload '\(fileURL.lastPathComponent)' to iCloud: \(error)")
                }
            }
        }
    }
    
    /// Scans local Documents/Books and uploads any books that are not yet in iCloud Drive
    func syncLocalBooksToCloud() {
        guard let driveURL = iCloudDriveURL else { return }
        let cloudBooksURL = driveURL.appendingPathComponent("Books", isDirectory: true)
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let localDocs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let localBooksURL = localDocs.appendingPathComponent("Books", isDirectory: true)
            guard FileManager.default.fileExists(atPath: localBooksURL.path) else { return }
            
            let supportedExtensions = Set(["epub", "pdf", "cbz", "cbr", "txt", "md"])
            guard let enumerator = FileManager.default.enumerator(
                at: localBooksURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return }
            
            while let localURL = enumerator.nextObject() as? URL {
                let ext = localURL.pathExtension.lowercased()
                if supportedExtensions.contains(ext) {
                    let cloudDest = cloudBooksURL.appendingPathComponent(localURL.lastPathComponent)
                    if !FileManager.default.fileExists(atPath: cloudDest.path) {
                        try? FileManager.default.copyItem(at: localURL, to: cloudDest)
                        print("CloudSyncService: Mirrored local book '\(localURL.lastPathComponent)' to iCloud Drive.")
                    }
                }
            }
            
            DispatchQueue.main.async {
                self?.refreshCloudFiles()
            }
        }
    }
    
    // MARK: - Bidirectional Sync: Ingest Cloud Books on this Device (e.g. iPad)
    
    /// Automatically imports any book files found in iCloud Drive that are missing from the local library
    func importDiscoveredCloudBooks() {
        guard let driveURL = iCloudDriveURL else { return }
        let cloudBooksURL = driveURL.appendingPathComponent("Books", isDirectory: true)
        let searchURL = FileManager.default.fileExists(atPath: cloudBooksURL.path) ? cloudBooksURL : driveURL
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let supportedExtensions = Set(["epub", "pdf", "cbz", "cbr", "txt", "md"])
            guard let enumerator = FileManager.default.enumerator(
                at: searchURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return }
            
            var filesToImport: [URL] = []
            while let fileURL = enumerator.nextObject() as? URL {
                if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                    filesToImport.append(fileURL)
                }
            }
            
            guard !filesToImport.isEmpty else { return }
            
            Task { @MainActor in
                guard let context = self?.modelContainer?.mainContext else { return }
                let descriptor = FetchDescriptor<Book>()
                let existingBooks = (try? context.fetch(descriptor)) ?? []
                let existingFilenames = Set(existingBooks.compactMap { $0.url?.lastPathComponent })
                let existingTitles = Set(existingBooks.map { $0.title.lowercased() })
                
                var importedAny = false
                for cloudURL in filesToImport {
                    let fileName = cloudURL.lastPathComponent
                    let titleGuess = cloudURL.deletingPathExtension().lastPathComponent.lowercased()
                    
                    if !existingFilenames.contains(fileName) && !existingTitles.contains(titleGuess) {
                        if let newBook = await ImportService.shared.importFile(at: cloudURL) {
                            context.insert(newBook)
                            importedAny = true
                            print("CloudSyncService: Auto-imported cloud book '\(newBook.title)' onto this device.")
                        }
                    }
                }
                
                if importedAny {
                    try? context.save()
                    NotificationCenter.default.post(name: .whisperLibraryDidSync, object: nil)
                }
            }
        }
    }
    
    // MARK: - Reading Progress Sync via NSUbiquitousKeyValueStore
    
    private func setupKVStoreObserver() {
        guard !EntitlementHelper.isTesting, EntitlementHelper.canUseKeyValueStore else { return }
        kvStoreObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyCloudReadingStates()
            }
        }
        NSUbiquitousKeyValueStore.default.synchronize()
    }
    
    /// Persists a book's reading progress and timestamp to iCloud Key-Value store
    func saveReadingProgress(for book: Book) {
        let idStr = book.id.uuidString
        let dateValue = book.lastReadDate.timeIntervalSince1970
        testStore["prog_\(idStr)"] = book.progress
        testStore["date_\(idStr)"] = dateValue
        
        guard EntitlementHelper.canUseKeyValueStore else { return }
        let store = NSUbiquitousKeyValueStore.default
        store.set(book.progress, forKey: "prog_\(idStr)")
        store.set(dateValue, forKey: "date_\(idStr)")
        store.synchronize()
    }
    
    /// Persists bookmarks count/locations for a book to iCloud
    func saveBookmarks(for book: Book) {
        let idStr = book.id.uuidString
        let locations = book.safeBookmarks.map { $0.pageOrLocation }
        testStore["bm_\(idStr)"] = locations
        
        guard EntitlementHelper.canUseKeyValueStore else { return }
        let store = NSUbiquitousKeyValueStore.default
        store.set(locations, forKey: "bm_\(idStr)")
        store.synchronize()
    }
    
    /// Updates local reading progress if a more recent state exists in iCloud
    func applyLatestCloudReadingProgress(for book: Book) {
        let idStr = book.id.uuidString
        var cloudDateStamp: Double = 0.0
        var cloudProgress: Double = 0.0
        
        if EntitlementHelper.canUseKeyValueStore {
            let store = NSUbiquitousKeyValueStore.default
            cloudDateStamp = store.double(forKey: "date_\(idStr)")
            cloudProgress = store.double(forKey: "prog_\(idStr)")
        } else if let testDate = testStore["date_\(idStr)"] as? Double,
                  let testProg = testStore["prog_\(idStr)"] as? Double {
            cloudDateStamp = testDate
            cloudProgress = testProg
        }
        
        guard cloudDateStamp > 0 else { return }
        
        let cloudDate = Date(timeIntervalSince1970: cloudDateStamp)
        if cloudDate > book.lastReadDate {
            book.progress = min(max(cloudProgress, 0.0), 1.0)
            book.lastReadDate = cloudDate
        }
    }
    
    /// Applies cloud reading progress to all books in the local library
    private func applyCloudReadingStates() {
        guard let context = modelContainer?.mainContext else { return }
        let descriptor = FetchDescriptor<Book>()
        guard let books = try? context.fetch(descriptor) else { return }
        
        var didUpdate = false
        for book in books {
            let prevProgress = book.progress
            applyLatestCloudReadingProgress(for: book)
            if book.progress != prevProgress {
                didUpdate = true
            }
        }
        if didUpdate {
            try? context.save()
            NotificationCenter.default.post(name: .whisperLibraryDidSync, object: nil)
        }
    }
    
    // MARK: - On-Demand Manual Refresh
    
    /// Triggers a full on-demand sync refresh
    func triggerSync() async {
        isSyncing = true
        await checkAccountStatus()
        resolveUbiquityContainer()
        syncLocalBooksToCloud()
        importDiscoveredCloudBooks()
        applyCloudReadingStates()
        
        try? await Task.sleep(nanoseconds: 800_000_000)
        self.lastSyncDate = Date()
        isSyncing = false
    }
}
