//
//  WhisperApp.swift
//  Whisper
//
//  Created by Anurag Ambuj on 28/12/25.
//

import SwiftUI
import SwiftData
import Combine

final class FileOpenManager: ObservableObject {
    static let shared = FileOpenManager()
    @Published var pendingURL: URL? = nil
    
    func openURL(_ url: URL) {
        DispatchQueue.main.async {
            self.pendingURL = url
        }
    }
}

extension Notification.Name {
    static let whisperOpenFile = Notification.Name("whisperOpenFile")
    static let whisperOpenBookById = Notification.Name("whisperOpenBookById")
    static let whisperResumeReading = Notification.Name("whisperResumeReading")
}

#if os(macOS)
import AppKit

final class WhisperAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            let url = URL(fileURLWithPath: filename)
            FileOpenManager.shared.openURL(url)
            NotificationCenter.default.post(name: .whisperOpenFile, object: url)
        }
        sender.reply(toOpenOrPrint: .success)
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            FileOpenManager.shared.openURL(url)
            NotificationCenter.default.post(name: .whisperOpenFile, object: url)
        }
    }
}

final class WhisperWindowDelegate: NSObject, NSWindowDelegate {
    func window(
        _ window: NSWindow,
        willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions = []
    ) -> NSApplication.PresentationOptions {
        // Auto-hides menu bar and titlebar in fullscreen; reveals both on hovering near top
        return [.autoHideToolbar, .autoHideMenuBar, .fullScreen]
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
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("Failed to initialize persistent ModelContainer: \(error). Attempting recovery...")
            if let storeURL = modelConfiguration.url as URL? {
                try? FileManager.default.removeItem(at: storeURL)
                let shmURL = storeURL.deletingPathExtension().appendingPathExtension("store-shm")
                let walURL = storeURL.deletingPathExtension().appendingPathExtension("store-wal")
                try? FileManager.default.removeItem(at: shmURL)
                try? FileManager.default.removeItem(at: walURL)
            }
            if let recoveredContainer = try? ModelContainer(for: schema, configurations: [modelConfiguration]) {
                return recoveredContainer
            }
            let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return (try? ModelContainer(for: schema, configurations: [fallbackConfig])) ?? {
                fatalError("Could not create ModelContainer: \(error)")
            }()
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
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("whisperOpenFile"))) { _ in
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
