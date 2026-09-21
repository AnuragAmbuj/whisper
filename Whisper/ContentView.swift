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
                    selectedTab = .library
                    incomingBook = book
                    isProcessingSharedImport = false
                }
            } else {
                await MainActor.run {
                    isProcessingSharedImport = false
                    importErrorMessage = "Could not import \"\(url.lastPathComponent)\". Please ensure it is a valid EPUB, PDF, CBZ/CBR comic, or TXT file."
                    showImportError = true
                }
            }
        }
    }
    
    private func handleDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let resolvedURL: URL?
                if let url = item as? URL {
                    resolvedURL = url
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    resolvedURL = url
                } else {
                    resolvedURL = nil
                }
                
                if let fileURL = resolvedURL {
                    Task { @MainActor in
                        handleIncomingURL(fileURL)
                    }
                }
            }
            return true
        }
        return false
    }
    
    #if os(macOS)
    private var macOSNavigationBar: some View {
        HStack(spacing: DS.Spacing.md) {
            // App Branding (High Contrast Apple Style)
            HStack(spacing: 8) {
                Image(systemName: "book.pages.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Text("Whisper")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.primary)
            }
            .padding(.leading, DS.Spacing.md)
            
            Spacer()
            
            // Clean segmented navigation bar with high-contrast Apple Books style selection & neutral hover
            HStack(spacing: 2) {
                ForEach(Tab.allCases) { tab in
                    let isSelected = selectedTab == tab
                    let isHovered = hoveredTab == tab && !isSelected
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: DS.Animation.fast)) {
                            selectedTab = tab
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                            Text(tab.title)
                                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                .fill(
                                    isSelected
                                        ? DS.Colors.selection
                                        : (isHovered ? DS.Colors.hover : Color.clear)
                                )
                        )
                        .foregroundColor(
                            isSelected
                                ? DS.Colors.onSelection
                                : (isHovered ? Color.primary : Color.secondary)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.12)) {
                            hoveredTab = hovering ? tab : nil
                        }
                    }
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(DS.Colors.unselectedFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Colors.border, lineWidth: 1)
            )
            
            Spacer()
            
            Color.clear
                .frame(width: 100, height: 20)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, 8)
        .background(DS.Colors.background)
    }
    #endif
}

#Preview {
    ContentView()
}
