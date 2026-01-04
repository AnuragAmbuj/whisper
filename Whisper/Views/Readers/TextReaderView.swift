//
//  TextReaderView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI

struct TextReaderView: View {
  let book: Book
  let viewModel: ReaderViewModel
  // Actually ReaderViewModel is @Observable (macro) now. So just 'let'.
  // Wait, we need to bind preferences?
  // The previous implementation used GeometryReader in ReaderView to capture preferences and update ReaderView state.
  // If we move this to a subview, the preferences will bubble up to ReaderView? Yes, preferences bubble up.

  // We need 'viewModel' for theme/font access.
  var theme: AppTheme
  var fontSize: Double
  var lineHeight: CGFloat

  var body: some View {
    GeometryReader { outerGeo in
      ScrollViewReader { scrollProxy in
        ScrollView {
          VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            Text(book.title)
              .font(.custom(theme.fontName, size: fontSize * 1.5))
              .fontWeight(.bold)
              .foregroundColor(theme.textColor)
              .padding(.top, 60)

            Text(book.content)
              .font(.custom(theme.fontName, size: fontSize))
              .foregroundColor(theme.textColor)
              .lineSpacing(lineHeight)

            Color.clear.frame(height: 1).id("bottom")
          }
          .padding(.horizontal, DS.Spacing.xxl)
          .padding(.bottom, 100)
          .id("content")
          .background(
            GeometryReader { proxy in
              Color.clear
                .preference(key: ContentSizePreferenceKey.self, value: proxy.size)
            }
          )
          .background(
            GeometryReader { proxy in
              Color.clear
                .preference(
                  key: ScrollOffsetPreferenceKey.self, value: proxy.frame(in: .named("scroll")).minY
                )
            }
          )
        }
        .coordinateSpace(name: "scroll")  // This needs to match where the preference is read?
        // Actually ReaderView reads the preference. But the named coordinate space needs to be here?
        // Or ReaderView defines the coordinate space?
        // If ReaderView defines it, we can use it here.
        // Wait, ReaderView defined `.coordinateSpace(name: "scroll")` ON the ScrollView.
        // So I should keep it on the ScrollView.
        .onAppear {
          if book.progress > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
              withAnimation {
                scrollProxy.scrollTo("content", anchor: UnitPoint(x: 0, y: book.progress))
              }
            }
          }
        }
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
          calculateProgress(scrollOffset: value, outerHeight: outerGeo.size.height)
        }
        .onPreferenceChange(ContentSizePreferenceKey.self) { size in
          self.contentHeight = size.height
        }
      }
    }
  }

  @State private var contentHeight: CGFloat = 1

  func calculateProgress(scrollOffset: CGFloat, outerHeight: CGFloat) {
    let visibleHeight = outerHeight
    let totalContentHeight = contentHeight

    guard totalContentHeight > visibleHeight else { return }

    let maxOffset = totalContentHeight - visibleHeight
    let currentOffset = -scrollOffset

    let progress = max(0, min(1, currentOffset / maxOffset))
    viewModel.updateProgress(progress)
  }
}
