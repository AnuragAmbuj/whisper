//
//  EpubReaderView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import Combine
import SwiftUI
import WebKit

enum EpubReadingMode: String, CaseIterable, Identifiable {
  case paginated = "Pages"
  case scroll = "Scroll"

  var id: String { rawValue }

  var icon: String {
    switch self {
    case .paginated: return "book.pages"
    case .scroll: return "doc.text.below.ecg"
    }
  }
}

// MARK: - Weak Script Message Handler to Prevent Retain Cycles
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
  private weak var delegate: WKScriptMessageHandler?

  init(delegate: WKScriptMessageHandler) {
    self.delegate = delegate
    super.init()
  }

  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    delegate?.userContentController(userContentController, didReceive: message)
  }
}

// MARK: - Dedicated Controller for WebKit Navigation & Reading Engine
@MainActor
final class EpubReaderController: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
  @Published var isLoading: Bool = true
  @Published var currentPage: Int = 1
  @Published var totalPages: Int = 1
  @Published var currentChapterIndex: Int = 0
  @Published var totalChapters: Int = 1
  @Published var scrollPercentage: Double = 0.0
  @Published var readingMode: EpubReadingMode
  @Published var errorMessage: String? = nil

  var webView: WKWebView?
  private(set) var bookDir: URL
  private var currentLoadedURL: URL?
  private var chapterPaths: [String] = []
  private var continuousBookURL: URL?
  private var continuousHTMLContent: String?
  private var watchdogTask: Task<Void, Never>?

  var onProgressUpdated: ((Double) -> Void)?
  var onChapterChanged: ((Int) -> Void)?
  var onTapRecognized: (() -> Void)?

  private var cachedTheme: AppTheme = .default
  private var cachedFontSize: Double = 19.0

  init(bookDir: URL, initialMode: EpubReadingMode = .paginated) {
    self.bookDir = bookDir
    self.readingMode = initialMode
    super.init()
  }

  func attach(webView: WKWebView) {
    self.webView = webView
    webView.navigationDelegate = self

    #if os(iOS)
      webView.isOpaque = false
      webView.backgroundColor = .clear
      webView.scrollView.backgroundColor = .clear
      webView.scrollView.bounces = true
      webView.scrollView.alwaysBounceVertical = (readingMode == .scroll)
      webView.scrollView.showsVerticalScrollIndicator = (readingMode == .scroll)
      webView.scrollView.showsHorizontalScrollIndicator = false
      webView.scrollView.minimumZoomScale = 1.0
      webView.scrollView.maximumZoomScale = 4.0
      webView.scrollView.isScrollEnabled = true
      webView.isUserInteractionEnabled = true
    #else
      webView.setValue(false, forKey: "drawsBackground")
      webView.allowsMagnification = true
    #endif

    let contentController = webView.configuration.userContentController
    contentController.removeScriptMessageHandler(forName: "whisperTap")
    contentController.add(WeakScriptMessageHandler(delegate: self), name: "whisperTap")

    contentController.removeScriptMessageHandler(forName: "whisperProgress")
    contentController.add(WeakScriptMessageHandler(delegate: self), name: "whisperProgress")

    contentController.removeScriptMessageHandler(forName: "whisperChapterChanged")
    contentController.add(WeakScriptMessageHandler(delegate: self), name: "whisperChapterChanged")
  }

  func configureBook(chapterPaths: [String], bookTitle: String, theme: AppTheme, fontSize: Double) {
    self.chapterPaths = chapterPaths
    self.totalChapters = max(1, chapterPaths.count)
    self.cachedTheme = theme
    self.cachedFontSize = fontSize

    if readingMode == .scroll {
      loadContinuousBook(bookTitle: bookTitle, theme: theme, fontSize: fontSize)
    } else {
      if let first = chapterPaths.first {
        loadChapter(at: URL(fileURLWithPath: first), theme: theme, fontSize: fontSize)
      } else {
        isLoading = false
      }
    }
  }

  /// Stitches all chapters together into a unified, seamless continuous scroll document
  func loadContinuousBook(bookTitle: String, theme: AppTheme, fontSize: Double) {
    guard let webView = webView else { return }
    isLoading = true
    errorMessage = nil

    watchdogTask?.cancel()
    watchdogTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 3_500_000_000)
      guard let self = self, self.isLoading else { return }
      self.injectReaderCSS(theme: theme, fontSize: fontSize)
      self.isLoading = false
    }

    Task.detached(priority: .userInitiated) { [bookDir = self.bookDir, paths = self.chapterPaths] in
      let (fileURL, html) = await Self.generateContinuousDocument(
        bookDir: bookDir,
        chapterPaths: paths,
        bookTitle: bookTitle
      )
      await MainActor.run {
        self.continuousBookURL = fileURL
        self.continuousHTMLContent = html

        let canonicalBookDir = bookDir.resolvingSymlinksInPath()

        if let fileURL = fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
          let canonicalFileURL = fileURL.resolvingSymlinksInPath()
          self.currentLoadedURL = canonicalFileURL
          webView.loadFileURL(canonicalFileURL, allowingReadAccessTo: canonicalBookDir)
        } else if let html = html {
          // Direct HTML String fallback with canonical base URL
          webView.loadHTMLString(html, baseURL: canonicalBookDir)
        } else if let first = paths.first {
          let fallbackURL = URL(fileURLWithPath: first).resolvingSymlinksInPath()
          self.currentLoadedURL = fallbackURL
          webView.loadFileURL(fallbackURL, allowingReadAccessTo: canonicalBookDir)
        } else {
          self.isLoading = false
          self.errorMessage = "Unable to generate continuous reading document."
        }
      }
    }
  }

  func loadChapter(at url: URL, theme: AppTheme, fontSize: Double) {
    guard let webView = webView else { return }
    let canonicalURL = url.resolvingSymlinksInPath()
    let canonicalBookDir = bookDir.resolvingSymlinksInPath()

    currentLoadedURL = canonicalURL
    isLoading = true
    currentPage = 1
    totalPages = 1
    errorMessage = nil

    watchdogTask?.cancel()
    watchdogTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 3_000_000_000)
      guard let self = self, self.isLoading else { return }
      self.injectReaderCSS(theme: theme, fontSize: fontSize)
      self.isLoading = false
    }

    if FileManager.default.fileExists(atPath: canonicalURL.path) {
      webView.loadFileURL(canonicalURL, allowingReadAccessTo: canonicalBookDir)
    } else if let data = try? Data(contentsOf: canonicalURL) {
      let content = String(decoding: data, as: UTF8.self)
      webView.loadHTMLString(content, baseURL: canonicalURL.deletingLastPathComponent())
    } else {
      isLoading = false
      errorMessage = "Unable to open chapter at: \(url.lastPathComponent)"
    }
  }

  // MARK: - WKNavigationDelegate

  nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    Task { @MainActor in
      self.watchdogTask?.cancel()
      self.injectReaderCSS(theme: self.cachedTheme, fontSize: self.cachedFontSize)
    }
  }

  nonisolated func webView(
    _ webView: WKWebView, didFail navigation: WKNavigation!,
    withError error: Error
  ) {
    Task { @MainActor in
      self.watchdogTask?.cancel()
      if let html = self.continuousHTMLContent {
        webView.loadHTMLString(html, baseURL: self.bookDir.resolvingSymlinksInPath())
      } else {
        self.isLoading = false
      }
    }
  }

  nonisolated func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    Task { @MainActor in
      self.watchdogTask?.cancel()
      // If provisional navigation fails (sandbox token rejection), fall back to loadHTMLString
      if let html = self.continuousHTMLContent {
        webView.loadHTMLString(html, baseURL: self.bookDir.resolvingSymlinksInPath())
      } else {
        self.isLoading = false
        self.errorMessage = "Failed to load reader: \(error.localizedDescription)"
      }
    }
  }

  // MARK: - WKScriptMessageHandler

  nonisolated func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    Task { @MainActor in
      if message.name == "whisperTap" {
        self.onTapRecognized?()
      } else if message.name == "whisperProgress" {
        if let body = message.body as? [String: Any],
           let progress = body["progress"] as? Double {
          self.scrollPercentage = progress
          self.onProgressUpdated?(progress)
        }
      } else if message.name == "whisperChapterChanged" {
        if let body = message.body as? [String: Any],
           let idx = body["chapterIndex"] as? Int {
          self.currentChapterIndex = idx
          self.onChapterChanged?(idx)
        }
      }
    }
  }

  // MARK: - Script Injection & Styling

  func updateThemeAndFont(theme: AppTheme, fontSize: Double) {
    self.cachedTheme = theme
    self.cachedFontSize = fontSize
    injectReaderCSS(theme: theme, fontSize: fontSize)
  }

  func setReadingMode(_ mode: EpubReadingMode) {
    self.readingMode = mode
    #if os(iOS)
      webView?.scrollView.alwaysBounceVertical = (mode == .scroll)
      webView?.scrollView.showsVerticalScrollIndicator = (mode == .scroll)
    #endif

    if mode == .scroll && continuousBookURL != nil {
      if currentLoadedURL != continuousBookURL, let continuousURL = continuousBookURL {
        currentLoadedURL = continuousURL
        let canonicalBookDir = bookDir.resolvingSymlinksInPath()
        webView?.loadFileURL(continuousURL.resolvingSymlinksInPath(), allowingReadAccessTo: canonicalBookDir)
        return
      }
    }

    injectReaderCSS(theme: cachedTheme, fontSize: cachedFontSize)
  }

  func scrollToChapter(index: Int) {
    guard let webView = webView else { return }
    self.currentChapterIndex = index

    if readingMode == .scroll {
      let js = "var el = document.getElementById('chapter-\(index)'); if (el) { el.scrollIntoView({ behavior: 'smooth', block: 'start' }); }"
      webView.evaluateJavaScript(js)
    } else {
      guard index >= 0, index < chapterPaths.count else { return }
      let url = URL(fileURLWithPath: chapterPaths[index])
      loadChapter(at: url, theme: cachedTheme, fontSize: cachedFontSize)
    }
  }

  func scrollToNextChapter() {
    if readingMode == .scroll {
      let nextIndex = min(totalChapters - 1, currentChapterIndex + 1)
      scrollToChapter(index: nextIndex)
    } else {
      nextPage {
        let nextIndex = self.currentChapterIndex + 1
        if nextIndex < self.chapterPaths.count {
          self.currentChapterIndex = nextIndex
          self.loadChapter(at: URL(fileURLWithPath: self.chapterPaths[nextIndex]), theme: self.cachedTheme, fontSize: self.cachedFontSize)
        }
      }
    }
  }

  func scrollToPreviousChapter() {
    if readingMode == .scroll {
      let prevIndex = max(0, currentChapterIndex - 1)
      scrollToChapter(index: prevIndex)
    } else {
      previousPage {
        let prevIndex = self.currentChapterIndex - 1
        if prevIndex >= 0 {
          self.currentChapterIndex = prevIndex
          self.loadChapter(at: URL(fileURLWithPath: self.chapterPaths[prevIndex]), theme: self.cachedTheme, fontSize: self.cachedFontSize)
        }
      }
    }
  }

  func injectReaderCSS(theme: AppTheme, fontSize: Double) {
    guard let webView = webView else { return }

    let bgHex = hexString(from: theme.backgroundColor)
    let textHex = hexString(from: theme.textColor)
    let fontCSS = fontFamilyCSS(for: theme.fontName)
    let isPaged = (readingMode == .paginated)

    let js = """
      (function() {
        // 1. Viewport Meta
        var meta = document.querySelector('meta[name="viewport"]');
        if (!meta) {
          meta = document.createElement('meta');
          meta.name = 'viewport';
          document.head.appendChild(meta);
        }
        meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes';

        // 2. Remove prior styles
        var oldStyle = document.getElementById('whisper-reader-style');
        if (oldStyle) oldStyle.remove();

        // 3. Inject new layout and typography style
        var style = document.createElement('style');
        style.id = 'whisper-reader-style';
        style.textContent = `
          :root {
            --whisper-bg: \(bgHex);
            --whisper-text: \(textHex);
            --whisper-font-size: \(fontSize)px;
            --whisper-line-height: \(theme.lineHeight);
          }

          * {
            box-sizing: border-box !important;
            -webkit-tap-highlight-color: transparent;
          }

          html {
            background-color: var(--whisper-bg) !important;
            color: var(--whisper-text) !important;
            -webkit-text-size-adjust: 100% !important;
            scroll-behavior: smooth;
            \(isPaged ?
              "height: 100vh !important; width: 100vw !important; overflow: hidden !important;" :
              "min-height: 100% !important; overflow-x: hidden !important;"
            )
          }

          html::-webkit-scrollbar { display: none !important; }

          body {
            background-color: var(--whisper-bg) !important;
            color: var(--whisper-text) !important;
            font-size: var(--whisper-font-size) !important;
            line-height: var(--whisper-line-height) !important;
            font-family: \(fontCSS) !important;
            margin: 0 !important;
            word-wrap: break-word !important;
            overflow-wrap: break-word !important;
            -webkit-font-smoothing: antialiased;
            \(isPaged ?
              "height: calc(100vh - 100px) !important; width: 100vw !important; padding: 24px 24px 70px 24px !important; column-width: calc(100vw - 48px) !important; column-gap: 48px !important; column-fill: auto !important; overflow-x: scroll !important; overflow-y: hidden !important; scrollbar-width: none !important; -webkit-overflow-scrolling: touch !important;"
              :
              "max-width: 720px !important; margin: 0 auto !important; padding: max(28px, env(safe-area-inset-top, 28px)) max(20px, env(safe-area-inset-right, 20px)) max(150px, env(safe-area-inset-bottom, 150px)) max(20px, env(safe-area-inset-left, 20px)) !important; overflow-x: hidden !important;"
            )
          }

          body::-webkit-scrollbar { display: none !important; }

          .whisper-book-container {
            width: 100%;
          }

          .whisper-chapter {
            margin-bottom: 56px;
            scroll-margin-top: 60px;
          }

          .whisper-chapter-divider {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 16px;
            margin: 64px 0 44px 0;
          }

          .whisper-divider-line {
            flex: 1;
            height: 1px;
            background: var(--whisper-text);
            opacity: 0.18;
          }

          .whisper-divider-pill {
            font-size: 0.82em;
            font-weight: 600;
            letter-spacing: 0.06em;
            text-transform: uppercase;
            color: var(--whisper-text);
            opacity: 0.8;
            padding: 6px 16px;
            border-radius: 14px;
            border: 1px solid rgba(128, 128, 128, 0.28);
            background: var(--whisper-bg);
          }

          h1, h2, h3, h4, h5, h6 {
            color: var(--whisper-text) !important;
            font-weight: 700 !important;
            line-height: 1.3 !important;
            margin-top: 1.4em !important;
            margin-bottom: 0.6em !important;
          }
          h1 { font-size: 1.65em !important; }
          h2 { font-size: 1.35em !important; }
          h3 { font-size: 1.18em !important; }

          p {
            color: var(--whisper-text) !important;
            margin: 0 0 1.2em 0 !important;
            line-height: var(--whisper-line-height) !important;
            text-align: justify;
            text-justify: inter-word;
            -webkit-hyphens: auto;
            hyphens: auto;
            word-break: break-word;
          }

          blockquote {
            border-left: 3px solid var(--whisper-text);
            opacity: 0.85;
            margin: 1.3em 0 1.3em 1.2em !important;
            padding-left: 1.1em !important;
            font-style: italic;
          }

          img {
            max-width: 100% !important;
            height: auto !important;
            display: block;
            margin: 20px auto !important;
            border-radius: 8px !important;
          }

          p img, span img {
            display: inline-block !important;
            margin: 0 4px !important;
            max-height: 1.8em !important;
            vertical-align: middle !important;
          }

          table {
            max-width: 100% !important;
            border-collapse: collapse !important;
            margin: 1.5em 0 !important;
          }
          th, td {
            border: 1px solid var(--whisper-text);
            opacity: 0.8;
            padding: 8px 12px;
          }
        `;
        document.head.appendChild(style);

        // 4. Stationary Tap & Interaction Listener (non-interfering)
        if (!window._whisperTapAttached) {
          window._whisperTapAttached = true;
          var touchStartX = 0;
          var touchStartY = 0;
          var touchStartTime = 0;

          document.addEventListener('touchstart', function(e) {
            if (e.touches && e.touches.length === 1) {
              touchStartX = e.touches[0].clientX;
              touchStartY = e.touches[0].clientY;
              touchStartTime = Date.now();
            }
          }, { passive: true });

          document.addEventListener('touchend', function(e) {
            if (!e.changedTouches || e.changedTouches.length !== 1) return;
            var dt = Date.now() - touchStartTime;
            var dx = Math.abs(e.changedTouches[0].clientX - touchStartX);
            var dy = Math.abs(e.changedTouches[0].clientY - touchStartY);

            // Stationary tap within 350ms and under 12px motion
            if (dt < 350 && dx < 12 && dy < 12) {
              var target = e.target;
              if (target && (target.tagName === 'A' || target.closest('A'))) {
                return; // Let hyperlink follow
              }
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.whisperTap) {
                window.webkit.messageHandlers.whisperTap.postMessage({});
              }
            }
          }, { passive: true });

          // Smooth internal anchor jump
          document.addEventListener('click', function(e) {
            var a = e.target.closest('a');
            if (!a) return;
            var href = a.getAttribute('href');
            if (href && href.startsWith('#')) {
              var el = document.querySelector(href);
              if (el) {
                e.preventDefault();
                el.scrollIntoView({ behavior: 'smooth' });
              }
            }
          });

          // Scroll percentage tracking
          window.addEventListener('scroll', function() {
            var docH = (document.documentElement.scrollHeight || document.body.scrollHeight) - window.innerHeight;
            var scrolled = window.scrollY || window.pageYOffset || 0;
            var progress = docH > 0 ? Math.min(1.0, Math.max(0.0, scrolled / docH)) : 0.0;
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.whisperProgress) {
              window.webkit.messageHandlers.whisperProgress.postMessage({ progress: progress });
            }
          }, { passive: true });

          // Intersection observer for continuous chapter tracking
          var chapterSections = document.querySelectorAll('.whisper-chapter');
          if (chapterSections.length > 0 && 'IntersectionObserver' in window) {
            var observer = new IntersectionObserver(function(entries) {
              var visible = entries.filter(function(e) { return e.isIntersecting; });
              if (visible.length > 0) {
                visible.sort(function(a, b) {
                  return Math.abs(a.boundingClientRect.top) - Math.abs(b.boundingClientRect.top);
                });
                var idx = parseInt(visible[0].target.getAttribute('data-chapter-index'), 10);
                if (!isNaN(idx) && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.whisperChapterChanged) {
                  window.webkit.messageHandlers.whisperChapterChanged.postMessage({ chapterIndex: idx });
                }
              }
            }, {
              rootMargin: '0px 0px -50% 0px',
              threshold: [0, 0.25, 0.5]
            });

            chapterSections.forEach(function(sec) {
              observer.observe(sec);
            });
          }
        }

        // 5. Paginated metrics
        var winW = window.innerWidth || 390;
        var scrollW = document.body.scrollWidth || document.documentElement.scrollWidth || winW;
        var pages = Math.max(1, Math.round(scrollW / winW));
        var currentScrollX = document.body.scrollLeft || window.scrollX || 0;
        var currPage = Math.min(pages, Math.max(1, Math.round(currentScrollX / winW) + 1));

        return {
          totalPages: pages,
          currentPage: currPage
        };
      })();
    """

    webView.evaluateJavaScript(js) { [weak self] result, error in
      guard let self = self else { return }
      if let dict = result as? [String: Any] {
        if let total = dict["totalPages"] as? Int {
          self.totalPages = max(1, total)
        }
        if let current = dict["currentPage"] as? Int {
          self.currentPage = max(1, min(self.totalPages, current))
        }
      }
      withAnimation(.easeOut(duration: 0.2)) {
        self.isLoading = false
      }
    }
  }

  // MARK: - Continuous Document Generator

  private static func generateContinuousDocument(
    bookDir: URL,
    chapterPaths: [String],
    bookTitle: String
  ) -> (URL?, String?) {
    let outputURL = bookDir.appendingPathComponent("whisper_continuous_book.html")
    let fileManager = FileManager.default

    // Load table of contents mapping if available
    var tocTitleMap: [String: String] = [:]
    let tocURL = bookDir.appendingPathComponent("toc.json")
    if let data = try? Data(contentsOf: tocURL),
       let chapters = try? JSONDecoder().decode([Chapter].self, from: data) {
      for ch in chapters {
        let clean = (ch.path.components(separatedBy: "#").first ?? ch.path).removingPercentEncoding ?? ch.path
        let filename = (clean as NSString).lastPathComponent
        tocTitleMap[filename] = ch.title
        tocTitleMap[clean] = ch.title
      }
    }

    var combinedSections: [String] = []
    var combinedHeadStyles: [String] = []

    for (index, path) in chapterPaths.enumerated() {
      let fileURL = URL(fileURLWithPath: path)
      let fileData = (try? Data(contentsOf: fileURL)) ?? Data()
      guard !fileData.isEmpty else { continue }

      let rawContent = String(decoding: fileData, as: UTF8.self)

      let chapterDirRel = fileURL.deletingLastPathComponent().path
        .replacingOccurrences(of: bookDir.path, with: "")
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

      let filename = fileURL.lastPathComponent
      let chapterTitle = tocTitleMap[filename] ?? tocTitleMap[path] ?? extractTitle(from: rawContent) ?? "Chapter \(index + 1)"
      let bodyContent = extractBody(from: rawContent)
      let resolvedContent = rewriteRelativePaths(html: bodyContent, chapterDir: chapterDirRel)
      let headStyles = extractHeadStyles(from: rawContent)
      if !headStyles.isEmpty {
        combinedHeadStyles.append(headStyles)
      }

      let sectionHTML = """
      <section id="chapter-\(index)" class="whisper-chapter" data-chapter-index="\(index)" data-chapter-title="\(chapterTitle)">
        \(index > 0 ? """
        <div class="whisper-chapter-divider">
          <div class="whisper-divider-line"></div>
          <span class="whisper-divider-pill">\(chapterTitle)</span>
          <div class="whisper-divider-line"></div>
        </div>
        """ : "")
        <div class="whisper-chapter-content">
          \(resolvedContent)
        </div>
      </section>
      """
      combinedSections.append(sectionHTML)
    }

    guard !combinedSections.isEmpty else { return (nil, nil) }

    let fullHTML = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes">
      <title>\(bookTitle)</title>
      \(combinedHeadStyles.joined(separator: "\n"))
    </head>
    <body>
      <main class="whisper-book-container">
        \(combinedSections.joined(separator: "\n"))
      </main>
    </body>
    </html>
    """

    do {
      try fullHTML.write(to: outputURL, atomically: true, encoding: .utf8)
      return (outputURL, fullHTML)
    } catch {
      print("EpubReaderController: Failed to write continuous book: \(error.localizedDescription)")
      return (nil, fullHTML)
    }
  }

  private static func extractBody(from html: String) -> String {
    let pattern = "(?is)<body[^>]*>(.*?)</body>"
    if let regex = try? NSRegularExpression(pattern: pattern),
       let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: html.utf16.count)),
       let range = Range(match.range(at: 1), in: html) {
      return String(html[range])
    }
    return html
      .replacingOccurrences(of: "<!DOCTYPE[^>]*>", with: "", options: .regularExpression)
      .replacingOccurrences(of: "<html[^>]*>", with: "", options: .regularExpression)
      .replacingOccurrences(of: "</html>", with: "")
  }

  private static func extractHeadStyles(from html: String) -> String {
    let pattern = "(?is)<style[^>]*>(.*?)</style>"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
    let matches = regex.matches(in: html, range: NSRange(location: 0, length: html.utf16.count))
    var styles: [String] = []
    for match in matches {
      if let range = Range(match.range, in: html) {
        styles.append(String(html[range]))
      }
    }
    return styles.joined(separator: "\n")
  }

  private static func extractTitle(from html: String) -> String? {
    let patterns = [
      "(?is)<h[1-2][^>]*>(.*?)</h[1-2]>",
      "(?is)<title[^>]*>(.*?)</title>"
    ]
    for pattern in patterns {
      if let regex = try? NSRegularExpression(pattern: pattern),
         let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: html.utf16.count)),
         let range = Range(match.range(at: 1), in: html) {
        let raw = String(html[range])
        let clean = raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
          .trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty && clean.count < 80 {
          return clean
        }
      }
    }
    return nil
  }

  private static func rewriteRelativePaths(html: String, chapterDir: String) -> String {
    guard !chapterDir.isEmpty else { return html }

    let pattern = "(?i)(src|href|xlink:href)\\s*=\\s*([\"'])([^\"']+)\\2"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }

    var result = html
    let matches = regex.matches(in: html, range: NSRange(location: 0, length: html.utf16.count)).reversed()
    for match in matches {
      if let attrRange = Range(match.range(at: 1), in: result),
         let quoteRange = Range(match.range(at: 2), in: result),
         let valRange = Range(match.range(at: 3), in: result) {
        let attr = String(result[attrRange])
        let val = String(result[valRange])

        // Skip anchors, web links, and data URLs
        if val.hasPrefix("http:") || val.hasPrefix("https:") || val.hasPrefix("data:") || val.hasPrefix("#") || val.hasPrefix("/") {
          continue
        }

        let dummyBase = "/whisper_base"
        let full = (dummyBase as NSString).appendingPathComponent(chapterDir).appending("/\(val)")
        let normalized = URL(fileURLWithPath: full).standardized.path
        if normalized.hasPrefix(dummyBase + "/") {
          let resolved = String(normalized.dropFirst(dummyBase.count + 1))
          let quote = String(result[quoteRange])
          if let fullRange = Range(match.range, in: result) {
            result.replaceSubrange(fullRange, with: "\(attr)=\(quote)\(resolved)\(quote)")
          }
        }
      }
    }
    return result
  }

  // MARK: - Navigation Control

  func nextPage(onChapterEnd: @escaping () -> Void) {
    guard let webView = webView else { return }

    if readingMode == .scroll {
      webView.evaluateJavaScript("window.scrollBy({ top: window.innerHeight * 0.85, behavior: 'smooth' });")
      return
    }

    let js = """
      (function() {
        var winW = window.innerWidth || 390;
        var scrollW = document.body.scrollWidth || document.documentElement.scrollWidth || winW;
        var pages = Math.max(1, Math.round(scrollW / winW));
        var currX = document.body.scrollLeft || window.scrollX || 0;
        var curr = Math.min(pages, Math.max(1, Math.round(currX / winW) + 1));
        if (curr < pages) {
          var targetX = curr * winW;
          if (document.body.scrollTo) {
            document.body.scrollTo({ left: targetX, top: 0, behavior: 'smooth' });
          } else {
            window.scrollTo({ left: targetX, top: 0, behavior: 'smooth' });
          }
          return { handled: true, page: curr + 1, total: pages };
        }
        return { handled: false, page: curr, total: pages };
      })();
    """

    webView.evaluateJavaScript(js) { [weak self] result, _ in
      guard let self = self else { return }
      if let dict = result as? [String: Any],
        let handled = dict["handled"] as? Bool
      {
        if handled, let page = dict["page"] as? Int {
          self.currentPage = page
        } else {
          onChapterEnd()
        }
      } else {
        onChapterEnd()
      }
    }
  }

  func previousPage(onChapterStart: @escaping () -> Void) {
    guard let webView = webView else { return }

    if readingMode == .scroll {
      webView.evaluateJavaScript("window.scrollBy({ top: -window.innerHeight * 0.85, behavior: 'smooth' });")
      return
    }

    let js = """
      (function() {
        var winW = window.innerWidth || 390;
        var scrollW = document.body.scrollWidth || document.documentElement.scrollWidth || winW;
        var pages = Math.max(1, Math.round(scrollW / winW));
        var currX = document.body.scrollLeft || window.scrollX || 0;
        var curr = Math.min(pages, Math.max(1, Math.round(currX / winW) + 1));
        if (curr > 1) {
          var targetX = (curr - 2) * winW;
          if (document.body.scrollTo) {
            document.body.scrollTo({ left: targetX, top: 0, behavior: 'smooth' });
          } else {
            window.scrollTo({ left: targetX, top: 0, behavior: 'smooth' });
          }
          return { handled: true, page: curr - 1, total: pages };
        }
        return { handled: false, page: curr, total: pages };
      })();
    """

    webView.evaluateJavaScript(js) { [weak self] result, _ in
      guard let self = self else { return }
      if let dict = result as? [String: Any],
        let handled = dict["handled"] as? Bool
      {
        if handled, let page = dict["page"] as? Int {
          self.currentPage = page
        } else {
          onChapterStart()
        }
      } else {
        onChapterStart()
      }
    }
  }

  // MARK: - Helpers

  private func fontFamilyCSS(for fontName: String) -> String {
    switch fontName.lowercased() {
    case "serif":
      return "Charter, Georgia, 'Times New Roman', serif"
    case "sans", "system":
      return "-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Helvetica Neue', sans-serif"
    case "mono", "monospace":
      return "ui-monospace, Menlo, Monaco, 'Courier New', monospace"
    case "round", "rounded":
      return "-apple-system-rounded, 'SF Pro Rounded', 'Avenir', sans-serif"
    default:
      return "'\(fontName)', Charter, -apple-system, serif"
    }
  }

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

// MARK: - Main EPUB Reader View
struct EpubReaderView: View {
  let bookDir: URL
  let theme: AppTheme
  let fontSize: Double
  var bookTitle: String = ""
  var onProgressChanged: ((Double) -> Void)? = nil

  @StateObject private var controller: EpubReaderController
  @State private var chapterPaths: [String] = []
  @State private var currentChapterIndex: Int = 0
  @State private var isShowingTOC: Bool = false
  @State private var showHUD: Bool = true

  init(
    bookDir: URL,
    theme: AppTheme = .default,
    fontSize: Double = 19.0,
    bookTitle: String = "",
    onProgressChanged: ((Double) -> Void)? = nil
  ) {
    self.bookDir = bookDir
    self.theme = theme
    self.fontSize = fontSize
    self.bookTitle = bookTitle
    self.onProgressChanged = onProgressChanged
    _controller = StateObject(wrappedValue: EpubReaderController(bookDir: bookDir, initialMode: .scroll))
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      theme.backgroundColor
        .ignoresSafeArea()

      // Core WebKit Canvas
      if let webView = controller.webView {
        WebViewContainer(webView: webView)
          .edgesIgnoringSafeArea(.all)
          .opacity(controller.isLoading ? 0 : 1)
          .animation(.easeInOut(duration: 0.25), value: controller.isLoading)
      }

      // In Paginated Mode, horizontal edge tap strips
      if controller.readingMode == .paginated {
        HStack(spacing: 0) {
          Color.clear
            .frame(width: 60)
            .contentShape(Rectangle())
            .onTapGesture {
              controller.previousPage {
                if currentChapterIndex > 0 {
                  currentChapterIndex -= 1
                  controller.scrollToChapter(index: currentChapterIndex)
                }
              }
            }

          Spacer()

          Color.clear
            .frame(width: 60)
            .contentShape(Rectangle())
            .onTapGesture {
              controller.nextPage {
                if currentChapterIndex < chapterPaths.count - 1 {
                  currentChapterIndex += 1
                  controller.scrollToChapter(index: currentChapterIndex)
                }
              }
            }
        }
        .ignoresSafeArea()
      }

      // Interactive Modern Loader Animation
      if controller.isLoading {
        InteractiveReaderLoaderView(
          bookTitle: bookTitle,
          chapterTitle: currentChapterDisplayName,
          theme: theme,
          onSkip: {
            withAnimation(.easeOut(duration: 0.2)) {
              controller.isLoading = false
            }
          }
        )
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .zIndex(10)
      }

      // HUD Bottom Navigation Pill
      if showHUD && !controller.isLoading && !chapterPaths.isEmpty {
        VStack(spacing: 0) {
          Spacer()

          HStack(spacing: DS.Spacing.md) {
            // Previous Chapter Button
            Button(action: { controller.scrollToPreviousChapter() }) {
              Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(theme.textColor)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(
                  Circle()
                    .stroke(theme.textColor.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Spacer()

            // TOC & Chapter Indicator
            Button(action: { isShowingTOC = true }) {
              HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "list.bullet")
                  .font(.caption2.weight(.bold))

                VStack(spacing: 1) {
                  Text("Chapter \(controller.currentChapterIndex + 1) of \(chapterPaths.count)")
                    .font(.caption.weight(.semibold))

                  if controller.readingMode == .paginated {
                    Text("Page \(controller.currentPage) of \(controller.totalPages)")
                      .font(.caption2)
                      .foregroundColor(theme.textColor.opacity(0.7))
                  } else {
                    let pct = Int(controller.scrollPercentage * 100)
                    Text("Continuous • \(pct)%")
                      .font(.caption2)
                      .foregroundColor(theme.textColor.opacity(0.7))
                  }
                }
              }
              .foregroundColor(theme.textColor)
              .padding(.horizontal, DS.Spacing.lg)
              .padding(.vertical, DS.Spacing.sm)
              .background(.ultraThinMaterial)
              .cornerRadius(22)
              .overlay(
                RoundedRectangle(cornerRadius: 22)
                  .stroke(theme.textColor.opacity(0.12), lineWidth: 1)
              )
            }
            .buttonStyle(.plain)

            Spacer()

            // Reading Mode Switcher (Pages vs Scroll)
            Button(action: toggleReadingMode) {
              Image(systemName: controller.readingMode.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(theme.textColor)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(
                  Circle()
                    .stroke(theme.textColor.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // Next Chapter Button
            Button(action: { controller.scrollToNextChapter() }) {
              Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(theme.textColor)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(
                  Circle()
                    .stroke(theme.textColor.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
          }
          .padding(.horizontal, DS.Spacing.xl)
          .padding(.bottom, DS.Spacing.xl)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .zIndex(5)
      }
    }
    .sheet(isPresented: $isShowingTOC) {
      ChapterListView(
        bookDir: bookDir,
        chapterPaths: chapterPaths,
        isPresented: $isShowingTOC
      ) { selectedPath in
        if let index = chapterPaths.firstIndex(where: {
          $0 == selectedPath || $0.hasSuffix(selectedPath) || selectedPath.hasSuffix($0)
        }) {
          currentChapterIndex = index
          controller.scrollToChapter(index: index)
        }
      }
    }
    .task {
      setupAndLoad()
    }
    .onChange(of: theme.style) { _, _ in
      controller.updateThemeAndFont(theme: theme, fontSize: fontSize)
    }
    .onChange(of: theme.isDarkMode) { _, _ in
      controller.updateThemeAndFont(theme: theme, fontSize: fontSize)
    }
    .onChange(of: fontSize) { _, newSize in
      controller.updateThemeAndFont(theme: theme, fontSize: newSize)
    }
  }

  // MARK: - Setup and Initialization

  private func setupAndLoad() {
    let webView = WebKitWarmer.shared.createWebView(allowFileAccess: true)
    controller.attach(webView: webView)

    controller.onTapRecognized = {
      withAnimation(.easeInOut(duration: 0.2)) {
        self.showHUD.toggle()
      }
    }

    controller.onProgressUpdated = { progress in
      self.onProgressChanged?(progress)
    }

    controller.onChapterChanged = { idx in
      self.currentChapterIndex = idx
    }

    Task {
      var paths = await resolveChapterPaths(bookDir: bookDir)
      if paths.isEmpty && (bookTitle.contains("Alice") || bookTitle.contains("Wonderland")) {
        BookService.shared.populateAliceEPUB(at: bookDir)
        paths = await resolveChapterPaths(bookDir: bookDir)
      }
      await MainActor.run {
        self.chapterPaths = paths
        if !paths.isEmpty {
          self.controller.configureBook(
            chapterPaths: paths,
            bookTitle: self.bookTitle,
            theme: self.theme,
            fontSize: self.fontSize
          )
        } else {
          self.controller.isLoading = false
          self.controller.errorMessage = "No readable chapters found."
        }
      }
    }
  }

  private var currentChapterDisplayName: String {
    guard currentChapterIndex < chapterPaths.count else { return "Reading EPUB..." }
    let rawPath = chapterPaths[currentChapterIndex]
    let name = URL(fileURLWithPath: rawPath).deletingPathExtension().lastPathComponent
    let cleaned = name.replacingOccurrences(of: "_", with: " ")
      .replacingOccurrences(of: "-", with: " ")
      .capitalized
    return cleaned.isEmpty ? "Chapter \(currentChapterIndex + 1)" : cleaned
  }

  private func toggleReadingMode() {
    let next: EpubReadingMode = (controller.readingMode == .paginated) ? .scroll : .paginated
    controller.setReadingMode(next)
  }

  // MARK: - Robust Chapter Path Resolution

  private func resolveChapterPaths(bookDir: URL) async -> [String] {
    await Task.detached(priority: .userInitiated) { () -> [String] in
      let fileManager = FileManager.default

      // 1. Try spine.json
      let spineURL = bookDir.appendingPathComponent("spine.json")
      if let data = try? Data(contentsOf: spineURL),
        let relativePaths = try? JSONDecoder().decode([String].self, from: data),
        !relativePaths.isEmpty
      {
        let fullPaths = relativePaths.compactMap { rel -> String? in
          let clean = (rel.components(separatedBy: "#").first ?? rel).removingPercentEncoding ?? rel
          let url = bookDir.appendingPathComponent(clean).standardizedFileURL
          if fileManager.fileExists(atPath: url.path) {
            return url.path
          }
          let filename = (clean as NSString).lastPathComponent
          let altURL = bookDir.appendingPathComponent(filename)
          if fileManager.fileExists(atPath: altURL.path) {
            return altURL.path
          }
          return nil
        }
        if !fullPaths.isEmpty {
          return fullPaths
        }
      }

      // 2. Fallback: Search bookDir recursively for .xhtml / .html files
      if let enumerator = fileManager.enumerator(
        at: bookDir,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      ) {
        var found: [URL] = []
        while let nextObj = enumerator.nextObject() {
          guard let fileURL = nextObj as? URL else { continue }
          let ext = fileURL.pathExtension.lowercased()
          let name = fileURL.lastPathComponent.lowercased()
          if (ext == "xhtml" || ext == "html" || ext == "htm"),
            !name.contains("toc"),
            !name.contains("nav"),
            !name.hasPrefix(".")
          {
            found.append(fileURL)
          }
        }
        let sorted = found.sorted {
          $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        return sorted.map { $0.path }
      }

      return []
    }.value
  }
}

// MARK: - Representable Container for WKWebView
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
