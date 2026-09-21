//
//  ContentView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 28/12/25.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: Tab = .library
    @State private var hoveredTab: Tab? = nil
    
    // Shared incoming file handling
    @State private var incomingBook: Book? = nil
    @State private var isProcessingSharedImport = false
    @State private var importErrorMessage: String? = nil
    @State private var showImportError = false
    @State private var isDropTargeted = false
    
    enum Tab: String, CaseIterable, Identifiable {
        case library
        case store
        case `import`
        
        var id: String { rawValue }
        
        var title: String {
            switch self {
            case .library: return "Library"
            case .store: return "Bookstore"
            case .import: return "Import"
            }
        }
        
        var iconName: String {
            switch self {
            case .library: return "books.vertical.fill"
            case .store: return "bag.fill"
            case .import: return "square.and.arrow.down.fill"
            }
        }
    }
    
    var body: some View {
        ZStack {
            #if os(iOS)
            TabView(selection: $selectedTab) {
                LibraryView()
                    .tabItem {
                        Label(Tab.library.title, systemImage: Tab.library.iconName)
                    }
                    .tag(Tab.library)
                
                StoreView()
                    .tabItem {
                        Label(Tab.store.title, systemImage: Tab.store.iconName)
                    }
                    .tag(Tab.store)
                
                ImportView()
                    .tabItem {
                        Label(Tab.import.title, systemImage: Tab.import.iconName)
                    }
                    .tag(Tab.import)
            }
            .tint(.primary)
            #elseif os(macOS)
            VStack(spacing: 0) {
                macOSNavigationBar
                
                Divider()
                    .background(DS.Colors.divider)
                
                Group {
                    switch selectedTab {
                    case .library:
                        LibraryView()
                    case .store:
                        StoreView()
                    case .import:
                        ImportView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(DS.Colors.background)
            #else
            LibraryView()
            #endif
            
            // Drag and Drop Visual Highlight (High Contrast Apple Style)
            if isDropTargeted {
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(Color.primary, lineWidth: 2)
                    .background(Color.primary.opacity(0.04))
                    .overlay(
                        VStack(spacing: 12) {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.primary)
                            Text("Drop Comic or Book to Import")
                                .font(.headline.bold())
                                .foregroundColor(.primary)
                            Text("Supports CBZ, CBR, EPUB, PDF, TXT")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(24)
                        .background(DS.Colors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                                .stroke(DS.Colors.border, lineWidth: 1)
                        )
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            
            // Processing Overlay for Shared / Dropped Files (Flat Material)
            if isProcessingSharedImport {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    VStack(spacing: DS.Spacing.md) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.primary)
                        Text("Importing file...")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    .padding(DS.Spacing.xl)
                    .background(DS.Colors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                            .stroke(DS.Colors.border, lineWidth: 1)
                    )
                }
            }
        }
        .onAppear {
            if let pending = FileOpenManager.shared.pendingURL {
                FileOpenManager.shared.pendingURL = nil
                handleIncomingURL(pending)
            }
        }
        .onReceive(FileOpenManager.shared.$pendingURL) { url in
            if let url = url {
                FileOpenManager.shared.pendingURL = nil
                handleIncomingURL(url)
            }
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("whisperOpenFile"))) { notification in
            if let url = notification.object as? URL {
                handleIncomingURL(url)
            }
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .whisperOpenBookById)) { notification in
            if let id = notification.object as? UUID,
               let book = BookService.shared.fetchBook(id: id) {
                self.incomingBook = book
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .whisperResumeReading)) { _ in
            if let book = BookService.shared.fetchLatestBook() {
                self.incomingBook = book
            }
        }
        .onDrop(of: [UTType.fileURL, UTType.item], isTargeted: $isDropTargeted) { providers in
            handleDroppedProviders(providers)
        }
        .sheet(item: $incomingBook) { book in
            #if os(iOS)
            NavigationStack {
                ReaderView(viewModel: ReaderViewModel(book: book))
            }
            #else
            ReaderView(viewModel: ReaderViewModel(book: book))
                .frame(minWidth: 800, minHeight: 600)
            #endif
        }
        .alert("Import Notice", isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "Could not import the selected file.")
        }
    }
    
    // MARK: - Incoming URL & Drag-and-Drop Handlers
    
    private func handleIncomingURL(_ url: URL) {
        isProcessingSharedImport = true
        
        Task {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            
            if let book = await ImportService.shared.importFile(at: url) {
                await MainActor.run {
                    modelContext.insert(book)
                    try? modelContext.save()
                    BookService.shared.indexBookInSpotlight(book)
                    isProcessingSharedImport = false
                    incomingBook = book
                }
            } else {
                await MainActor.run {
                    isProcessingSharedImport = false
                    importErrorMessage = "Could not parse or open the file. Ensure it is a valid CBZ, CBR, EPUB, PDF, or TXT file."
                    showImportError = true
                }
            }
        }
    }
    
    private func handleDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                DispatchQueue.main.async {
                    self.handleIncomingURL(url)
                }
            }
            return true
        }
        return false
    }
    
    // MARK: - macOS Flat Segmented Header Bar
    #if os(macOS)
    private func tabForegroundColor(for tab: Tab) -> Color {
        if selectedTab == tab { return .white }
        if hoveredTab == tab { return .primary }
        return .secondary
    }

    private func tabBackgroundColor(for tab: Tab) -> Color {
        if selectedTab == tab { return Color.accentColor }
        if hoveredTab == tab { return DS.Colors.hover }
        return Color.clear
    }

    private var macOSNavigationBar: some View {
        HStack(spacing: DS.Spacing.md) {
            Text("Whisper")
                .font(.headline.weight(.semibold))
                .foregroundColor(.primary)
            
            Spacer()
            
            HStack(spacing: DS.Spacing.xxs) {
                ForEach(Tab.allCases) { tab in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 12, weight: .medium))
                            Text(tab.title)
                                .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundColor(tabForegroundColor(for: tab))
                        .background(tabBackgroundColor(for: tab))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovered in
                        hoveredTab = isHovered ? tab : nil
                    }
                }
            }
            .padding(3)
            .background(DS.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Colors.border, lineWidth: 1)
            )
            
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Colors.cardBackground)
    }
    #endif
}
