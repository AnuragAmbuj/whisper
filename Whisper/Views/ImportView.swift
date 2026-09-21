//
//  ImportView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 18/09/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportView: View {
    @State private var isImporting = false
    @State private var isProcessing = false
    @State private var importMessage: String?
    @State private var showAlert = false
    @State private var isTargetedForDrop = false
    
    @ObservedObject private var cloudSync = CloudSyncService.shared
    
    @Environment(\.modelContext) private var modelContext
    @Query private var allBooks: [Book]
    
    var body: some View {
        #if os(iOS)
        NavigationStack {
            importScrollContent
                .navigationTitle("Import")
                .background(systemBackground.ignoresSafeArea())
        }
        #else
        importScrollContent
            .background(systemBackground)
        #endif
    }
    
    private var importScrollContent: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.xxl) {
                // Quick Import Action Card with Mac Drag & Drop support
                importHeroCard
                    #if os(macOS)
                    .padding(.top, DS.Spacing.xl)
                    #else
                    .padding(.top, DS.Spacing.xs)
                    #endif
                
                // iCloud Sync Overview
                iCloudSyncSection
                
                // Library Stats Grid
                libraryStatsSection
                
                // Supported Formats Overview
                supportedFormatsSection
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.xxl)
            .frame(maxWidth: DS.Layout.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: ImportService.supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImport(result: result)
        }
        .alert("Import Status", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage ?? "Operation completed.")
        }
    }
    
    private var systemBackground: Color {
        DS.Colors.groupedBackground
    }
    
    private var cardBackground: Color {
        DS.Colors.cardBackground
    }
    
    private var subcardBackground: Color {
        #if os(iOS)
        return Color(uiColor: .tertiarySystemGroupedBackground)
        #elseif os(macOS)
        return Color(nsColor: .underPageBackgroundColor)
        #else
        return Color.gray.opacity(0.15)
        #endif
    }
    
    // MARK: - Import Hero Card (Flat, High Contrast Apple Style)
    private var importHeroCard: some View {
        VStack(spacing: DS.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(DS.Colors.unselectedFill)
                    .frame(width: 72, height: 72)
                
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.primary)
            }
            
            VStack(spacing: 6) {
                Text("Import Books & Documents")
                    .font(.title3.bold())
                    .foregroundColor(.primary)
                
                Text(dropPromptText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.md)
            }
            
            Button(action: { isImporting = true }) {
                HStack(spacing: 8) {
                    if isProcessing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(DS.Colors.onSelection)
                    } else {
                        Image(systemName: "plus.circle.fill")
                    }
                    Text(isProcessing ? "Importing..." : "Choose File to Import")
                }
                .font(.headline.weight(.semibold))
                .foregroundColor(DS.Colors.onSelection)
                .frame(maxWidth: 320)
                .padding(.vertical, 12)
                .background(Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
        }
        .padding(DS.Spacing.xxl)
        .frame(maxWidth: .infinity)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(isTargetedForDrop ? Color.primary : DS.Colors.border, lineWidth: isTargetedForDrop ? 2 : 1)
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
            handleDrop(providers: providers)
        }
    }
    
    private var dropPromptText: String {
        #if os(macOS)
        return "Drag and drop EPUB, PDF, CBZ/CBR comics, or TXT files here, or choose from your Mac."
        #else
        return "Import EPUB, PDF, CBZ/CBR comics, and text files directly from the Files app or iCloud Drive."
        #endif
    }
    
    // MARK: - iCloud Sync Section
    private var iCloudSyncSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("iCloud Sync")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, 4)
            
            VStack(spacing: DS.Spacing.md) {
                HStack(spacing: DS.Spacing.md) {
                    Image(systemName: cloudSync.status.iconName)
                        .font(.title2)
                        .foregroundColor(cloudSync.status == .available ? .green : .secondary)
                        .frame(width: 40, height: 40)
                        .background(DS.Colors.unselectedFill)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cloudSync.status.localizedDescription)
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                        
                        if let lastSync = cloudSync.lastSyncDate {
                            Text("Last synced \(lastSync.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Automatic SwiftData & CloudKit Sync")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        Task {
                            await cloudSync.triggerSync()
                        }
                    }) {
                        if cloudSync.isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Sync Now")
                                .font(.caption.bold())
                                .foregroundColor(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(DS.Colors.unselectedFill)
                                .clipShape(Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(cloudSync.isSyncing)
                }
                
                if !cloudSync.cloudBookFiles.isEmpty {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Books found in iCloud Drive:")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        
                        ForEach(cloudSync.cloudBookFiles, id: \.self) { fileURL in
                            HStack {
                                Image(systemName: "doc.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(fileURL.lastPathComponent)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                Button("Import") {
                                    processImportURL(fileURL)
                                }
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.primary)
                                .foregroundColor(DS.Colors.onSelection)
                                .clipShape(Capsule())
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(DS.Spacing.lg)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Colors.border, lineWidth: 1)
            )
        }
    }
    
    // MARK: - Library Stats Section (Consistent, Flat)
    private var libraryStatsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Library Overview")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, 4)
            
            HStack(spacing: DS.Spacing.md) {
                statBox(
                    title: "Total Books",
                    value: "\(allBooks.count)",
                    icon: "books.vertical.fill",
                    color: .primary
                )
                statBox(
                    title: "In Progress",
                    value: "\(allBooks.filter { $0.progress > 0 && $0.progress < 1.0 }.count)",
                    icon: "book.fill",
                    color: .primary
                )
                statBox(
                    title: "Finished",
                    value: "\(allBooks.filter { $0.progress >= 1.0 }.count)",
                    icon: "checkmark.circle.fill",
                    color: .secondary
                )
            }
        }
    }
    
    private func statBox(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
            
            Text(value)
                .font(.title2.bold())
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.lg)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Colors.border, lineWidth: 1)
        )
    }
    
    // MARK: - Supported Formats Section (Consistent)
    private var supportedFormatsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Supported Formats")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, 4)
            
            VStack(spacing: DS.Spacing.sm) {
                formatRow(
                    title: "EPUB (.epub)",
                    subtitle: "Reflowable text, chapters, custom typography, and themes",
                    icon: "book.closed.fill"
                )
                formatRow(
                    title: "PDF Documents (.pdf)",
                    subtitle: "High precision layout, page navigation, and eye-comfort tinting",
                    icon: "doc.text.fill"
                )
                formatRow(
                    title: "Comics (.cbz, .cbr)",
                    subtitle: "Manga & graphic novels, ultra-crisp full-width reading",
                    icon: "photo.stack.fill"
                )
                formatRow(
                    title: "Plain Text (.txt)",
                    subtitle: "Lightweight reading with zero distractions and full font controls",
                    icon: "text.quote"
                )
            }
        }
    }
    
    private func formatRow(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.primary)
                .frame(width: 40, height: 40)
                .background(DS.Colors.unselectedFill)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundColor(DS.Colors.accent)
        }
        .padding(DS.Spacing.md)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Colors.border, lineWidth: 1)
        )
    }
    
    // MARK: - Drop and File Handling
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            
            Task { @MainActor in
                self.processImportURL(url)
            }
        }
        return true
    }
    
    private func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let selectedURL = urls.first else { return }
            processImportURL(selectedURL)
        case .failure(let error):
            importMessage = error.localizedDescription
            showAlert = true
        }
    }
    
    private func processImportURL(_ fileURL: URL) {
        isProcessing = true
        
        Task {
            let accessing = fileURL.startAccessingSecurityScopedResource()
            defer {
                if accessing { fileURL.stopAccessingSecurityScopedResource() }
            }
            
            if let newBook = await ImportService.shared.importFile(at: fileURL) {
                await MainActor.run {
                    modelContext.insert(newBook)
                    try? modelContext.save()
                    isProcessing = false
                    importMessage = "Successfully added \"\(newBook.title)\" to your library."
                    showAlert = true
                }
            } else {
                await MainActor.run {
                    isProcessing = false
                    importMessage = "Could not import \"\(fileURL.lastPathComponent)\". Make sure it is a valid format."
                    showAlert = true
                }
            }
        }
    }
}

#Preview {
    ImportView()
}
