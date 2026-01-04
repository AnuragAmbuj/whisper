//
//  ComicReaderView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI

/// Cross-platform comic book reader view
/// Supports both extracted comic directories and mock asset images
struct ComicReaderView: View {
    let bookDir: URL?
    let mockImages: [String]  // For backwards compatibility with sample data
    @Binding var currentPage: Int
    
    @State private var pageURLs: [URL] = []
    @State private var isLoading = true
    
    init(bookDir: URL?, mockImages: [String] = [], currentPage: Binding<Int>) {
        self.bookDir = bookDir
        self.mockImages = mockImages
        self._currentPage = currentPage
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if isLoading {
                ProgressView("Loading pages...")
                    .foregroundColor(.white)
            } else if !pageURLs.isEmpty {
                // Real comic pages from extracted directory
                #if os(iOS)
                TabView(selection: $currentPage) {
                    ForEach(0..<pageURLs.count, id: \.self) { index in
                        ComicPageView(url: pageURLs[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                #else
                // macOS: Use custom pager
                ComicPagerView(pageURLs: pageURLs, currentPage: $currentPage)
                #endif
            } else if !mockImages.isEmpty {
                // Mock images from assets (backwards compatibility)
                #if os(iOS)
                TabView(selection: $currentPage) {
                    ForEach(0..<mockImages.count, id: \.self) { index in
                        Image(mockImages[index])
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .tag(index)
                            .pinchToZoom()
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                #else
                ComicAssetPagerView(images: mockImages, currentPage: $currentPage)
                #endif
            } else {
                // Empty state
                VStack(spacing: DS.Spacing.lg) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    Text("No pages available")
                        .foregroundColor(.gray)
                }
            }
            
            // Page indicator overlay
            if !pageURLs.isEmpty || !mockImages.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(currentPage + 1) / \(max(pageURLs.count, mockImages.count))")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.xs)
                            .background(.ultraThinMaterial)
                            .cornerRadius(DS.Radius.sm)
                        Spacer()
                    }
                    .padding(.bottom, DS.Spacing.xxl)
                }
            }
        }
        .onAppear {
            loadPages()
        }
    }
    
    private func loadPages() {
        guard let dir = bookDir else {
            isLoading = false
            return
        }
        
        // Load pages from comic directory
        pageURLs = ComicParser.shared.getPages(from: dir)
        isLoading = false
    }
}

// MARK: - Comic Page View (loads image from URL)

struct ComicPageView: View {
    let url: URL
    @State private var image: Image?
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        Group {
            if let image = image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = value
                            }
                            .onEnded { _ in
                                withAnimation {
                                    scale = 1.0
                                }
                            }
                    )
            } else {
                ProgressView()
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        DispatchQueue.global(qos: .userInitiated).async {
            #if canImport(UIKit)
            if let uiImage = UIImage(contentsOfFile: url.path) {
                DispatchQueue.main.async {
                    self.image = Image(uiImage: uiImage)
                }
            }
            #elseif canImport(AppKit)
            if let nsImage = NSImage(contentsOfFile: url.path) {
                DispatchQueue.main.async {
                    self.image = Image(nsImage: nsImage)
                }
            }
            #endif
        }
    }
}

// MARK: - macOS Pager Views

#if os(macOS)
struct ComicPagerView: View {
    let pageURLs: [URL]
    @Binding var currentPage: Int
    
    var body: some View {
        ZStack {
            if currentPage < pageURLs.count {
                ComicPageView(url: pageURLs[currentPage])
            }
            
            // Navigation buttons
            HStack {
                Button(action: previousPage) {
                    Image(systemName: "chevron.left")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .disabled(currentPage <= 0)
                .opacity(currentPage <= 0 ? 0.3 : 1)
                
                Spacer()
                
                Button(action: nextPage) {
                    Image(systemName: "chevron.right")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .disabled(currentPage >= pageURLs.count - 1)
                .opacity(currentPage >= pageURLs.count - 1 ? 0.3 : 1)
            }
            .padding()
        }
    }
    
    private func nextPage() {
        if currentPage < pageURLs.count - 1 {
            currentPage += 1
        }
    }
    
    private func previousPage() {
        if currentPage > 0 {
            currentPage -= 1
        }
    }
}

struct ComicAssetPagerView: View {
    let images: [String]
    @Binding var currentPage: Int
    
    var body: some View {
        ZStack {
            if currentPage < images.count {
                Image(images[currentPage])
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            
            HStack {
                Button(action: { if currentPage > 0 { currentPage -= 1 } }) {
                    Image(systemName: "chevron.left")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .disabled(currentPage <= 0)
                .opacity(currentPage <= 0 ? 0.3 : 1)
                
                Spacer()
                
                Button(action: { if currentPage < images.count - 1 { currentPage += 1 } }) {
                    Image(systemName: "chevron.right")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .disabled(currentPage >= images.count - 1)
                .opacity(currentPage >= images.count - 1 ? 0.3 : 1)
            }
            .padding()
        }
    }
}
#endif

// MARK: - Pinch to Zoom Modifier

extension View {
    func pinchToZoom() -> some View {
        self.modifier(PinchToZoom())
    }
}

struct PinchToZoom: ViewModifier {
    @State private var scale: CGFloat = 1.0
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = value
                    }
                    .onEnded { _ in
                        withAnimation(.easeInOut(duration: DS.Animation.normal)) {
                            scale = 1.0
                        }
                    }
            )
    }
}
