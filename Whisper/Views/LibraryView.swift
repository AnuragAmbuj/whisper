//
//  LibraryView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
  @State private var viewModel = LibraryViewModel()
  @State private var isImporting = false
  @State private var isProcessingImport = false
  @State private var showImportError = false
  @State private var importErrorMessage: String?
  @State private var hoveredCategory: String? = nil
  @State private var showSyncSheet = false
  @ObservedObject private var cloudSync = CloudSyncService.shared
  @Query var books: [Book]
  @Environment(\.modelContext) private var modelContext

  let columns = [
    GridItem(
      .adaptive(minimum: DS.Layout.gridItemMin, maximum: DS.Layout.gridItemMax),
      spacing: DS.Layout.gridSpacing)
  ]

  var filteredBooks: [Book] {
    viewModel.filterBooks(books)
  }

  var body: some View {
    NavigationStack {
      ZStack {
        // Native Apple system background
        #if os(iOS)
        systemBackground
          .ignoresSafeArea()
        #else
        systemBackground
        #endif

        ScrollView {
          VStack(spacing: DS.Spacing.lg) {
            categoryChipsView
              #if os(macOS)
              .padding(.top, DS.Spacing.md)
              #else
              .padding(.top, DS.Spacing.xs)
              #endif

            booksGridView
              .padding(.horizontal)
              .padding(.bottom, DS.Spacing.xxl)
          }
          .frame(maxWidth: DS.Layout.maxSplitWidth)
          .frame(maxWidth: .infinity)
        }
        .refreshable {
          await cloudSync.triggerSync()
        }

        if isProcessingImport {
          importingOverlay
        }
      }
      .navigationTitle("Library")
      .searchable(text: $viewModel.searchText, prompt: "Search title or author")
      .onAppear {
        loadMockData()
        Task {
          await cloudSync.triggerSync()
        }
      }
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          HStack(spacing: DS.Spacing.sm) {
            // Cloud Sync Action Menu & Status (iCloud / Google Drive)
            Menu {
              Button(action: {
                Task {
                  await cloudSync.triggerSync()
                }
              }) {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
              }
              
              Button(action: {
                showSyncSheet = true
              }) {
                Label("Sync Settings (\(cloudSync.activeProvider.title))...", systemImage: "gearshape")
              }
            } label: {
              if cloudSync.isSyncing {
                ProgressView()
                  .controlSize(.small)
              } else {
                Image(systemName: cloudSync.statusIcon)
                  .foregroundColor(cloudSync.activeProvider == .disabled ? .secondary : DS.Colors.accent)
              }
            }
            .help(cloudSync.statusText)

            Menu {
              Button(action: resetToSampleLibrary) {
                Label("Reload Sample Library", systemImage: "arrow.counterclockwise")
              }
            } label: {
              Image(systemName: "arrow.clockwise")
            }

            Button(action: { isImporting = true }) {
              Image(systemName: "plus")
            }
            .disabled(isProcessingImport)
          }
        }
      }
      .fileImporter(
        isPresented: $isImporting,
        allowedContentTypes: ImportService.supportedTypes,
        allowsMultipleSelection: false
      ) { result in
        handleImport(result: result)
      }
      .sheet(isPresented: $showSyncSheet) {
        CloudSyncSheet()
      }
      .alert("Import Notice", isPresented: $showImportError) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(importErrorMessage ?? "An error occurred during import.")
      }
      .overlay {
        if books.isEmpty && !isProcessingImport {
          emptyStateView
        }
      }
    }
  }

  private var systemBackground: Color {
    #if os(iOS)
    return Color(uiColor: .systemBackground)
    #elseif os(macOS)
    return Color(nsColor: .windowBackgroundColor)
    #else
    return Color.black
    #endif
  }

  private var categoryChipsView: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: DS.Spacing.sm) {
        ForEach(viewModel.categories, id: \.self) { category in
          let isSelected = viewModel.selectedCategory == category
          let isHovered = hoveredCategory == category && !isSelected
          Button(action: {
            withAnimation(.easeInOut(duration: DS.Animation.fast)) {
              viewModel.selectedCategory = category
            }
          }) {
            Text(category)
              .font(.subheadline.weight(isSelected ? .semibold : .regular))
              .foregroundColor(
                isSelected
                  ? DS.Colors.onSelection
                  : (isHovered ? Color.primary : Color.secondary)
              )
              .padding(.horizontal, DS.Spacing.md)
              .padding(.vertical, DS.Spacing.xs)
              .background(
                Capsule()
                  .fill(
                    isSelected
                      ? DS.Colors.selection
                      : (isHovered ? DS.Colors.hover : DS.Colors.unselectedFill)
                  )
              )
          }
          .buttonStyle(.plain)
          .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
              hoveredCategory = hovering ? category : nil
            }
          }
        }
      }
      .padding(.horizontal)
    }
  }

  private var booksGridView: some View {
    LazyVGrid(columns: columns, spacing: DS.Spacing.xxl) {
      ForEach(filteredBooks) { book in
        NavigationLink(destination: BookDetailView(book: book)) {
          BookCoverView(book: book)
        }
        .contextMenu {
          Button(role: .destructive) {
            deleteBook(book)
          } label: {
            Label("Delete", systemImage: "trash")
          }
        }
      }
    }
  }

  private var importingOverlay: some View {
    ZStack {
      Color.black.opacity(0.3)
        .ignoresSafeArea()

      VStack(spacing: 16) {
        WhisperMarkLoaderView(size: 64, style: .wave)
        Text("Importing...")
          .font(.headline)
          .foregroundColor(.primary)
      }
      .padding(32)
      .background(DS.Colors.cardBackground)
      .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
          .stroke(DS.Colors.border, lineWidth: 1)
      )
    }
  }

  private var emptyStateView: some View {
    ContentUnavailableView {
      Label("Library Empty", systemImage: "books.vertical")
    } description: {
      Text("Tap the refresh button to load sample books or the plus button to import your own.")
    }
  }

  private func handleImport(result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
      guard let selectedURL = urls.first else { return }

      isProcessingImport = true

      Task {
        let accessing = selectedURL.startAccessingSecurityScopedResource()
        defer {
          if accessing { selectedURL.stopAccessingSecurityScopedResource() }
        }

        if let newBook = await ImportService.shared.importFile(at: selectedURL) {
          await MainActor.run {
            modelContext.insert(newBook)
            try? modelContext.save()
            isProcessingImport = false
          }
        } else {
          await MainActor.run {
            isProcessingImport = false
            importErrorMessage = "Could not import the selected file. Please ensure it is a valid EPUB, PDF, CBZ/CBR comic, or TXT file."
            showImportError = true
          }
        }
      }

    case .failure(let error):
      importErrorMessage = error.localizedDescription
      showImportError = true
    }
  }

  func loadMockData() {
    BookService.shared.checkForSeeding(context: modelContext)
  }

  func resetToSampleLibrary() {
    for book in books {
      deleteBook(book)
    }
    BookService.shared.seedBooks(context: modelContext)
  }

  func deleteBook(_ book: Book) {
    book.cleanupFiles()
    modelContext.delete(book)
    try? modelContext.save()
  }
}
