//
//  EpubReaderView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI
import WebKit

struct EpubReaderView: View {
  let bookDir: URL
  @State private var webView = WKWebView()
  @State private var chapterPaths: [String] = []
  @State private var currentChapterIndex = 0
  @State private var isLoading = true

  @State private var isShowingTOC = false

  var body: some View {
    ZStack(alignment: .bottom) {
      // WebView Container
      WebViewContainer(webView: webView)
        .edgesIgnoringSafeArea(.all)

      // Navigation Overlay
      if !chapterPaths.isEmpty {
        HStack {
          Button(action: previousChapter) {
            Image(systemName: "chevron.left")
              .font(.title2)
              .iconButtonStyle()
          }
          .disabled(currentChapterIndex <= 0)
          .opacity(currentChapterIndex <= 0 ? 0.3 : 1)

          Spacer()

          // Center Controls
          HStack(spacing: DS.Spacing.md) {
            Text("Chapter \(currentChapterIndex + 1) / \(chapterPaths.count)")
              .font(.caption)
              .chipStyle()

            Button(action: { isShowingTOC = true }) {
              Image(systemName: "list.bullet")
                .font(.body)
                .iconButtonStyle(padding: DS.Spacing.xs)
            }
          }

          Spacer()

          Button(action: nextChapter) {
            Image(systemName: "chevron.right")
              .font(.title2)
              .iconButtonStyle()
          }
          .disabled(currentChapterIndex >= chapterPaths.count - 1)
          .opacity(currentChapterIndex >= chapterPaths.count - 1 ? 0.3 : 1)
        }
        .padding()
        .padding(.bottom, DS.Spacing.xl)
      }

      if isLoading {
        ProgressView()
          .padding()
          .background(.ultraThinMaterial)
          .cornerRadius(DS.Radius.sm)
      }
    }
    .onAppear {
      setupWebView()
      loadSpine()
    }
    .sheet(isPresented: $isShowingTOC) {
      ChapterListView(bookDir: bookDir, isPresented: $isShowingTOC) { selectedPath in
        // Handle Selection
        // Need to find index of this path in spine if possible, or just load URL.
        // If we load URL directly, 'currentChapterIndex' might get out of sync if the path is not in 'chapterPaths' exactly.
        // But usually TOC items point to spine items.

        // Try to match path suffix
        if let index = chapterPaths.firstIndex(where: {
          selectedPath.hasSuffix($0) || $0.hasSuffix(selectedPath)
        }) {
          loadChapter(at: index)
        } else {
          // Load direct
          let fileURL = bookDir.appendingPathComponent(selectedPath)
          webView.loadFileURL(fileURL, allowingReadAccessTo: bookDir)
        }
      }
    }
  }

  func setupWebView() {
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.showsVerticalScrollIndicator = true
  }

  func loadSpine() {
    let spineURL = bookDir.appendingPathComponent("spine.json")
    do {
      let data = try Data(contentsOf: spineURL)
      chapterPaths = try JSONDecoder().decode([String].self, from: data)
      isLoading = false
      loadChapter(at: 0)
    } catch {
      print("Failed to load spine: \(error)")
      // Fallback: Try finding any HTML file if spine fails
      if let files = FileManager.default.enumerator(at: bookDir, includingPropertiesForKeys: nil),
        let htmlFile = files.allObjects.compactMap({ $0 as? URL }).first(where: {
          $0.pathExtension == "html" || $0.pathExtension == "xhtml"
        })
      {
        // Determine relative path for consistency if needed, but for fallback just load absolute
        // We won't have navigation though.
        isLoading = false
        webView.loadFileURL(htmlFile, allowingReadAccessTo: bookDir)
      }
    }
  }

  func loadChapter(at index: Int) {
    guard index >= 0 && index < chapterPaths.count else { return }
    currentChapterIndex = index
    let path = chapterPaths[index]
    let fileURL = bookDir.appendingPathComponent(path)

    webView.loadFileURL(fileURL, allowingReadAccessTo: bookDir)
  }

  func nextChapter() {
    loadChapter(at: currentChapterIndex + 1)
  }

  func previousChapter() {
    loadChapter(at: currentChapterIndex - 1)
  }
}

// Wrapper to use WKWebView in SwiftUI
struct WebViewContainer: UIViewRepresentable {
  let webView: WKWebView

  func makeUIView(context: Context) -> WKWebView {
    return webView
  }

  func updateUIView(_ uiView: WKWebView, context: Context) {}
}
