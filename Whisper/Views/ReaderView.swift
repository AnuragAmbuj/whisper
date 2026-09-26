//
//  ReaderView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import PDFKit
import SwiftData
import SwiftUI

struct ReaderView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @State var viewModel: ReaderViewModel
  @State private var showControls = true
  @State private var showSettings = false
  @State private var showBookmarks = false
  @State private var pageIndex: Int = 0
  @State private var totalPages: Int = 1
  @State private var showSmartFind = false
  @State private var showAIInsights = false

  init(book: Book) {
    _viewModel = State(wrappedValue: ReaderViewModel(book: book))
  }

  init(viewModel: ReaderViewModel) {
    _viewModel = State(wrappedValue: viewModel)
  }

  var body: some View {
    ZStack {
      // Content layer based on format
      switch viewModel.book.format ?? .text {
      case .text:
        TextReaderView(
          book: viewModel.book,
          theme: viewModel.theme,
          fontSize: viewModel.fontSize,
          lineHeight: viewModel.lineHeight,
          showControls: $showControls
        )

      case .pdf:
        if let url = viewModel.book.resolvedURL {
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
          .simultaneousGesture(
            TapGesture().onEnded {
              withAnimation(.easeInOut(duration: 0.22)) {
                showControls.toggle()
              }
            }
          )
        } else {
          ContentUnavailableView("PDF Not Found", systemImage: "doc.text")
        }

      case .comic:
        ComicReaderView(
          bookDir: viewModel.book.bookDir,
          mockImages: viewModel.book.sampleImages,
          currentPage: $pageIndex,
          totalPages: $totalPages,
          showControls: $showControls
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
            showControls: $showControls,
            onProgressChanged: { progress in
              viewModel.updateProgress(progress)
            }
          )
        } else {
          ContentUnavailableView("EPUB Not Found", systemImage: "book.closed")
        }
      }

      // Top Navigation HUD (iOS)
      #if os(iOS)
      if showControls {
        VStack(spacing: 0) {
          HStack(alignment: .center) {
            // Dismiss / Close Button
            Button(action: { dismiss() }) {
              Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(viewModel.theme.textColor)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(
                  Circle()
                    .stroke(viewModel.theme.textColor.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Spacer()

            // Header metadata (Title & Format)
            VStack(spacing: 2) {
              Text(viewModel.book.title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(viewModel.theme.textColor)
                .lineLimit(1)

              if !viewModel.book.author.isEmpty {
                Text(viewModel.book.author)
                  .font(.caption2)
                  .foregroundColor(viewModel.theme.textColor.opacity(0.65))
                  .lineLimit(1)
              }
            }
            .frame(maxWidth: 240)

            Spacer()

            // Trailing Actions
            HStack(spacing: DS.Spacing.sm) {
              Button(action: { showAIInsights = true }) {
                Image(systemName: "sparkles")
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundColor(viewModel.theme.textColor)
                  .frame(width: 38, height: 38)
                  .background(.ultraThinMaterial)
                  .clipShape(Circle())
                  .overlay(
                    Circle()
                      .stroke(viewModel.theme.textColor.opacity(0.12), lineWidth: 1)
                  )
              }
              .buttonStyle(.plain)
              .help("Apple Intelligence Reading Insights")

              Button(action: { showSmartFind = true }) {
                Image(systemName: "sparkle.magnifyingglass")
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundColor(viewModel.theme.textColor)
                  .frame(width: 38, height: 38)
                  .background(.ultraThinMaterial)
                  .clipShape(Circle())
                  .overlay(
                    Circle()
                      .stroke(viewModel.theme.textColor.opacity(0.12), lineWidth: 1)
                  )
              }
              .buttonStyle(.plain)

              Button(action: { showBookmarks = true }) {
                Image(systemName: "list.bullet")
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundColor(viewModel.theme.textColor)
                  .frame(width: 38, height: 38)
                  .background(.ultraThinMaterial)
                  .clipShape(Circle())
                  .overlay(
                    Circle()
                      .stroke(viewModel.theme.textColor.opacity(0.12), lineWidth: 1)
                  )
              }
              .buttonStyle(.plain)

              Button(action: { viewModel.toggleBookmark() }) {
                Image(systemName: viewModel.isBookmarked ? "bookmark.fill" : "bookmark")
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundColor(viewModel.isBookmarked ? .yellow : viewModel.theme.textColor)
                  .frame(width: 38, height: 38)
                  .background(.ultraThinMaterial)
                  .clipShape(Circle())
                  .overlay(
                    Circle()
                      .stroke(viewModel.theme.textColor.opacity(0.12), lineWidth: 1)
                  )
              }
              .buttonStyle(.plain)

              Button(action: {
                withAnimation(.easeInOut(duration: DS.Animation.normal)) { showSettings.toggle() }
              }) {
                Image(systemName: "textformat.size")
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundColor(viewModel.theme.textColor)
                  .frame(width: 38, height: 38)
                  .background(.ultraThinMaterial)
                  .clipShape(Circle())
                  .overlay(
                    Circle()
                      .stroke(viewModel.theme.textColor.opacity(0.12), lineWidth: 1)
                  )
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.horizontal, DS.Spacing.lg)
          .padding(.vertical, DS.Spacing.xs)
          .background(
            LinearGradient(
              colors: [
                viewModel.theme.backgroundColor.opacity(0.92),
                viewModel.theme.backgroundColor.opacity(0.0)
              ],
              startPoint: .top,
              endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
          )

          Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(10)
      }
      #endif

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
        .zIndex(20)
      }
    }
    #if os(iOS)
      .navigationBarBackButtonHidden(true)
      .toolbar(.hidden, for: .navigationBar)
    #else
      .toolbar {
        ToolbarItem(placement: .navigation) {
          HStack(spacing: DS.Spacing.lg) {
            Button(action: { dismiss() }) {
              Image(systemName: "xmark.circle")
            }
            Divider()
            Button(action: { showAIInsights = true }) {
              Image(systemName: "sparkles")
            }
            .help("Apple Intelligence Reading Insights")

            Button(action: { showSmartFind = true }) {
              Image(systemName: "sparkle.magnifyingglass")
            }
            .help("Smart Find (TypeSafe AI)")

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
    .sheet(isPresented: $showSmartFind) {
      SmartFindSheet(book: viewModel.book, theme: viewModel.theme) { lineIndex, excerpt in
        handleSmartFindNavigation(lineIndex: lineIndex, excerpt: excerpt)
      }
    }
    .sheet(isPresented: $showAIInsights) {
      AIReaderInsightsSheet(book: viewModel.book)
    }
    .onReceive(NotificationCenter.default.publisher(for: .whisperToggleBookmark)) { _ in
      viewModel.toggleBookmark()
    }
    .onDisappear {
      try? modelContext.save()
    }
  }

  private func handleSmartFindNavigation(lineIndex: Int, excerpt: String) {
    // 1. Check if excerpt indicates a specific page (PDF / Comic format)
    let pattern = #"(?:\[Page|Page)\s+(\d+)"#
    if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
       let match = regex.firstMatch(in: excerpt, range: NSRange(excerpt.startIndex..., in: excerpt)),
       let range = Range(match.range(at: 1), in: excerpt),
       let pageNum = Int(excerpt[range]) {
      let targetIndex = max(0, pageNum - 1)
      pageIndex = targetIndex
      viewModel.updateLocation(targetIndex)
      return
    }

    // 2. Default line or location navigation
    pageIndex = lineIndex
    viewModel.updateLocation(lineIndex)
  }
}

#Preview {
  let mockBook = Book(
    title: "1984", author: "George Orwell", coverImageName: "",
    content: "It was a bright cold day...")
  let vm = ReaderViewModel(book: mockBook)
  ReaderView(viewModel: vm)
}
