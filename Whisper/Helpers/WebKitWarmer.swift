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

  private init() {}

  func prewarm() {
    // No-op: Offscreen unattached webviews trigger IdleExit process terminations
    // and sandbox extension failures on modern iOS.
  }

  func createWebView(allowFileAccess: Bool = false) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.preferences.isTextInteractionEnabled = true
    config.defaultWebpagePreferences.allowsContentJavaScript = true
    config.suppressesIncrementalRendering = false

    let webView = WKWebView(frame: .zero, configuration: config)

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
