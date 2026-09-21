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
  @State private var totalPages: Int = 1

  var body: some View {
    ZStack {
      // Clean reading surface matching selected eye-comfort theme (Apple HIG compliant)
      viewModel.theme.backgroundColor
        .ignoresSafeArea()

      // Content Area
      switch viewModel.book.format ?? .text {
      case .text:
        TextReaderView(
          book: viewModel.book, theme: viewModel.theme,
          fontSize: viewModel.fontSize, lineHeight: viewModel.lineHeight)

      case .pdf:
        if let url = viewModel.book.url {
          ZStack {
            PDFKitView(url: url, currentPageIndex: $pageIndex, totalPages: $totalPages, theme: viewModel.theme)
          }
          .onAppear {
            pageIndex = viewModel.currentLocation
          }
          .onChange(of: pageIndex) { _, newValue in
            viewModel.updateLocation(newValue)
            let prog = totalPages > 1 ? Double(newValue) / Double(totalPages - 1) : 1.0
            viewModel.updateProgress(prog)
          }
        } else {
          ContentUnavailableView("PDF Not Found", systemImage: "doc.text")
        }

      case .comic:
        ComicReaderView(
          bookDir: viewModel.book.bookDir,
          mockImages: viewModel.book.sampleImages,
          currentPage: $pageIndex,
          totalPages: $totalPages
        )
        .onAppear {
          pageIndex = viewModel.currentLocation
        }
        .onChange(of: pageIndex) { _, newValue in
          viewModel.updateLocation(newValue)
          let prog = totalPages > 1 ? Double(newValue) / Double(totalPages - 1) : 1.0
          viewModel.updateProgress(prog)
        }

      case .epub:
        if let bookDir = viewModel.book.bookDir {
          EpubReaderView(
            bookDir: bookDir,
            theme: viewModel.theme,
            fontSize: viewModel.fontSize,
            bookTitle: viewModel.book.title,
            onProgressChanged: { progress in
              viewModel.updateProgress(progress)
            }
          )
        } else {
          ContentUnavailableView("EPUB Not Found", systemImage: "book.closed")
        }
      }

      if showSettings {
        Color.black.opacity(0.4)
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
      .navigationBarBackButtonHidden(true)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: { dismiss() }) {
            Image(systemName: "xmark.circle.fill")
            .symbolRenderingMode(.hierarchical)
            .foregroundColor(viewModel.theme.textColor.opacity(0.85))
            .font(.title2)
          }
        }

        ToolbarItem(placement: .topBarTrailing) {
          HStack(spacing: DS.Spacing.lg) {
            Button(action: { showBookmarks = true }) {
              Image(systemName: "list.bullet")
              .foregroundColor(viewModel.theme.textColor.opacity(0.85))
            }
            Button(action: { viewModel.toggleBookmark() }) {
              Image(systemName: viewModel.isBookmarked ? "bookmark.fill" : "bookmark")
              .foregroundColor(viewModel.isBookmarked ? .yellow : viewModel.theme.textColor.opacity(0.85))
            }
            Button(action: {
              withAnimation(.easeInOut(duration: DS.Animation.normal)) { showSettings.toggle() }
            }) {
              Image(systemName: "textformat.size")
              .foregroundColor(viewModel.theme.textColor.opacity(0.85))
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
              .foregroundColor(viewModel.isBookmarked ? .yellow : .white)
            }
            Button(action: {
              withAnimation(.easeInOut(duration: DS.Animation.normal)) { showSettings.toggle() }
            }) {
              Image(systemName: "textformat.size")
            }
          }
        }
      }
    #endif

    .sheet(isPresented: $showBookmarks) {
      BookmarksList(book: viewModel.book) { bookmark in
        pageIndex = bookmark.pageOrLocation
        viewModel.updateLocation(bookmark.pageOrLocation)
      }
    }
    .onDisappear {
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
