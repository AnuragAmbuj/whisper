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
  @Query var books: [Book]
  @Environment(\.modelContext) private var modelContext

  let columns = [
    GridItem(.adaptive(minimum: DS.Layout.gridItemMin, maximum: DS.Layout.gridItemMax), spacing: DS.Layout.gridSpacing)
  ]

  var filteredBooks: [Book] {
    viewModel.filterBooks(books)
  }

  init() {
    // Customize Navigation Bar appearance for glass effect (iOS only)
    #if os(iOS)
      if #available(iOS 15.0, *) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
      }
    #endif
  }

  var body: some View {
    NavigationStack {
      ZStack {
        LiquidBackground()

        ScrollView {
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
          .padding()
        }
      }
      .navigationTitle("Library")
      .searchable(text: $viewModel.searchText, prompt: "Search title or author")
      .onAppear {
        loadMockData()
      }
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          HStack {
            Button(action: loadMockData) {
              Image(systemName: "arrow.clockwise")
                .iconButtonStyle()
            }

            Button(action: { isImporting = true }) {
              Image(systemName: "plus")
                .iconButtonStyle()
            }
          }
        }
      }
      .fileImporter(
        isPresented: $isImporting,
        allowedContentTypes: ImportService.supportedTypes,
        allowsMultipleSelection: false
      ) { result in
        switch result {
        case .success(let urls):
          guard let selectedURL = urls.first else { return }
          // Access security scope
          if selectedURL.startAccessingSecurityScopedResource() {
            defer { selectedURL.stopAccessingSecurityScopedResource() }
            if let newBook = ImportService.shared.importFile(at: selectedURL) {
              modelContext.insert(newBook)
              try? modelContext.save()
            }
          }
        case .failure(let error):
          print("Import failed: \(error.localizedDescription)")
        }
      }
      .overlay {
        if books.isEmpty {
          if #available(iOS 17.0, macOS 14.0, *) {
            ContentUnavailableView {
              Label("Library Empty", systemImage: "books.vertical")
                .foregroundColor(.white)
            } description: {
              Text("Tap the refresh button to load sample books.")
                .foregroundColor(.white.opacity(0.8))
            }
          } else {
            // Fallback for older versions
            VStack(spacing: DS.Spacing.lg) {
              Image(systemName: "books.vertical")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(DS.Opacity.tertiary))
              Text("Library Empty")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
              Text("Tap the refresh button to load sample books.")
                .font(.body)
                .foregroundColor(.white.opacity(DS.Opacity.secondary))
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.xxxl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
      }
    }
    .preferredColorScheme(.dark)  // Force dark mode feel for the glass effect
  }

  func loadMockData() {
    BookService.shared.checkForSeeding(context: modelContext)
  }

  func deleteBook(_ book: Book) {
    modelContext.delete(book)
    // SwiftData autosaves or we can explicit save
    try? modelContext.save()
  }
}

#Preview {
  LibraryView()
    .modelContainer(for: Book.self, inMemory: true)
}
