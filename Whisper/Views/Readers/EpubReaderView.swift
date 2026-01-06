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
  let theme: AppTheme
  let fontSize: Double

  @State private var webView: WKWebView?
  @State private var chapterPaths: [String] = []
  @State private var currentChapterIndex = 0
  @State private var isLoading = true
  @State private var isShowingTOC = false

  // Pagination State (Visual only, source of truth is JS)
  @State private var currentPage = 1
  @State private var totalPages = 1

  init(bookDir: URL, theme: AppTheme = .default, fontSize: Double = 18.0) {
    self.bookDir = bookDir
    self.theme = theme
    self.fontSize = fontSize
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      theme.backgroundColor
        .ignoresSafeArea()

      if let webView = webView {
        WebViewContainer(webView: webView)
          .edgesIgnoringSafeArea(.all)
          .opacity(isLoading ? 0 : 1)
      }

      if isLoading {
        ProgressView()
          .progressViewStyle(CircularProgressViewStyle(tint: theme.textColor))
          .scaleEffect(1.5)
      }

      // HUD Overlay
      if !isLoading && !chapterPaths.isEmpty {
        VStack {
          Spacer()
          HStack {
            // Previous
            Button(action: previousPageOrChapter) {
              Image(systemName: "chevron.left")
                .font(.title3)
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
            }
            .foregroundColor(theme.textColor)

            Spacer()

            // TOC
            Button(action: { isShowingTOC = true }) {
              VStack(spacing: 2) {
                Text("Chapter \(currentChapterIndex + 1)")
                  .font(.caption.bold())
                Text("Page \(currentPage) of \(totalPages)")
                  .font(.caption2)
              }
              .padding(.horizontal, 16)
              .padding(.vertical, 8)
              .background(.ultraThinMaterial)
              .cornerRadius(20)
            }
            .foregroundColor(theme.textColor)

            Spacer()

            // Next
            Button(action: nextPageOrChapter) {
              Image(systemName: "chevron.right")
                .font(.title3)
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
            }
            .foregroundColor(theme.textColor)
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 20)
        }
      }
    }
    .sheet(isPresented: $isShowingTOC) {
      tocSheet
    }
    .task {
      setupWebView()
      await loadEpubAsync()
    }
    .onChange(of: currentChapterIndex) { _, newIndex in
      loadChapter(at: newIndex)
    }
    .onChange(of: theme.style) { _, _ in updateAppearance() }
    .onChange(of: theme.isDarkMode) { _, _ in updateAppearance() }
    .onChange(of: fontSize) { _, _ in updateAppearance() }
  }

  private var tocSheet: some View {
    NavigationStack {
      List {
        ForEach(0..<chapterPaths.count, id: \.self) { index in
          Button(action: {
            currentChapterIndex = index
            isShowingTOC = false
          }) {
            HStack {
              Text("Chapter \(index + 1)")
                .foregroundColor(index == currentChapterIndex ? .accentColor : .primary)
              Spacer()
              if index == currentChapterIndex {
                Image(systemName: "checkmark")
                  .foregroundColor(.accentColor)
              }
            }
          }
        }
      }
      .navigationTitle("Table of Contents")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") {
            isShowingTOC = false
          }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  private func setupWebView() {
    let webView = WebKitWarmer.shared.createWebView(allowFileAccess: true)

    #if os(iOS)
      webView.isOpaque = false
      webView.backgroundColor = UIColor.clear
      webView.scrollView.backgroundColor = UIColor.clear
      webView.scrollView.contentInsetAdjustmentBehavior = .never
      webView.scrollView.isScrollEnabled = false
    #else
      webView.setValue(false, forKey: "drawsBackground")
    #endif

    webView.navigationDelegate = contextCoordinator
    self.webView = webView
  }

  // We need a coordinator for WKNavigationDelegate to handle load completion
  private class Coordinator: NSObject, WKNavigationDelegate {
    var parent: EpubReaderView

    init(_ parent: EpubReaderView) {
      self.parent = parent
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      print("EpubReader: WebView finished loading")
      // Inject CSS and JS after load
      parent.injectReadingSystem()
    }

    func webView(
      _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
      withError error: Error
    ) {
      print("EpubReader: WebLoad Error: \(error.localizedDescription)")
    }
  }

  @State private var coordinator: Coordinator?

  private var contextCoordinator: Coordinator {
    if let existing = coordinator { return existing }
    let new = Coordinator(self)
    // Store in state to keep alive
    DispatchQueue.main.async { self.coordinator = new }
    return new
  }

  // MARK: - Safe Navigation Logic

  private func previousPageOrChapter() {
    guard let webView = webView else { return }

    // Ask JS to try scrolling back
    webView.evaluateJavaScript("tryScrollPrev()") { result, _ in
      if let success = result as? Bool, success {
        // Scrolled successfully, update current page
        self.currentPage = max(1, self.currentPage - 1)
      } else {
        // Must be at start, go to prev chapter
        if self.currentChapterIndex > 0 {
          self.currentChapterIndex -= 1
          // When going back a chapter, we ideally want to land on the LAST page.
          // This implementation defaults to first page for stability.
          // To do last page, we'd need another JS param.
        }
      }
    }
  }

  private func nextPageOrChapter() {
    guard let webView = webView else { return }

    // Ask JS to try scrolling next
    webView.evaluateJavaScript("tryScrollNext()") { result, _ in
      if let success = result as? Bool, success {
        // Scrolled successfully
        self.currentPage = min(self.totalPages, self.currentPage + 1)
      } else {
        // At end, go to next chapter
        if self.currentChapterIndex < self.chapterPaths.count - 1 {
          self.currentChapterIndex += 1
        }
      }
    }
  }

  // MARK: - Loading & Injection

  private func loadEpubAsync() async {
    // Re-using existing logic but moved to background task

    let paths = await Task.detached(priority: .userInitiated) { [bookDir] () -> [String] in
      let spineURL = bookDir.appendingPathComponent("spine.json")
      guard let data = try? Data(contentsOf: spineURL),
        let relativePaths = try? JSONDecoder().decode([String].self, from: data)
      else {
        return []
      }
      return relativePaths.map { bookDir.appendingPathComponent($0).path }
    }.value

    chapterPaths = paths

    if !chapterPaths.isEmpty {
      DispatchQueue.main.async {
        loadChapter(at: 0)
      }
    }
  }

  private func loadChapter(at index: Int) {
    guard index >= 0, index < chapterPaths.count, let webView = webView else { return }

    isLoading = true
    // Reset page count visual state
    currentPage = 1
    totalPages = 1

    let chapterPath = chapterPaths[index]
    let chapterURL = URL(fileURLWithPath: chapterPath)

    // IMPORTANT: Read access to the BOOK directory, not just chapter
    webView.loadFileURL(chapterURL, allowingReadAccessTo: bookDir)
  }

  private func injectReadingSystem() {
    guard let webView = webView else { return }

    // Robust CSS with break protection
    let css = """
      :root {
          --bg-color: \(hexString(from: theme.backgroundColor));
          --text-color: \(hexString(from: theme.textColor));
          --font-size: \(fontSize)px;
          --line-height: \(theme.lineHeight);
      }

      html, body {
          height: 100vh;
          width: 100vw;
          margin: 0;
          padding: 0;
          overflow: hidden;
          background-color: var(--bg-color) !important;
          color: var(--text-color) !important;
      }

      body {
          font-size: var(--font-size) !important;
          line-height: var(--line-height) !important;
          font-family: -apple-system, system-ui, sans-serif;
          
          /* Column Layout for Horizontal Pagination */
          column-width: 100vw;
          column-gap: 0;
          column-fill: auto;
          
          /* Padding must be handled carefully with columns */
          padding: 20px 20px 40px 20px;
          box-sizing: border-box;
          
          -webkit-text-size-adjust: none;
      }

      /* Prevent content from breaking layout */
      img, video, svg {
          max-width: 100%;
          height: auto;
          max-height: 90vh;
          object-fit: contain;
          break-inside: avoid;
      }

      p, h1, h2, h3, h4, h5, h6, li, blockquote {
          break-inside: avoid; /* Try to keep paragraphs together */
      }

      * {
          background-color: transparent !important;
          color: inherit !important;
      }
      """

    // Robust JS with Tolerances
    let jsConfig = """
      // Inject CSS
      var style = document.createElement('style');
      style.innerHTML = `\(css)`;
      document.head.appendChild(style);

      // Prevent default touch/scroll actions
      document.addEventListener('touchmove', function(e) { e.preventDefault(); }, { passive: false });

      function getPageWidth() {
          return window.innerWidth;
      }

      function updateMetrics() {
          var scrollW = document.body.scrollWidth;
          var winW = window.innerWidth;
          var pages = Math.max(1, Math.ceil(scrollW / winW));
          
          // Current Page Calculation
          var currentScroll = window.scrollX;
          var page = Math.floor(currentScroll / winW) + 1;
          
          return {
              totalPages: pages,
              currentPage: page
          };
      }

      function tryScrollNext() {
          var currentX = window.scrollX;
          var winW = window.innerWidth;
          var limit = document.body.scrollWidth;
          
          // Tolerance of 5px to account for subpixel rendering
          if (currentX + winW < limit - 5) {
              window.scrollBy({ left: winW, behavior: 'smooth' });
              return true;
          }
          return false;
      }

      function tryScrollPrev() {
          var currentX = window.scrollX;
          var winW = window.innerWidth;
          
          if (currentX - winW >= -5) {
              window.scrollBy({ left: -winW, behavior: 'smooth' });
              return true;
          }
          return false;
      }

      // Initial Calculation
      updateMetrics();
      """

    webView.evaluateJavaScript(jsConfig) { result, error in
      if let error = error {
        print("JS Logic Error: \(error)")
      } else if let dict = result as? [String: Any],
        let pages = dict["totalPages"] as? Int
      {
        self.totalPages = pages
        self.isLoading = false
      } else {
        // Fallback
        self.totalPages = 1
        self.isLoading = false
      }
    }
  }

  private func updateAppearance() {
    guard let webView = webView else { return }

    let cssUpdate = """
      document.documentElement.style.setProperty('--bg-color', '\(hexString(from: theme.backgroundColor))');
      document.documentElement.style.setProperty('--text-color', '\(hexString(from: theme.textColor))');
      document.documentElement.style.setProperty('--font-size', '\(fontSize)px');

      // Return metrics for UI update
      updateMetrics();
      """

    webView.evaluateJavaScript(cssUpdate) { result, _ in
      if let dict = result as? [String: Any],
        let pages = dict["totalPages"] as? Int
      {
        self.totalPages = pages
        // If current page > total, snap back
        if self.currentPage > pages {
          self.currentPage = pages
          let script = "window.scrollTo((3000000), 0);"  // Scroll to end
          webView.evaluateJavaScript(script)
        }
      }
    }
  }

  // Helper for Color to Hex
  private func hexString(from color: Color) -> String {
    #if os(iOS)
      let uiColor = UIColor(color)
      var r: CGFloat = 0
      var g: CGFloat = 0
      var b: CGFloat = 0
      var a: CGFloat = 0
      uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
      return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    #else
      let nsColor = NSColor(color)
      guard let rgbColor = nsColor.usingColorSpace(.deviceRGB) else { return "#000000" }
      return String(
        format: "#%02X%02X%02X", Int(rgbColor.redComponent * 255),
        Int(rgbColor.greenComponent * 255), Int(rgbColor.blueComponent * 255))
    #endif
  }
}

#if os(iOS)
  struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
      return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
  }
#elseif os(macOS)
  struct WebViewContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
      return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
  }
#endif
