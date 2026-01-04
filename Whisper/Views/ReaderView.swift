//
//  ReaderView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftData
import SwiftUI

struct ReaderView: View {
  @State var viewModel: ReaderViewModel
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) var modelContext

  @State private var showSettings = false
  @State private var showBookmarks = false

  @State private var pageIndex: Int = 0  // For PDF/Comic

  var body: some View {
    ZStack {
      // Background
      LiquidBackground()
        .opacity(DS.BackgroundOpacity.overlay)
        .ignoresSafeArea()

      // Content Area
      switch viewModel.book.format {
      case .text:
        TextReaderView(
          book: viewModel.book, viewModel: viewModel, theme: viewModel.theme,
          fontSize: viewModel.fontSize, lineHeight: viewModel.lineHeight)

      case .pdf:
        if let url = viewModel.book.url {
          ZStack {
            PDFKitView(url: url, currentPageIndex: $pageIndex)
          }
          .onAppear {
            // Restore page
            pageIndex = Int(viewModel.book.progress)
          }
          .onChange(of: pageIndex) { _, newValue in
            viewModel.updateProgress(Double(newValue))
          }
        } else {
          ContentUnavailableView("PDF Not Found", systemImage: "doc.text")
        }

      case .comic:
        ComicReaderView(
          bookDir: viewModel.book.url,
          mockImages: viewModel.book.sampleImages,
          currentPage: $pageIndex
        )
        .onAppear {
          pageIndex = Int(viewModel.book.progress)
        }
        .onChange(of: pageIndex) { _, newValue in
          viewModel.updateProgress(Double(newValue))
        }

      case .epub:
        if let url = viewModel.book.url {
          // url points to the unzipped directory
          EpubReaderView(bookDir: url)
        } else {
          ContentUnavailableView("EPUB Not Found", systemImage: "book.closed")
        }
      }

      if showSettings {
        Color.black.opacity(0.2)
          .ignoresSafeArea()
          .onTapGesture {
            withAnimation(.easeInOut(duration: DS.Animation.normal)) { showSettings = false }
          }

        VStack {
          Spacer()
          SettingsSheet(viewModel: viewModel)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.bottom, DS.Spacing.xl)
        }
        .zIndex(2)
      }
    }
    #if os(iOS)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: { dismiss() }) {
            Image(systemName: "xmark.circle.fill")
            .symbolRenderingMode(.hierarchical)
            .foregroundColor(.white)
            .font(.title2)
          }
        }

        ToolbarItem(placement: .topBarTrailing) {
          HStack(spacing: DS.Spacing.lg) {
            Button(action: { showBookmarks = true }) {
              Image(systemName: "list.bullet")
              .foregroundColor(.white)
            }
            Button(action: { viewModel.toggleBookmark() }) {
              Image(systemName: viewModel.isBookmarked ? "bookmark.fill" : "bookmark")
              .foregroundColor(.white)
            }
            Button(action: { withAnimation(.easeInOut(duration: DS.Animation.normal)) { showSettings.toggle() } }) {
              Image(systemName: "textformat.size")
              .foregroundColor(.white)
            }
          }
        }
      }
    #else
      .toolbar {
        ToolbarItem(placement: .navigation) {
          HStack(spacing: DS.Spacing.lg) {
            Button(action: { dismiss() }) {
              Image(systemName: "xmark.circle")
            }
            Divider()
            Button(action: { showBookmarks = true }) {
              Image(systemName: "list.bullet")
            }
            Button(action: { viewModel.toggleBookmark() }) {
              Image(systemName: viewModel.isBookmarked ? "bookmark.fill" : "bookmark")
            }
            Button(action: { withAnimation(.easeInOut(duration: DS.Animation.normal)) { showSettings.toggle() } }) {
              Image(systemName: "textformat.size")
            }
          }
        }
      }
    #endif

    .sheet(isPresented: $showBookmarks) {
      BookmarksList(book: viewModel.book)
    }
    .onDisappear {
      // Save progress logic
      try? modelContext.save()
    }
  }

}

#Preview {
  let mockBook = Book(
    title: "1984", author: "George Orwell", coverImageName: "",
    content: "It was a bright cold day...")
  let vm = ReaderViewModel(book: mockBook)
  ReaderView(viewModel: vm)
}
