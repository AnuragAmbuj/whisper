//
//  BookDetailView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI

struct BookDetailView: View {
  let book: Book
  @State private var navigateToReader = false
  @Environment(\.dismiss) var dismiss
  @Environment(\.horizontalSizeClass) private var hSizeClass
  @Environment(\.verticalSizeClass) private var vSizeClass

  private func isLandscape(size: CGSize) -> Bool {
    size.width > size.height
  }

  var body: some View {
    NavigationStack {
      #if os(macOS)
        ZStack {
          LiquidBackground()
            .ignoresSafeArea()

          ScrollView {
            HStack(alignment: .top, spacing: DS.Spacing.xxxl) {
              // Left: cover
              VStack(spacing: DS.Spacing.xxl) {
                CachedAsyncImage(imageName: book.coverImageName) {
                  Rectangle()
                    .fill(
                      LinearGradient(
                        colors: [.cyan.opacity(0.8), .blue.opacity(0.8)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .overlay {
                      Image(systemName: "book.closed")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.5))
                    }
                }
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: DS.Layout.maxCoverWidth)
                .bookCoverStyle(size: .large)

                Button(action: { navigateToReader = true }) {
                  Text("Start Reading")
                    .primaryButtonStyle()
                }
                .frame(maxWidth: DS.Layout.maxButtonWidth)
              }
              .frame(maxWidth: .infinity, alignment: .top)

              // Right: details
              VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                  Text(book.title)
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)

                  Text(book.author)
                    .font(.title2)
                    .foregroundColor(.white.opacity(DS.Opacity.secondary))
                }

                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                  Text("Synopsis")
                    .font(.headline)
                    .foregroundColor(.white)

                  Text(book.content)
                    .font(.body)
                    .foregroundColor(.white.opacity(DS.Opacity.secondary))
                    .lineSpacing(DS.Typography.lineSpacing)
                }
                .synopsisContainerStyle()

                Spacer(minLength: DS.Spacing.xl)
              }
              .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(DS.Spacing.xxxl)
            .frame(maxWidth: DS.Layout.maxSplitWidth)
            .frame(maxWidth: .infinity)
          }
        }
        .navigationDestination(isPresented: $navigateToReader) {
          ReaderView(viewModel: ReaderViewModel(book: book))
        }
      #else
        GeometryReader { geometry in
          let isLandscape = isLandscape(size: geometry.size)
          let showSplitLayout = hSizeClass == .regular && isLandscape

          ZStack {
            LiquidBackground()
              .ignoresSafeArea()

            if showSplitLayout {
              // iPad regular width: mac-like split layout
              ScrollView {
                HStack(alignment: .top, spacing: DS.Spacing.xxxl) {
                  // Left: cover
                  VStack(spacing: DS.Spacing.xxl) {
                    Rectangle()
                      .fill(
                        LinearGradient(
                          colors: [.cyan.opacity(0.8), .blue.opacity(0.8)],
                          startPoint: .topLeading, endPoint: .bottomTrailing)
                      )
                      .frame(maxWidth: DS.Layout.maxCoverWidth)
                      .bookCoverStyle(size: .large)

                    Button(action: { navigateToReader = true }) {
                      Text("Start Reading")
                        .primaryButtonStyle()
                    }
                    .frame(maxWidth: DS.Layout.maxButtonWidth)
                  }
                  .frame(maxWidth: .infinity, alignment: .top)

                  // Right: details
                  VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                      Text(book.title)
                        .font(.largeTitle.bold())
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)

                      Text(book.author)
                        .font(.title2)
                        .foregroundColor(.white.opacity(DS.Opacity.secondary))
                    }

                    VStack(alignment: .leading, spacing: DS.Spacing.md) {
                      Text("Synopsis")
                        .font(.headline)
                        .foregroundColor(.white)

                      Text(book.content)
                        .font(.body)
                        .foregroundColor(.white.opacity(DS.Opacity.secondary))
                        .lineSpacing(DS.Typography.lineSpacing)
                    }
                    .synopsisContainerStyle()

                    Spacer(minLength: DS.Spacing.xl)
                  }
                  .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .padding(DS.Spacing.xxxl)
                .frame(maxWidth: DS.Layout.maxSplitWidth)
                .frame(maxWidth: .infinity)
              }
            } else {
              // Compact or narrow width: keep stacked layout
              ScrollView {
                VStack(spacing: DS.Spacing.xxl) {
                  Color.clear.frame(height: DS.Spacing.lg)

                  CachedAsyncImage(imageName: book.coverImageName) {
                    Rectangle()
                      .fill(
                        LinearGradient(
                          colors: [.cyan.opacity(0.8), .blue.opacity(0.8)],
                          startPoint: .topLeading, endPoint: .bottomTrailing)
                      )
                      .overlay {
                        Image(systemName: "book.closed")
                          .font(.system(size: 40))
                          .foregroundColor(.white.opacity(0.5))
                      }
                  }
                  .aspectRatio(contentMode: .fill)
                  .frame(maxWidth: (hSizeClass == .regular) ? 600 : 500)
                  .bookCoverStyle(size: .large)
                  .padding(.horizontal, DS.Spacing.lg)
                  .frame(maxWidth: .infinity)

                  VStack(spacing: DS.Spacing.sm) {
                    Text(book.title)
                      .font(.largeTitle.bold())
                      .minimumScaleFactor(0.8)
                      .multilineTextAlignment(.center)
                      .foregroundColor(.white)

                    Text(book.author)
                      .font(.title2)
                      .foregroundColor(.white.opacity(DS.Opacity.secondary))
                  }
                  .padding(.horizontal)

                  Button(action: { navigateToReader = true }) {
                    Text("Start Reading")
                      .primaryButtonStyle()
                  }
                  .frame(maxWidth: DS.Layout.maxButtonWidth)
                  .padding(.horizontal)
                  .frame(maxWidth: .infinity)
                  .padding(.top, DS.Spacing.sm)

                  VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    Text("Synopsis")
                      .font(.headline)
                      .foregroundColor(.white)

                    let maxLines = (hSizeClass == .regular) ? 14 : 10
                    Text(book.content)
                      .font(.body)
                      .foregroundColor(.white.opacity(DS.Opacity.secondary))
                      .lineSpacing(DS.Typography.lineSpacing)
                      .lineLimit(maxLines)
                      .overlay(alignment: .bottom) {
                        LinearGradient(
                          gradient: Gradient(colors: [.clear, .black.opacity(0.2)]),
                          startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 36)
                      }
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
        #if os(iOS)
          .toolbarBackground(.automatic, for: .navigationBar)
        #endif
      #endif
    }
  }
}

extension Book {
  fileprivate static var preview: Book {
    Book(
      title: "The Great Gatsby",
      author: "F. Scott Fitzgerald",
      coverImageName: "",
      content:
        "In my younger and more vulnerable years my father gave me some advice that I've been turning over in my mind ever since..."
    )
  }
}
#Preview("Book Detail") {
  NavigationStack {
    BookDetailView(book: .preview)
  }
}
