//
//  WhisperApp.swift
//  Whisper
//
//  Created by Anurag Ambuj on 28/12/25.
//

import SwiftUI
import SwiftData

@main
struct WhisperApp: App {
    @State private var showSplash = true
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Book.self,
            Bookmark.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ZStack {
                LibraryView()
                    .opacity(showSplash ? 0 : 1)
                
                if showSplash {
                    SplashScreenView()
                        .transition(.opacity)
                }
            }
            .onAppear {
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
