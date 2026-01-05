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
    
    private let theme: AppTheme
    
    init(bookDir: URL, theme: AppTheme = .default, fontSize: Double = 18.0, lineHeight: CGFloat = 1.8) {
        self.bookDir = bookDir
        self.theme = theme
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(theme.adaptiveBackground)
                .ignoresSafeArea()
            
            // WebView Container
            WebViewContainer(webView: webView)
                .edgesIgnoringSafeArea(.all)
            
            if isLoading {
                ProgressView("Loading...")
                    .progressViewStyle(CircularProgressViewStyle(tint: theme.adaptiveText))
            }
            
            // Navigation Overlay
            if !chapterPaths.isEmpty {
                HStack {
                    Button(action: previousChapter) {
                        Image(systemName: "chevron.left")
                    }
                    .foregroundColor(theme.adaptiveText)
                    
                    Spacer()
                    
                    Button(action: { isShowingTOC = true }) {
                        Image(systemName: "list.bullet")
                    }
                    .foregroundColor(theme.adaptiveText)
                    
                    Text("Chapter \(currentChapterIndex + 1) / \(chapterPaths.count)")
                        .font(.caption)
                        .chipStyle()
                }
                
                Spacer()
                
                Button(action: nextChapter) {
                    Image(systemName: "chevron.right")
                    }
                    .foregroundColor(theme.adaptiveText)
                    .opacity(currentChapterIndex < chapterPaths.count - 1 ? 1 : 0.3)
                }
            }
            
            // Table of Contents Sheet
            .sheet(isPresented: $isShowingTOC) {
                VStack(alignment: .top, spacing: 16) {
                    Text("Table of Contents")
                        .font(.headline)
                        .foregroundColor(theme.adaptiveText)
                        .padding()
                    
                    ScrollView {
                        ForEach(0..<chapterPaths.count, id: \.self) { index in
                            Button(action: {
                                currentChapterIndex = index
                            }) {
                                Text("Chapter \(index + 1)")
                                    .font(.subheadline)
                                    .foregroundColor(theme.adaptiveSecondaryText)
                                    .padding(8)
                                    .background(theme.isDarkMode ? .ultraThinMaterial : .ultraThickMaterial)
                                    .cornerRadius(8)
                            }
                            }
                            .background(theme.isDarkMode ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                            .cornerRadius(12)
                    }
                }
                .padding()
                .presentationDetents([.large])
            }
        }
    }
}