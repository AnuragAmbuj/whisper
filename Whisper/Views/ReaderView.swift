//
//  ReaderView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftData
import SwiftUI

struct ReaderView: View {
  @Bindable var viewModel: ReaderViewModel
  @State private var showSettings = false
  @State private var showBookmarks = false
  @State private var showSmartFind = false
  @State private var showAIInsights = false
  @State private var showControls = true
  @State private var pageIndex: Int = 0
  @State private var totalPages: Int = 0
  @State private var targetChapterIndex: Int? = nil
  @State private var targetSearchSnippet: String? = nil
  @State private var targetTextLocation: Int? = nil
  @State private var currentChapterPath: String? = nil
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  var body: some View {
    ZStack {
      // Dynamic Eye Comfort Theme Background
      viewModel.theme.backgroundColor
        .ignoresSafeArea()

      // Format-Specific Reader View
      switch viewModel.book.format ?? .text {
      case .text:
        TextReaderView(
          book: viewModel.book,
          theme: viewModel.theme,
          fontSize: viewModel.fontSize,
          lineHeight: viewModel.lineHeight,
          targetLocation: $targetTextLocation,
          targetSearchSnippet: $targetSearchSnippet,
          showControls: $showControls
        )

      case .comic:
        if let bookDir = viewModel.book.bookDir {
          ComicReaderView(
            bookDir: bookDir,
            currentPage: $pageIndex,
            totalPages: $totalPages,
            showControls: $showControls
          )
          .onChange(of: pageIndex) { _, newIndex in
            viewModel.updateLocation(newIndex)
            let prog = totalPages > 1 ? Double(newIndex) / Double(totalPages - 1) : 1.0
            viewModel.updateProgress(prog)
          }
        } else {
          ContentUnavailableView("Comic Not Found", systemImage: "photo.stack")
        }

      case .pdf:
        if let pdfURL = viewModel.book.resolvedURL {
          PDFKitView(
            url: pdfURL,
            currentPageIndex: $pageIndex,
            totalPages: $totalPages,
            theme: viewModel.theme,
            targetSearchSnippet: $targetSearchSnippet
          )
          .ignoresSafeArea()
          .onTapGesture {
            withAnimation(.easeInOut(duration: DS.Animation.fast)) {
              showControls.toggle()
            }
          }
          .onChange(of: pageIndex) { _, newValue in
            viewModel.updateLocation(newValue)
            let prog = totalPages > 1 ? Double(newValue) / Double(totalPages - 1) : 1.0
            viewModel.updateProgress(prog)
          }
        } else {
          ContentUnavailableView("PDF Not Found", systemImage: "doc.text")
        }

      case .epub:
        if let bookDir = viewModel.book.bookDir {
          EpubReaderView(
            bookDir: bookDir,
            theme: viewModel.theme,
            fontSize: viewModel.fontSize,
            bookTitle: viewModel.book.title,
            showControls: $showControls,
            targetChapterIndex: $targetChapterIndex,
            targetSearchSnippet: $targetSearchSnippet,
            onProgressChanged: { progress in
              viewModel.updateProgress(progress)
            }
          )
        } else {
          ContentUnavailableView("EPUB Not Found", systemImage: "book.closed")
        }

      case .audiobook:
        AudiobookPlayerView(
          book: viewModel.book,
          viewModel: viewModel,
          showControls: $showControls
        )
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
                .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Reader")
            .accessibilityHint("Return to library")

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
            .accessibilityElement(children: .combine)

            Spacer()

            // Action Buttons
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
                  .frame(minWidth: 44, minHeight: 44)
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Apple Intelligence Insights")

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
                  .frame(minWidth: 44, minHeight: 44)
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Smart Find")

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
                  .frame(minWidth: 44, minHeight: 44)
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Chapters and Bookmarks")

              Button(action: { viewModel.toggleBookmark() }) {
                Image(systemName: viewModel.isBookmarked ? "bookmark.fill" : "bookmark")
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundColor(viewModel.isBookmarked ? DS.Colors.accent : viewModel.theme.textColor)
                  .frame(width: 38, height: 38)
                  .background(.ultraThinMaterial)
                  .clipShape(Circle())
                  .overlay(
                    Circle()
                      .stroke(viewModel.theme.textColor.opacity(0.12), lineWidth: 1)
                  )
                  .frame(minWidth: 44, minHeight: 44)
              }
              .buttonStyle(.plain)
              .accessibilityLabel(viewModel.isBookmarked ? "Remove Bookmark" : "Add Bookmark")

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
                  .frame(minWidth: 44, minHeight: 44)
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Reading Appearance and Display Settings")
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
      .toolbar(.hidden, for: .tabBar)
    #else
      .toolbar {
        ToolbarItem(placement: .navigation) {
          HStack(spacing: DS.Spacing.lg) {
            Button(action: { dismiss() }) {
              Image(systemName: "xmark.circle")
            }
            .accessibilityLabel("Close Reader")
            .keyboardShortcut(.escape, modifiers: [])
            .help("Close Reader (Esc)")

            Divider()

            Button(action: { showAIInsights = true }) {
              Image(systemName: "sparkles")
            }
            .accessibilityLabel("Apple Intelligence Reading Insights")
            .keyboardShortcut("i", modifiers: .command)
            .help("Apple Intelligence Reading Insights (⌘I)")

            Button(action: { showSmartFind = true }) {
              Image(systemName: "sparkle.magnifyingglass")
            }
            .accessibilityLabel("Smart Find")
            .keyboardShortcut("f", modifiers: .command)
            .help("Smart Find (⌘F)")

            Button(action: { showBookmarks = true }) {
              Image(systemName: "list.bullet")
            }
            .accessibilityLabel("Chapters and Bookmarks")
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .help("Chapters and Bookmarks (⇧⌘B)")

            Button(action: { viewModel.toggleBookmark() }) {
              Image(systemName: viewModel.isBookmarked ? "bookmark.fill" : "bookmark")
                .foregroundColor(viewModel.isBookmarked ? .yellow : .white)
            }
            .accessibilityLabel(viewModel.isBookmarked ? "Remove Bookmark" : "Add Bookmark")
            .keyboardShortcut("d", modifiers: .command)
            .help(viewModel.isBookmarked ? "Remove Bookmark (⌘D)" : "Bookmark Page (⌘D)")

            if (viewModel.book.format ?? .text) != .audiobook {
              Button(action: {
                withAnimation(.easeInOut(duration: DS.Animation.normal)) { showSettings.toggle() }
              }) {
                Image(systemName: "textformat.size")
              }
              .accessibilityLabel("Reading Appearance and Display Settings")
              .keyboardShortcut(",", modifiers: .command)
              .help("Reading Settings (⌘,)")
            }
          }
        }
      }
    #endif
    .sheet(isPresented: $showBookmarks) {
      BookmarksList(
        book: viewModel.book,
        currentChapterPath: currentChapterPath,
        currentLocation: (viewModel.book.format ?? .text) == .epub ? (targetChapterIndex ?? 0) : pageIndex,
        onSelectChapter: { chapter in
          handleChapterNavigation(chapter)
        },
        onSelectBookmark: { bookmark in
          handleBookmarkNavigation(bookmark)
        },
        onFindCharacter: { characterName in
          showSmartFind = true
        }
      )
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
      if viewModel.book.format == .audiobook {
        AudiobookPlayerService.shared.pause()
      }
      try? modelContext.save()
    }
  }

  private func handleChapterNavigation(_ chapter: Chapter) {
    let loc = chapter.pageOrLocation
    currentChapterPath = chapter.path
    viewModel.updateLocation(loc)

    switch viewModel.book.format ?? .text {
    case .epub:
      targetChapterIndex = loc
    case .pdf, .comic:
      pageIndex = loc
    case .text:
      targetTextLocation = loc
      pageIndex = loc
    case .audiobook:
      AudiobookPlayerService.shared.seek(to: Double(loc))
    }
  }

  private func handleBookmarkNavigation(_ bookmark: Bookmark) {
    pageIndex = bookmark.pageOrLocation
    viewModel.updateLocation(bookmark.pageOrLocation)

    switch viewModel.book.format ?? .text {
    case .epub:
      targetChapterIndex = bookmark.pageOrLocation
    case .pdf, .comic:
      pageIndex = bookmark.pageOrLocation
    case .text:
      targetTextLocation = bookmark.pageOrLocation
    case .audiobook:
      AudiobookPlayerService.shared.seek(to: Double(bookmark.pageOrLocation))
    }
  }

  private func handleSmartFindNavigation(lineIndex: Int, excerpt: String) {
    targetSearchSnippet = excerpt

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

    // 2. Check if audiobook timestamp (e.g. 03:45 or 12:30)
    if viewModel.book.format == .audiobook {
      let timePattern = #"(\d{1,2}):(\d{2})(?::(\d{2}))?"#
      if let regex = try? NSRegularExpression(pattern: timePattern, options: []),
         let match = regex.firstMatch(in: excerpt, range: NSRange(excerpt.startIndex..., in: excerpt)),
         let r1 = Range(match.range(at: 1), in: excerpt),
         let r2 = Range(match.range(at: 2), in: excerpt),
         let m = Int(excerpt[r1]),
         let s = Int(excerpt[r2]) {
        let total = Double(m * 60 + s)
        AudiobookPlayerService.shared.seek(to: total)
        viewModel.updateLocation(Int(total))
        return
      }
    }

    // 3. For Text Reader:
    if viewModel.book.format == .text {
      targetTextLocation = lineIndex
      pageIndex = lineIndex
      viewModel.updateLocation(lineIndex)
      return
    }

    // 4. Default line or location navigation
    pageIndex = lineIndex
    viewModel.updateLocation(lineIndex)
  }
}
