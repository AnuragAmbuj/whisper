//
//  WhisperApp.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI
import SwiftData
import Combine

extension Notification.Name {
    static let whisperOpenFile = Notification.Name("whisperOpenFile")
    static let whisperOpenBookById = Notification.Name("whisperOpenBookById")
    static let whisperResumeReading = Notification.Name("whisperResumeReading")
}

final class FileOpenManager: ObservableObject {
    static let shared = FileOpenManager()
    @Published var pendingURL: URL? = nil
    
    func openURL(_ url: URL) {
        DispatchQueue.main.async {
            self.pendingURL = url
        }
    }
}

#if os(macOS)
import AppKit

final class WhisperAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        FileOpenManager.shared.openURL(url)
        NotificationCenter.default.post(name: .whisperOpenFile, object: url)
        return true
    }
}

final class WhisperWindowDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        true
    }
}

struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                configure(window)
            }
        }
    }
}
#endif

@main
struct WhisperApp: App {
    @State private var showSplash = true
    #if os(macOS)
    @NSApplicationDelegateAdaptor(WhisperAppDelegate.self) var appDelegate
    @State private var windowDelegate = WhisperWindowDelegate()
    #endif
    
    init() {
        #if os(macOS)
        // Ensure application icon is loaded and displayed immediately in Dock & app switcher
        if let icon = NSImage(named: "AppIcon") ?? Bundle.main.image(forResource: "AppIcon") {
            NSApplication.shared.applicationIconImage = icon
        }
        #endif
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Book.self,
            Bookmark.self,
        ])
        
        // Only enable CloudKit database synchronization if the binary possesses the CloudKit entitlement
        let cloudKitDB: ModelConfiguration.CloudKitDatabase = EntitlementHelper.canUseCloudKit ? .automatic : .none
        let cloudConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: cloudKitDB)

        do {
            return try ModelContainer(for: schema, configurations: [cloudConfig])
        } catch {
            print("Notice: SwiftData CloudKit initialization: \(error.localizedDescription). Falling back to standard persistent store...")
            let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            
            do {
                return try ModelContainer(for: schema, configurations: [localConfig])
            } catch {
                print("Failed to initialize persistent ModelContainer: \(error). Attempting recovery...")
                if let storeURL = localConfig.url as URL? {
                    try? FileManager.default.removeItem(at: storeURL)
                    let shmURL = storeURL.deletingPathExtension().appendingPathExtension("store-shm")
                    let walURL = storeURL.deletingPathExtension().appendingPathExtension("store-wal")
                    try? FileManager.default.removeItem(at: shmURL)
                    try? FileManager.default.removeItem(at: walURL)
                }
                if let recoveredContainer = try? ModelContainer(for: schema, configurations: [localConfig]) {
                    return recoveredContainer
                }
                let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return (try? ModelContainer(for: schema, configurations: [fallbackConfig])) ?? {
                    fatalError("Could not create ModelContainer: \(error)")
                }()
            }
        }
    }()

    var body: some Scene {
        WindowGroup("Whisper") {
            ZStack {
                ContentView()
                    .opacity(showSplash ? 0 : 1)
                
                if showSplash {
                    SplashScreenView()
                        .transition(.opacity)
                }
            }
            #if os(macOS)
            .background(
                WindowAccessor { window in
                    window.delegate = windowDelegate
                    window.title = "Whisper"
                    window.titleVisibility = .visible
                    window.toolbar?.isVisible = true
                    window.collectionBehavior.insert(.fullScreenPrimary)
                    window.collectionBehavior.insert(.fullScreenAllowsTiling)
                }
            )
            .windowToolbarFullScreenVisibility(.onHover)
            .onReceive(NotificationCenter.default.publisher(for: .whisperOpenFile)) { _ in
                showSplash = false
            }
            #endif
            .onReceive(FileOpenManager.shared.$pendingURL) { url in
                if url != nil {
                    showSplash = false
                }
            }
            .onOpenURL { url in
                showSplash = false
                FileOpenManager.shared.openURL(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: .whisperOpenBookById)) { _ in
                showSplash = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .whisperResumeReading)) { _ in
                showSplash = false
            }
            .onAppear {
                BookService.shared.setModelContainer(sharedModelContainer)
                CloudSyncService.shared.startSyncEngine(container: sharedModelContainer)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showSplash = false
                    }
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
