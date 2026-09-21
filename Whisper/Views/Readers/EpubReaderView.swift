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
  @Published var scrollPercentage: Double = 0.0
  @Published var readingMode: EpubReadingMode = .paginated
  @Published var errorMessage: String? = nil

  var webView: WKWebView?
  private(set) var bookDir: URL
  private var currentChapterURL: URL?
  private var watchdogTask: Task<Void, Never>?

  var onProgressUpdated: ((Double) -> Void)?
  var onTapRecognized: (() -> Void)?

  init(bookDir: URL) {
    self.bookDir = bookDir
    super.init()
  }

  func attach(webView: WKWebView) {
    self.webView = webView
    webView.navigationDelegate = self

    webView.configuration.userContentController.removeScriptMessageHandler(forName: "whisperTap")
    webView.configuration.userContentController.add(WeakScriptMessageHandler(delegate: self), name: "whisperTap")

    webView.configuration.userContentController.removeScriptMessageHandler(forName: "whisperProgress")
    webView.configuration.userContentController.add(WeakScriptMessageHandler(delegate: self), name: "whisperProgress")

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

  func loadChapter(at url: URL, theme: AppTheme, fontSize: Double) {
    guard let webView = webView else { return }
    currentChapterURL = url
    isLoading = true
    currentPage = 1
    totalPages = 1
    errorMessage = nil

    // 3-second safety watchdog ensures loader never hangs indefinitely
    watchdogTask?.cancel()
    watchdogTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 3_000_000_000)
      guard let self = self, self.isLoading else { return }
      print("EpubReaderController: Safety timeout reached, force-revealing content")
      self.injectReaderCSS(theme: theme, fontSize: fontSize)
      self.isLoading = false
    }

    if FileManager.default.fileExists(atPath: url.path) {
      webView.loadFileURL(url, allowingReadAccessTo: bookDir)
    } else {
      // Direct string fallback if file path resolution differs
      if let content = try? String(contentsOf: url, encoding: .utf8) {
        webView.loadHTMLString(content, baseURL: url.deletingLastPathComponent())
      } else {
        isLoading = false
        errorMessage = "Unable to open chapter at: \(url.lastPathComponent)"
      }
    }
  }

  // MARK: - WKNavigationDelegate

  nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    Task { @MainActor in
      self.watchdogTask?.cancel()
      print("EpubReaderController: Chapter loaded successfully")
      self.injectReaderCSS(theme: self.cachedTheme, fontSize: self.cachedFontSize)
    }
  }

  nonisolated func webView(
    _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
  ) {
    Task { @MainActor in
      self.watchdogTask?.cancel()
      print("EpubReaderController: Navigation failed: \(error.localizedDescription)")
      self.isLoading = false
    }
  }

  nonisolated func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    Task { @MainActor in
      self.watchdogTask?.cancel()
      print("EpubReaderController: Provisional navigation failed: \(error.localizedDescription)")
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
      }
    }
  }

  // MARK: - Script Injection & Styling

  private var cachedTheme: AppTheme = .default
  private var cachedFontSize: Double = 19.0

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
    injectReaderCSS(theme: cachedTheme, fontSize: cachedFontSize)
  }

  func injectReaderCSS(theme: AppTheme, fontSize: Double) {
    guard let webView = webView else { return }

    let bgHex = hexString(from: theme.backgroundColor)
    let textHex = hexString(from: theme.textColor)
    let fontCSS = fontFamilyCSS(for: theme.fontName)

    let isPaged = (readingMode == .paginated)

    let js = """
      (function() {
        // 1. Ensure viewport meta tag exists and enables pinch to zoom
        var meta = document.querySelector('meta[name="viewport"]');
        if (!meta) {
          meta = document.createElement('meta');
          meta.name = 'viewport';
          document.head.appendChild(meta);
        }
        meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes';

        // 2. Remove any prior Whisper styling
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
            \(isPaged ?
              "height: calc(100vh - 100px) !important; width: 100vw !important; padding: 24px 24px 70px 24px !important; column-width: calc(100vw - 48px) !important; column-gap: 48px !important; column-fill: auto !important; overflow-x: scroll !important; overflow-y: hidden !important; scrollbar-width: none !important; -webkit-overflow-scrolling: touch !important;"
              :
              "max-width: 740px !important; margin: 0 auto !important; padding: 32px 24px 140px 24px !important; overflow-x: hidden !important;"
            )
          }

          body::-webkit-scrollbar { display: none !important; }

          /* Preserve natural heading scale & font weights */
          h1, h2, h3, h4, h5, h6 {
            color: var(--whisper-text) !important;
            font-weight: 700 !important;
            line-height: 1.3 !important;
            margin-top: 1.4em !important;
            margin-bottom: 0.6em !important;
            break-after: avoid !important;
            page-break-after: avoid !important;
          }
          h1 { font-size: 1.7em !important; }
          h2 { font-size: 1.4em !important; }
          h3 { font-size: 1.22em !important; }
          h4 { font-size: 1.1em !important; }

          /* Clean paragraph typography */
          p {
            color: var(--whisper-text) !important;
            margin: 0 0 1.15em 0 !important;
            line-height: var(--whisper-line-height) !important;
            -webkit-hyphens: auto;
            hyphens: auto;
            word-break: break-word;
          }

          li, blockquote, dd, dt, figcaption {
            color: var(--whisper-text) !important;
            line-height: var(--whisper-line-height) !important;
          }

          blockquote {
            border-left: 3px solid var(--whisper-text);
            opacity: 0.85;
            margin: 1.2em 0 1.2em 1.2em !important;
            padding-left: 1em !important;
            font-style: italic;
          }

          img, svg, video {
            max-width: 100% !important;
            \(isPaged ? "max-height: calc(100vh - 160px) !important; object-fit: contain !important;" : "height: auto !important;")
            display: block !important;
            margin: 18px auto !important;
            border-radius: 8px !important;
            break-inside: avoid !important;
            page-break-inside: avoid !important;
          }

          table {
            max-width: 100% !important;
            border-collapse: collapse !important;
            margin: 16px 0 !important;
          }

          a {
            color: inherit !important;
            text-decoration: underline !important;
          }
        `;
        document.head.appendChild(style);

        // 4. Install click/tap detection to toggle HUD without blocking scrolling or gestures
        if (!window._whisperTapInstalled) {
          window._whisperTapInstalled = true;
          var touchStartX = 0, touchStartY = 0, touchStartTime = 0;
          window.addEventListener('touchstart', function(e) {
            if (e.touches.length === 1) {
              touchStartX = e.touches[0].clientX;
              touchStartY = e.touches[0].clientY;
              touchStartTime = Date.now();
            }
          }, { passive: true });

          window.addEventListener('touchend', function(e) {
            if (Date.now() - touchStartTime < 350) {
              var touch = e.changedTouches[0];
              var dx = Math.abs(touch.clientX - touchStartX);
              var dy = Math.abs(touch.clientY - touchStartY);
              if (dx < 12 && dy < 12) {
                var target = e.target;
                if (target && (target.tagName === 'A' || target.tagName === 'BUTTON' || target.closest('a'))) {
                  return; // Allow link taps
                }
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.whisperTap) {
                  window.webkit.messageHandlers.whisperTap.postMessage({ x: touch.clientX, y: touch.clientY });
                }
              }
            }
          }, { passive: true });

          window.addEventListener('click', function(e) {
            if (e.target && (e.target.tagName === 'A' || e.target.tagName === 'BUTTON' || e.target.closest('a'))) {
              return;
            }
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.whisperTap) {
              window.webkit.messageHandlers.whisperTap.postMessage({ x: e.clientX, y: e.clientY });
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
        }

        // 5. Calculate metrics for paginated mode
        var winW = window.innerWidth || document.documentElement.clientWidth || 390;
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
      if let error = error {
        print("EpubReaderController: Script evaluation warning: \(error.localizedDescription)")
      } else if let dict = result as? [String: Any] {
        if let total = dict["totalPages"] as? Int {
          self.totalPages = max(1, total)
        }
        if let current = dict["currentPage"] as? Int {
          self.currentPage = max(1, min(self.totalPages, current))
        }
      }
      withAnimation(.easeOut(duration: 0.25)) {
        self.isLoading = false
      }
    }
  }

  // MARK: - Navigation Control

  func nextPage(onChapterEnd: @escaping () -> Void) {
    guard let webView = webView else { return }

    if readingMode == .scroll {
      // Scroll down by 80% viewport
      webView.evaluateJavaScript("window.scrollBy({ top: window.innerHeight * 0.8, behavior: 'smooth' });")
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
      // Scroll up by 80% viewport
      webView.evaluateJavaScript("window.scrollBy({ top: -window.innerHeight * 0.8, behavior: 'smooth' });")
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

      // Tap Zones for Paginated Mode ONLY.
      // In Continuous Scroll Mode, touches pass 100% directly to WKWebView for native touch scrolling & momentum!
      if controller.readingMode == .paginated {
        HStack(spacing: 0) {
          // Left zone: Previous page
          Color.clear
            .frame(width: 80)
            .contentShape(Rectangle())
            .onTapGesture {
              previousPageOrChapter()
            }

          // Center zone: Toggle HUD
          Color.clear
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
              withAnimation(.easeInOut(duration: 0.2)) {
                showHUD.toggle()
              }
            }

          // Right zone: Next page
          Color.clear
            .frame(width: 80)
            .contentShape(Rectangle())
            .onTapGesture {
              nextPageOrChapter()
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
            // Previous Chapter / Page Button
            Button(action: previousPageOrChapter) {
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

            // TOC & Page Indicator
            Button(action: { isShowingTOC = true }) {
              HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "list.bullet")
                  .font(.caption2.weight(.bold))

                VStack(spacing: 1) {
                  Text("Chapter \(currentChapterIndex + 1) of \(chapterPaths.count)")
                    .font(.caption.weight(.semibold))

                  if controller.readingMode == .paginated {
                    Text("Page \(controller.currentPage) of \(controller.totalPages)")
                      .font(.caption2)
                      .foregroundColor(theme.textColor.opacity(0.7))
                  } else {
                    let pct = Int(controller.scrollPercentage * 100)
                    Text("Scroll Mode • \(pct)%")
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

            // Next Chapter / Page Button
            Button(action: nextPageOrChapter) {
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
        }
      }
    }
    .task {
      setupAndLoad()
    }
    .onChange(of: currentChapterIndex) { _, newIndex in
      loadChapter(at: newIndex)
      if !chapterPaths.isEmpty {
        let prog = Double(newIndex) / Double(max(1, chapterPaths.count))
        onProgressChanged?(prog)
      }
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
      if !self.chapterPaths.isEmpty {
        let baseProg = Double(self.currentChapterIndex) / Double(max(1, self.chapterPaths.count))
        let chapterSlice = 1.0 / Double(max(1, self.chapterPaths.count))
        let totalProg = min(1.0, baseProg + (chapterSlice * progress))
        self.onProgressChanged?(totalProg)
      }
    }

    Task {
      let paths = await resolveChapterPaths(bookDir: bookDir)
      await MainActor.run {
        self.chapterPaths = paths
        if !paths.isEmpty {
          self.loadChapter(at: self.currentChapterIndex)
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

  private func loadChapter(at index: Int) {
    guard index >= 0, index < chapterPaths.count else { return }
    let path = chapterPaths[index]
    let url = URL(fileURLWithPath: path)
    controller.loadChapter(at: url, theme: theme, fontSize: fontSize)
  }

  private func toggleReadingMode() {
    let next: EpubReadingMode = (controller.readingMode == .paginated) ? .scroll : .paginated
    controller.setReadingMode(next)
  }

  private func nextPageOrChapter() {
    controller.nextPage {
      if self.currentChapterIndex < self.chapterPaths.count - 1 {
        self.currentChapterIndex += 1
      }
    }
  }

  private func previousPageOrChapter() {
    controller.previousPage {
      if self.currentChapterIndex > 0 {
        self.currentChapterIndex -= 1
      }
    }
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
          // Fallback: check matching last path component
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
