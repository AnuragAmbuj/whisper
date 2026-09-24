//
//  BookDetailView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI

struct BookDetailView: View {
  let book: Book
  @Environment(\.horizontalSizeClass) var hSizeClass
  @State private var navigateToReader: Bool = false
  @ObservedObject private var cloudSync = CloudSyncService.shared

  var body: some View {
    #if os(macOS)
      macOSContent
        .navigationDestination(isPresented: $navigateToReader) {
          ReaderView(viewModel: ReaderViewModel(book: book))
        }
    #else
      GeometryReader { geometry in
        let isLandscapeMode = geometry.size.width > geometry.size.height
        let showSplitLayout = hSizeClass == .regular && isLandscapeMode

        ZStack {
          systemBackground
            .ignoresSafeArea()

          if showSplitLayout {
            // iPad regular width: mac-like split layout
            ScrollView {
              HStack(alignment: .top, spacing: DS.Spacing.xxxl) {
                // Left: cover
                VStack(spacing: DS.Spacing.xxl) {
                  BookCoverView(book: book, showMetadata: false)
                    .frame(maxWidth: DS.Layout.maxCoverWidth)

                  primaryActionButton
                    .frame(maxWidth: DS.Layout.maxButtonWidth)
                }
                .frame(maxWidth: .infinity, alignment: .top)

                // Right: details
                detailMetadataView
                  .frame(maxWidth: .infinity, alignment: .topLeading)
              }
              .padding(DS.Spacing.xxxl)
              .frame(maxWidth: DS.Layout.maxSplitWidth)
              .frame(maxWidth: .infinity)
            }
          } else {
            // Compact or narrow width: stacked layout
            ScrollView {
              VStack(spacing: DS.Spacing.xxl) {
                Color.clear.frame(height: DS.Spacing.sm)

                BookCoverView(book: book, showMetadata: false)
                  .frame(maxWidth: (hSizeClass == .regular) ? 280 : 220)
                  .padding(.horizontal, DS.Spacing.lg)
                  .frame(maxWidth: .infinity)

                VStack(spacing: DS.Spacing.xs) {
                  Text(book.title)
                    .font(.title.bold())
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)

                  Text(book.author)
                    .font(.title3)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                // Badges row
                badgesRow
                  .padding(.horizontal)

                cloudSyncCard
                  .padding(.horizontal)

                primaryActionButton
                  .frame(maxWidth: DS.Layout.maxButtonWidth)
                  .padding(.horizontal)
                  .frame(maxWidth: .infinity)
                  .padding(.top, DS.Spacing.xs)

                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                  Text("Synopsis")
                    .font(.headline)
                    .foregroundColor(.primary)

                  let maxLines = (hSizeClass == .regular) ? 14 : 10
                  Text(book.content.isEmpty ? "No description available for this book." : book.content)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineSpacing(DS.Typography.lineSpacing)
                    .lineLimit(maxLines)
                }
                .synopsisContainerStyle()
                .padding(.horizontal)

                Spacer(minLength: 50)
              }
              .frame(maxWidth: hSizeClass == .regular ? DS.Layout.maxContentWidth : .infinity)
              .padding(.horizontal, 0)
              .frame(maxWidth: .infinity)
            }
          }
        }
      }
      .navigationDestination(isPresented: $navigateToReader) {
        ReaderView(viewModel: ReaderViewModel(book: book))
      }
    #endif
  }

  #if os(macOS)
  private var macOSContent: some View {
    ZStack {
      systemBackground
        .ignoresSafeArea()

      ScrollView {
        HStack(alignment: .top, spacing: DS.Spacing.xxxl) {
          // Left: cover
          VStack(spacing: DS.Spacing.xxl) {
            BookCoverView(book: book, showMetadata: false)
              .frame(maxWidth: DS.Layout.maxCoverWidth)

            primaryActionButton
              .frame(maxWidth: DS.Layout.maxButtonWidth)
          }
          .frame(maxWidth: .infinity, alignment: .top)

          // Right: details
          detailMetadataView
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(DS.Spacing.xxxl)
        .frame(maxWidth: DS.Layout.maxSplitWidth)
        .frame(maxWidth: .infinity)
      }
    }
  }
  #endif

  private var systemBackground: Color {
    DS.Colors.groupedBackground
  }

  private var primaryActionButton: some View {
    Button(action: { navigateToReader = true }) {
      HStack(spacing: 8) {
        Image(systemName: "book.fill")
        Text(book.progress > 0 ? "Continue Reading" : "Start Reading")
      }
      .font(.headline.weight(.semibold))
      .foregroundColor(DS.Colors.onSelection)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 14)
      .background(Color.primary)
      .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private var detailMetadataView: some View {
    VStack(alignment: .leading, spacing: DS.Spacing.xl) {
      VStack(alignment: .leading, spacing: DS.Spacing.xs) {
        Text(book.title)
          .font(.largeTitle.bold())
          .foregroundColor(.primary)
          .fixedSize(horizontal: false, vertical: true)

        Text(book.author)
          .font(.title2)
          .foregroundColor(.secondary)
      }

      badgesRow

      cloudSyncCard

      VStack(alignment: .leading, spacing: DS.Spacing.md) {
        Text("Synopsis")
          .font(.headline)
          .foregroundColor(.primary)

        Text(book.content.isEmpty ? "No description available for this book." : book.content)
          .font(.body)
          .foregroundColor(.secondary)
          .lineSpacing(DS.Typography.lineSpacing)
      }
      .synopsisContainerStyle()
    }
  }

  private var badgesRow: some View {
    HStack(spacing: DS.Spacing.md) {
      HStack(spacing: 4) {
        Image(systemName: "doc.plaintext")
        Text((book.format ?? .text).rawValue.uppercased())
      }
      .font(.caption.bold())
      .foregroundColor(.primary)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(DS.Colors.cardBackground)
      .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
          .stroke(DS.Colors.border, lineWidth: 1)
      )

      if book.progress > 0 {
        HStack(spacing: 4) {
          Image(systemName: "chart.bar.fill")
          Text("\(Int(book.progress * 100))% Complete")
        }
        .font(.caption.bold())
        .foregroundColor(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DS.Colors.unselectedFill)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
            .stroke(DS.Colors.border, lineWidth: 1)
        )
      }

      if !book.safeBookmarks.isEmpty {
        HStack(spacing: 4) {
          Image(systemName: "bookmark.fill")
          Text("\(book.safeBookmarks.count) Bookmarks")
        }
        .font(.caption.bold())
        .foregroundColor(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
            .stroke(DS.Colors.border, lineWidth: 1)
        )
      }

      if cloudSync.activeProvider != .disabled {
        let syncStatus = cloudSync.syncStatus(for: book)
        HStack(spacing: 4) {
          Image(systemName: syncStatus.iconName)
          Text(syncStatus.displayText)
        }
        .font(.caption.bold())
        .foregroundColor(syncStatus == .synced ? .green : (syncStatus == .syncing ? .blue : (book.cloudSyncError != nil ? .orange : .secondary)))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
            .stroke(DS.Colors.border, lineWidth: 1)
        )
      }
    }
  }

  @ViewBuilder
  private var cloudSyncCard: some View {
    if cloudSync.activeProvider != .disabled {
      let status = cloudSync.syncStatus(for: book)
      if status != .synced {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(book.cloudSyncError != nil ? "Cloud Sync Notice" : "Cloud Backup")
              .font(.subheadline.bold())
              .foregroundColor(book.cloudSyncError != nil ? .orange : .primary)
            if let err = cloudSync.bookSyncErrors[book.id] ?? book.cloudSyncError {
              Text(err)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            } else {
              Text(cloudSync.activeProvider == .googleDrive ? "Ready to sync with Google Drive." : "Ready to sync with iCloud.")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          
          Spacer()
          
          Button(action: {
            Task {
              await cloudSync.syncSingleBook(book)
            }
          }) {
            HStack(spacing: 6) {
              if cloudSync.isBookSyncing(book.id) {
                ProgressView()
                  .controlSize(.small)
                Text("Syncing...")
              } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text(book.cloudSyncError != nil ? "Retry" : "Sync")
              }
            }
            .font(.caption.bold())
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          .disabled(cloudSync.isBookSyncing(book.id))
        }
        .padding(12)
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .stroke(DS.Colors.border, lineWidth: 1)
        )
      }
    }
  }
}

extension Book {
  fileprivate static var preview: Book {
    Book(
      title: "The Great Gatsby",
      author: "F. Scott Fitzgerald",
      coverImageName: "",
      content: "A portrait of the Jazz Age in all its decadence and excess..."
    )
  }
}

#Preview {
  BookDetailView(book: .preview)
}
