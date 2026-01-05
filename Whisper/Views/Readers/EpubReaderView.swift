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
    
    @State private var webView: WKWebView?
    @State private var chapterPaths: [String] = []
    @State private var currentChapterIndex = 0
    @State private var isLoading = true
    @State private var isShowingTOC = false
    
    init(bookDir: URL, theme: AppTheme = .default) {
        self.bookDir = bookDir
        self.theme = theme
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            theme.backgroundColor
                .ignoresSafeArea()
            
            if let webView = webView {
                WebViewContainer(webView: webView)
                    .edgesIgnoringSafeArea(.all)
            }
            
            if isLoading {
                ProgressView("Loading...")
                    .progressViewStyle(CircularProgressViewStyle(tint: theme.textColor))
            }
            
            if !chapterPaths.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Button(action: previousChapter) {
                            Image(systemName: "chevron.left")
                                .padding()
                        }
                        .disabled(currentChapterIndex <= 0)
                        .opacity(currentChapterIndex > 0 ? 1 : 0.3)
                        .foregroundColor(theme.textColor)
                        
                        Spacer()
                        
                        Button(action: { isShowingTOC = true }) {
                            HStack {
                                Image(systemName: "list.bullet")
                                Text("Chapter \(currentChapterIndex + 1) / \(chapterPaths.count)")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                        }
                        .foregroundColor(theme.textColor)
                        
                        Spacer()
                        
                        Button(action: nextChapter) {
                            Image(systemName: "chevron.right")
                                .padding()
                        }
                        .disabled(currentChapterIndex >= chapterPaths.count - 1)
                        .opacity(currentChapterIndex < chapterPaths.count - 1 ? 1 : 0.3)
                        .foregroundColor(theme.textColor)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
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
        self.webView = WebKitWarmer.shared.createWebView()
    }
    
    private func previousChapter() {
        guard currentChapterIndex > 0 else { return }
        currentChapterIndex -= 1
    }
    
    private func nextChapter() {
        guard currentChapterIndex < chapterPaths.count - 1 else { return }
        currentChapterIndex += 1
    }
    
    private func loadEpubAsync() async {
        isLoading = true
        
        print("EpubReader: bookDir = \(bookDir.path)")
        
        let paths = await Task.detached(priority: .userInitiated) { [bookDir] () -> [String] in
            let spineURL = bookDir.appendingPathComponent("spine.json")
            print("EpubReader: Looking for spine at \(spineURL.path)")
            print("EpubReader: spine.json exists? \(FileManager.default.fileExists(atPath: spineURL.path))")
            
            // List contents of bookDir for debugging
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: bookDir.path) {
                print("EpubReader: bookDir contents: \(contents)")
            }
            
            guard let data = try? Data(contentsOf: spineURL) else {
                print("EpubReader: Failed to read spine.json data")
                return []
            }
            
            guard let relativePaths = try? JSONDecoder().decode([String].self, from: data) else {
                print("EpubReader: Failed to decode spine.json")
                print("EpubReader: Raw data: \(String(data: data, encoding: .utf8) ?? "nil")")
                return []
            }
            
            print("EpubReader: Decoded \(relativePaths.count) paths from spine.json")
            if let first = relativePaths.first {
                print("EpubReader: First path: \(first)")
            }
            
            return relativePaths.map { relativePath in
                let fullPath = bookDir.appendingPathComponent(relativePath).path
                let exists = FileManager.default.fileExists(atPath: fullPath)
                print("EpubReader: \(relativePath) -> exists: \(exists)")
                return fullPath
            }
        }.value
        
        chapterPaths = paths
        print("EpubReader: Final chapterPaths count: \(chapterPaths.count)")
        
        if !chapterPaths.isEmpty {
            loadChapter(at: 0)
        } else {
            print("EpubReader: ERROR - No chapters loaded!")
        }
        
        isLoading = false
    }
    
    private func loadChapter(at index: Int) {
        guard index >= 0, index < chapterPaths.count, let webView = webView else {
            print("EpubReader: loadChapter guard failed - index:\(index), paths:\(chapterPaths.count), webView:\(webView != nil)")
            return
        }
        
        let chapterPath = chapterPaths[index]
        let chapterURL = URL(fileURLWithPath: chapterPath)
        
        print("EpubReader: Loading chapter \(index) from \(chapterURL.path)")
        print("EpubReader: allowingReadAccessTo: \(bookDir.path)")
        
        webView.loadFileURL(chapterURL, allowingReadAccessTo: bookDir)
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
