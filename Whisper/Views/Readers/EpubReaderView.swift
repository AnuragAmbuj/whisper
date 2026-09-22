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
  @Published var readingMode: EpubReadingMode = .paginated
  @Published var errorMessage: String? = nil

  var webView: WKWebView?
  private(set) var bookDir: URL
  private var currentLoadedURL: URL?
  private var chapterPaths: [String] = []
  private var continuousBookURL: URL?
  private var watchdogTask: Task<Void, Never>?

  var onProgressUpdated: ((Double) -> Void)?
  var onChapterChanged: ((Int) -> Void)?
  var onTapRecognized: (() -> Void)?

  private var cachedTheme: AppTheme = .default
  private var cachedFontSize: Double = 19.0

  init(bookDir: URL) {
    self.bookDir = bookDir
    super.init()
  }

  func attach(webView: WKWebView) {
    self.webView = webView
    webView.navigationDelegate = self

    let contentController = webView.configuration.userContentController
    contentController.removeScriptMessageHandler(forName: "whisperTap")
    contentController.add(WeakScriptMessageHandler(delegate: self), name: "whisperTap")

    contentController.removeScriptMessageHandler(forName: "whisperProgress")
    contentController.add(WeakScriptMessageHandler(delegate: self), name: "whisperProgress")

    contentController.removeScriptMessageHandler(forName: "whisperChapterChanged")
    contentController.add(WeakScriptMessageHandler(delegate: self), name: "whisperChapterChanged")

    #if os(iOS)
      webView.scrollView.bounces = true
      webView.scrollView.alwaysBounceVertical = (readingMode == .scroll)
      webView.scrollView.showsVerticalScrollIndicator = (readingMode == .scroll)
      webView.scrollView.showsHorizontalScrollIndicator = false
      webView.scrollView.minimumZoomScale = 1.0
      webView.scrollView.maximumZoomScale = 4.0
      webView.scrollView.isScrollEnabled = true
      webView.isUserInteractionEnabled = true
    #else
      webView.allowsMagnification = true
    #endif
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
      let fileURL = await Self.generateContinuousDocument(
        bookDir: bookDir,
        chapterPaths: paths,
        bookTitle: bookTitle
      )
      await MainActor.run {
        self.continuousBookURL = fileURL
        if let fileURL = fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
          self.currentLoadedURL = fileURL
          webView.loadFileURL(fileURL, allowingReadAccessTo: bookDir)
        } else if let first = paths.first {
          let fallbackURL = URL(fileURLWithPath: first)
          self.currentLoadedURL = fallbackURL
          webView.loadFileURL(fallbackURL, allowingReadAccessTo: bookDir)
        } else {
          self.isLoading = false
          self.errorMessage = "Unable to generate continuous reading document."
        }
      }
    }
  }

  func loadChapter(at url: URL, theme: AppTheme, fontSize: Double) {
    guard let webView = webView else { return }
    currentLoadedURL = url
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

    if FileManager.default.fileExists(atPath: url.path) {
      webView.loadFileURL(url, allowingReadAccessTo: bookDir)
    } else if let content = try? String(contentsOf: url, encoding: .utf8) {
      webView.loadHTMLString(content, baseURL: url.deletingLastPathComponent())
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
    _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
  ) {
    Task { @MainActor in
      self.watchdogTask?.cancel()
      self.isLoading = false
    }
  }

  nonisolated func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    Task { @MainActor in
      self.watchdogTask?.cancel()
      self.isLoading = false
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
        webView?.loadFileURL(continuousURL, allowingReadAccessTo: bookDir)
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
              "max-width: 720px !important; margin: 0 auto !important; padding: max(24px, env(safe-area-inset-top, 24px)) max(20px, env(safe-area-inset-right, 20px)) max(140px, env(safe-area-inset-bottom, 140px)) max(20px, env(safe-area-inset-left, 20px)) !important; overflow-x: hidden !important;"
            )
          }

          body::-webkit-scrollbar { display: none !important; }

          .whisper-book-container {
            width: 100%;
          }

          .whisper-chapter {
            margin-bottom: 56px;
            scroll-margin-top: 40px;
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
            font-size: 0.8em;
            font-weight: 600;
            letter-spacing: 0.08em;
            text-transform: uppercase;
            color: var(--whisper-text);
            opacity: 0.75;
            padding: 6px 14px;
            border-radius: 12px;
            border: 1px solid rgba(128, 128, 128, 0.25);
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
            margin: 18px 0 !important;
          }

          a {
            color: inherit !important;
            text-decoration: underline !important;
          }
        `;
        document.head.appendChild(style);

        // 4. Install interaction listeners
        if (!window._whisperListenersInstalled) {
          window._whisperListenersInstalled = true;
          var touchStartX = 0, touchStartY = 0, touchStartTime = 0;

          window.addEventListener('touchstart', function(e) {
            if (e.touches.length === 1) {
              touchStartX = e.touches[0].clientX;
              touchStartY = e.touches[0].clientY;
              touchStartTime = Date.now();
            }
          }, { passive: true });

          window.addEventListener('touchend', function(e) {
            if (Date.now() - touchStartTime < 320) {
              var touch = e.changedTouches[0];
              var dx = Math.abs(touch.clientX - touchStartX);
              var dy = Math.abs(touch.clientY - touchStartY);
              if (dx < 10 && dy < 10) {
                var target = e.target;
                if (target && (target.tagName === 'A' || target.tagName === 'BUTTON' || target.closest('a'))) {
                  return;
                }
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.whisperTap) {
                  window.webkit.messageHandlers.whisperTap.postMessage({});
                }
              }
            }
          }, { passive: true });

          window.addEventListener('click', function(e) {
            if (e.target && (e.target.tagName === 'A' || e.target.tagName === 'BUTTON' || e.target.closest('a'))) {
              return;
            }
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.whisperTap) {
              window.webkit.messageHandlers.whisperTap.postMessage({});
            }
          });

          // Scroll progress tracking
          window.addEventListener('scroll', function() {
            var scrollY = window.scrollY || document.documentElement.scrollTop || document.body.scrollTop || 0;
            var maxScroll = Math.max(1, (document.documentElement.scrollHeight || document.body.scrollHeight || 1) - window.innerHeight);
            var pct = Math.min(1.0, Math.max(0.0, scrollY / maxScroll));
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.whisperProgress) {
              window.webkit.messageHandlers.whisperProgress.postMessage({ progress: pct });
            }
          }, { passive: true });

          // Multi-Chapter Intersection Observer
          if ('IntersectionObserver' in window) {
            var chapterObserver = new IntersectionObserver(function(entries) {
              for (var i = 0; i < entries.length; i++) {
                if (entries[i].isIntersecting) {
                  var target = entries[i].target;
                  var idx = parseInt(target.getAttribute('data-chapter-index'), 10);
                  if (!isNaN(idx) && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.whisperChapterChanged) {
                    window.webkit.messageHandlers.whisperChapterChanged.postMessage({ chapterIndex: idx });
                  }
                }
              }
            }, {
              rootMargin: '-10% 0px -70% 0px',
              threshold: 0
            });

            var chapters = document.querySelectorAll('.whisper-chapter');
            for (var j = 0; j < chapters.length; j++) {
              chapterObserver.observe(chapters[j]);
            }
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
  ) -> URL? {
    let outputURL = bookDir.appendingPathComponent("whisper_continuous_book.html")
    let fileManager = FileManager.default

    var combinedSections: [String] = []

    for (index, path) in chapterPaths.enumerated() {
      let fileURL = URL(fileURLWithPath: path)
      guard let rawContent = try? String(contentsOf: fileURL, encoding: .utf8) ??
            String(contentsOf: fileURL, encoding: .ascii) else {
        continue
      }

      let chapterDirRel = fileURL.deletingLastPathComponent().path
        .replacingOccurrences(of: bookDir.path, with: "")
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

      let chapterTitle = extractTitle(from: rawContent) ?? "Chapter \(index + 1)"
      let bodyContent = extractBody(from: rawContent)
      let resolvedContent = rewriteRelativePaths(html: bodyContent, chapterDir: chapterDirRel)

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

    guard !combinedSections.isEmpty else { return nil }

    let fullHTML = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes">
      <title>\(bookTitle)</title>
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
      return outputURL
    } catch {
      print("EpubReaderController: Failed to write continuous book: \(error.localizedDescription)")
      return nil
    }
  }

  private static func extractBody(from html: String) -> String {
    let pattern = "(?is)<body[^>]*>(.*?)</body>"
    if let regex = try? NSRegularExpression(pattern: pattern),
       let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: html.utf16.count)),
       let range = Range(match.range(at: 1), in: html) {
      return String(html[range])
    }
    // Fallback: strip doctype and html tags
    return html
      .replacingOccurrences(of: "<!DOCTYPE[^>]*>", with: "", options: .regularExpression)
      .replacingOccurrences(of: "<html[^>]*>", with: "", options: .regularExpression)
      .replacingOccurrences(of: "</html>", with: "")
  }

  private static func extractTitle(from html: String) -> String? {
    let patterns = [
      "(?is)<title[^>]*>(.*?)</title>",
      "(?is)<h[1-2][^>]*>(.*?)</h[1-2]>"
    ]
    for pattern in patterns {
      if let regex = try? NSRegularExpression(pattern: pattern),
         let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: html.utf16.count)),
         let range = Range(match.range(at: 1), in: html) {
        let text = String(html[range])
          .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
          .trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
          return text
        }
      }
    }
    return nil
  }

  private static func rewriteRelativePaths(html: String, chapterDir: String) -> String {
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
    _controller = StateObject(wrappedValue: EpubReaderController(bookDir: bookDir))
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

      // In Paginated Mode, horizontal swipe gestures to turn pages
      if controller.readingMode == .paginated {
        HStack(spacing: 0) {
          Color.clear
            .frame(width: 80)
            .contentShape(Rectangle())
            .onTapGesture {
              controller.previousPage {
                if currentChapterIndex > 0 {
                  currentChapterIndex -= 1
                  controller.scrollToChapter(index: currentChapterIndex)
                }
              }
            }

          Color.clear
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
              withAnimation(.easeInOut(duration: 0.2)) {
                showHUD.toggle()
              }
            }

          Color.clear
            .frame(width: 80)
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
                    Text("Continuous \u{2022} \(pct)%")
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
      let paths = await resolveChapterPaths(bookDir: bookDir)
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
          return url.path
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
