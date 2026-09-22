//
//  WebKitWarmer.swift
//  Whisper
//
//  Created by Anurag Ambuj on 05/01/26.
//

import WebKit

@MainActor
final class WebKitWarmer {
  static let shared = WebKitWarmer()

  private var warmedWebView: WKWebView?
  private var isWarmed = false

  private init() {}

  func prewarm() {
    guard !isWarmed else { return }
    isWarmed = true

    let config = WKWebViewConfiguration()
    config.preferences.isTextInteractionEnabled = true
    config.defaultWebpagePreferences.allowsContentJavaScript = true

    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
    webView.loadHTMLString("<html><body></body></html>", baseURL: nil)

    warmedWebView = webView

    print("WebKit: Pre-warming complete")
  }

  func createWebView(allowFileAccess: Bool = false) -> WKWebView {
    let webView: WKWebView

    if let warmed = warmedWebView {
      warmedWebView = nil
      webView = warmed
    } else {
      let config = WKWebViewConfiguration()
      config.preferences.isTextInteractionEnabled = true
      config.defaultWebpagePreferences.allowsContentJavaScript = true
      config.suppressesIncrementalRendering = false
      webView = WKWebView(frame: .zero, configuration: config)
    }

    #if os(iOS)
      webView.isOpaque = false
      webView.backgroundColor = .clear
      webView.scrollView.backgroundColor = .clear
      webView.scrollView.showsHorizontalScrollIndicator = false
      webView.scrollView.showsVerticalScrollIndicator = false
      webView.scrollView.contentInsetAdjustmentBehavior = .never
      webView.scrollView.minimumZoomScale = 1.0
      webView.scrollView.maximumZoomScale = 4.0
      webView.scrollView.bounces = true
    #else
      webView.setValue(false, forKey: "drawsBackground")
      webView.allowsMagnification = true
    #endif

    return webView
  }
}
