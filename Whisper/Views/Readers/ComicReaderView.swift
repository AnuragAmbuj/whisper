//
//  ComicReaderView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 19/09/26.
//

import SwiftUI

enum ComicReadingMode: String, CaseIterable, Identifiable {
    case paged = "Paged"
    case continuous = "Continuous"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .paged: return "book.pages"
        case .continuous: return "scroll"
        }
    }
}

enum ComicPageSource: Identifiable, Hashable {
    case url(URL)
    case mock(String)
    
    var id: String {
        switch self {
        case .url(let url): return url.path
        case .mock(let name): return name
        }
    }
}

struct ComicReaderView: View {
    let bookDir: URL?
    var mockImages: [String] = []
    @Binding var currentPage: Int
    @Binding var totalPages: Int
    
    @State private var pageURLs: [URL] = []
    @State private var readingMode: ComicReadingMode = .paged
    @State private var enableFocalHighlight: Bool = true
    @State private var showControls = true
    @State private var isLoading = true
    
    private var pages: [ComicPageSource] {
        if !pageURLs.isEmpty {
            return pageURLs.map { .url($0) }
        } else if !mockImages.isEmpty {
            return mockImages.map { .mock($0) }
        }
        return []
    }
    
    private var effectiveTotalPages: Int {
        max(1, pages.count)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if isLoading {
                VStack(spacing: DS.Spacing.md) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                    Text("Loading comic pages...")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                }
            } else if !pages.isEmpty {
                if readingMode == .paged {
                    #if os(iOS)
                    TabView(selection: $currentPage) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            ComicPageItemView(page: pages[index], isWebtoonFit: false)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: DS.Animation.fast)) {
                            showControls.toggle()
                        }
                    }
                    #else
                    // macOS: Custom pager with full keyboard shortcuts, click zones, and caching
                    ComicPagerView(
                        pages: pages,
                        currentPage: $currentPage,
                        showControls: $showControls
                    )
                    #endif
                } else {
                    // Continuous Vertical Scroll (Webtoon / Manga style) with Smart Focal Highlighting & Auto-Zoom
                    ComicContinuousScrollView(
                        pages: pages,
                        currentPage: $currentPage,
                        enableFocalHighlight: enableFocalHighlight,
                        onTap: {
                            withAnimation(.easeInOut(duration: DS.Animation.fast)) {
                                showControls.toggle()
                            }
                        }
                    )
                }
            } else {
                // Empty state
                VStack(spacing: DS.Spacing.lg) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 56))
                        .foregroundColor(.secondary)
                    Text("No Comic Pages Found")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    Text("Could not find readable images in this comic archive.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Spacing.xl)
                }
            }
            
            // Bottom Scrubber & Controls Overlay (Apple Minimal High-Contrast)
            if !pages.isEmpty && showControls {
                VStack {
                    Spacer()
                    bottomControlBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .padding(.bottom, DS.Spacing.xl)
                .ignoresSafeArea(.keyboard)
            }
        }
        .onAppear {
            loadPages()
        }
    }
    
    // MARK: - Bottom Control Bar (Minimal & High Contrast)
    private var bottomControlBar: some View {
        VStack(spacing: DS.Spacing.sm) {
            // Top row: Page scrubber slider and quick navigation buttons
            HStack(spacing: DS.Spacing.md) {
                Button(action: {
                    if currentPage > 0 { currentPage -= 1 }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .foregroundColor(currentPage > 0 ? .white : .white.opacity(0.3))
                }
                .disabled(currentPage <= 0)
                .buttonStyle(.plain)
                
                // Slider
                Slider(
                    value: Binding(
                        get: { Double(currentPage) },
                        set: { currentPage = Int($0) }
                    ),
                    in: 0...Double(max(0, effectiveTotalPages - 1)),
                    step: 1
                )
                .tint(.white)
                
                Button(action: {
                    if currentPage < effectiveTotalPages - 1 { currentPage += 1 }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .foregroundColor(currentPage < effectiveTotalPages - 1 ? .white : .white.opacity(0.3))
                }
                .disabled(currentPage >= effectiveTotalPages - 1)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DS.Spacing.md)
            
            // Bottom row: Page label & Action toggles
            HStack(spacing: DS.Spacing.sm) {
                Text("Page \(currentPage + 1) of \(effectiveTotalPages)")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.9))
                
                Spacer()
                
                // Focal Highlight & Auto-Zoom Toggle (in Continuous Webtoon Mode)
                if readingMode == .continuous {
                    Button(action: {
                        withAnimation(.easeInOut(duration: DS.Animation.fast)) {
                            enableFocalHighlight.toggle()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: enableFocalHighlight ? "viewfinder.circle.fill" : "viewfinder.circle")
                            Text(enableFocalHighlight ? "Focal Zoom" : "Uniform")
                        }
                        .font(.caption2.bold())
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(enableFocalHighlight ? Color.white : Color.white.opacity(0.12))
                        .foregroundColor(enableFocalHighlight ? Color.black : .white.opacity(0.85))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                
                // Mode Toggle Button (Paged vs Continuous)
                Button(action: {
                    withAnimation(.easeInOut(duration: DS.Animation.fast)) {
                        readingMode = (readingMode == .paged) ? .continuous : .paged
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: readingMode.iconName)
                        Text(readingMode == .paged ? "Webtoon Mode" : "Page Mode")
                    }
                    .font(.caption2.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.18))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DS.Spacing.md)
        }
        .padding(.vertical, DS.Spacing.md)
        .padding(.horizontal, DS.Spacing.sm)
        .frame(maxWidth: 480)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Colors.border, lineWidth: 1)
        )
    }
    
    private func loadPages() {
        guard let dir = bookDir else {
            isLoading = false
            if !mockImages.isEmpty {
                totalPages = mockImages.count
            }
            return
        }
        
        let loaded = ComicParser.shared.getPages(from: dir)
        pageURLs = loaded
        if !loaded.isEmpty {
            totalPages = loaded.count
        } else if !mockImages.isEmpty {
            totalPages = mockImages.count
        }
        isLoading = false
    }
}

// MARK: - Comic Page Position for Focal Tracking

struct WebtoonPagePos: Equatable {
    let index: Int
    let midY: CGFloat
}

struct WebtoonPagePositionPreferenceKey: PreferenceKey {
    static var defaultValue: [WebtoonPagePos] = []
    static func reduce(value: inout [WebtoonPagePos], nextValue: () -> [WebtoonPagePos]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - Comic Continuous Scroll View (Webtoon Style with Frictionless Scrolling & Smart Focal Zoom)

struct ComicContinuousScrollView: View {
    let pages: [ComicPageSource]
    @Binding var currentPage: Int
    var enableFocalHighlight: Bool = true
    var onTap: () -> Void
    
    @State private var lastReportedPage: Int = -1
    @State private var webtoonZoomScale: CGFloat = 1.0
    @State private var liveMagnification: CGFloat = 1.0
    
    init(pages: [ComicPageSource], currentPage: Binding<Int>, enableFocalHighlight: Bool = true, onTap: @escaping () -> Void) {
        self.pages = pages
        self._currentPage = currentPage
        self.enableFocalHighlight = enableFocalHighlight
        self.onTap = onTap
    }
    
    init(pageURLs: [URL], currentPage: Binding<Int>, enableFocalHighlight: Bool = true, onTap: @escaping () -> Void) {
        self.pages = pageURLs.map { .url($0) }
        self._currentPage = currentPage
        self.enableFocalHighlight = enableFocalHighlight
        self.onTap = onTap
    }
    
    var body: some View {
        GeometryReader { outerGeo in
            let viewportHeight = outerGeo.size.height
            let viewportCenterY = viewportHeight / 2
            
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 6) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            ComicPageItemView(
                                page: pages[index],
                                isWebtoonFit: true,
                                onTap: onTap,
                                onDoubleTap: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        if webtoonZoomScale > 1.05 {
                                            webtoonZoomScale = 1.0
                                        } else {
                                            webtoonZoomScale = 1.75
                                        }
                                        liveMagnification = 1.0
                                    }
                                }
                            )
                            .id(index)
                            .modifier(
                                WebtoonFocalHighlightModifier(
                                    isFocal: (index == currentPage),
                                    enableFocalHighlight: enableFocalHighlight
                                )
                            )
                            .background(
                                GeometryReader { itemGeo in
                                    let itemMidY = itemGeo.frame(in: .named("webtoonScrollCoordinate")).midY
                                    Color.clear.preference(
                                        key: WebtoonPagePositionPreferenceKey.self,
                                        value: [
                                            WebtoonPagePos(
                                                index: index,
                                                midY: itemMidY
                                            )
                                        ]
                                    )
                                }
                            )
                        }
                    }
                    .scaleEffect(webtoonZoomScale * liveMagnification, anchor: .center)
                    .padding(.vertical, DS.Spacing.md)
                }
                .coordinateSpace(name: "webtoonScrollCoordinate")
                .gesture(
                    MagnificationGesture()
                        .onChanged { val in
                            liveMagnification = val
                        }
                        .onEnded { val in
                            let target = min(max(webtoonZoomScale * val, 1.0), 3.0)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                webtoonZoomScale = target
                                liveMagnification = 1.0
                            }
                        }
                )
                .onPreferenceChange(WebtoonPagePositionPreferenceKey.self) { positions in
                    // Find the page whose center is closest to the viewport's center
                    guard !positions.isEmpty else { return }
                    let closest = positions.min { a, b in
                        abs(a.midY - viewportCenterY) < abs(b.midY - viewportCenterY)
                    }
                    if let closest = closest, closest.index != currentPage {
                        lastReportedPage = closest.index
                        currentPage = closest.index
                    }
                }
                .onChange(of: currentPage) { _, newPage in
                    // Only perform programmatic scroll if the change came from outside (slider or shortcut),
                    // avoiding the feedback loop that fights user manual scrolling.
                    if newPage != lastReportedPage {
                        lastReportedPage = newPage
                        withAnimation(.easeInOut(duration: DS.Animation.fast)) {
                            proxy.scrollTo(newPage, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Smart Focal Highlighting & Dynamic Magnification Modifier

struct WebtoonFocalHighlightModifier: ViewModifier {
    var viewportHeight: CGFloat = 0
    var viewportCenterY: CGFloat = 0
    var isFocal: Bool = false
    var enableFocalHighlight: Bool = true
    
    init(isFocal: Bool, enableFocalHighlight: Bool = true) {
        self.isFocal = isFocal
        self.enableFocalHighlight = enableFocalHighlight
    }
    
    init(viewportHeight: CGFloat = 0, viewportCenterY: CGFloat = 0, isFocal: Bool = false, enableFocalHighlight: Bool = true) {
        self.viewportHeight = viewportHeight
        self.viewportCenterY = viewportCenterY
        self.isFocal = isFocal
        self.enableFocalHighlight = enableFocalHighlight
    }
    
    func body(content: Content) -> some View {
        if enableFocalHighlight {
            content
                .overlay(
                    Color.black.opacity(isFocal ? 0.0 : 0.15)
                        .allowsHitTesting(false)
                )
                .scaleEffect(isFocal ? 1.04 : 1.0)
                .zIndex(isFocal ? 1 : 0)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isFocal)
        } else {
            content
        }
    }
}

// MARK: - Comic Page Item View (Handles both disk URLs and asset mock images)

struct ComicPageItemView: View {
    let page: ComicPageSource
    var isWebtoonFit: Bool = false
    var onTap: (() -> Void)? = nil
    var onDoubleTap: (() -> Void)? = nil
    
    var body: some View {
        Group {
            switch page {
            case .url(let url):
                ComicPageView(url: url, isWebtoonFit: isWebtoonFit)
            case .mock(let assetName):
                #if canImport(UIKit)
                let img = Image(assetName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: isWebtoonFit ? .infinity : nil)
                if isWebtoonFit {
                    img
                } else {
                    img.pinchToZoom()
                }
                #elseif canImport(AppKit)
                let img = Image(assetName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: isWebtoonFit ? .infinity : nil)
                if isWebtoonFit {
                    img
                } else {
                    img.pinchToZoom()
                }
                #endif
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onDoubleTap?()
        }
        .onTapGesture(count: 1) {
            onTap?()
        }
    }
}

// MARK: - Comic Page View (Robust image loader with caching)

struct ComicPageView: View {
    let url: URL
    var isWebtoonFit: Bool = false
    
    #if canImport(UIKit)
    @State private var image: UIImage?
    #elseif canImport(AppKit)
    @State private var image: NSImage?
    #endif
    
    @State private var isLoading = true
    
    var body: some View {
        Group {
            #if canImport(UIKit)
            if let uiImage = image {
                let img = Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: isWebtoonFit ? .infinity : nil)
                if isWebtoonFit {
                    img
                } else {
                    img.pinchToZoom()
                }
            } else if isLoading {
                ProgressView()
                    .controlSize(.regular)
                    .tint(.white)
                    .frame(maxWidth: .infinity, minHeight: isWebtoonFit ? 400 : nil)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.secondary)
                    Text("Could not load image")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            }
            #elseif canImport(AppKit)
            if let nsImage = image {
                let img = Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: isWebtoonFit ? .infinity : nil)
                if isWebtoonFit {
                    img
                } else {
                    img.pinchToZoom()
                }
            } else if isLoading {
                ProgressView()
                    .controlSize(.regular)
                    .tint(.white)
                    .frame(maxWidth: .infinity, minHeight: isWebtoonFit ? 400 : nil)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.secondary)
                    Text("Could not load image")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            }
            #endif
        }
        .onAppear {
            loadImage(for: url)
        }
        .onChange(of: url) { _, newURL in
            loadImage(for: newURL)
        }
    }
    
    private func loadImage(for fileURL: URL) {
        isLoading = true
        
        Task {
            // 1. Check in-memory ImageCache
            if let cached = await ImageCache.shared.image(for: fileURL.path) {
                await MainActor.run {
                    self.image = cached
                    self.isLoading = false
                }
                return
            }
            
            // 2. Asynchronously load from disk
            let loaded: PlatformImage? = await Task.detached(priority: .userInitiated) { () -> PlatformImage? in
                guard let data = try? Data(contentsOf: fileURL) else {
                    #if canImport(UIKit)
                    return UIImage(contentsOfFile: fileURL.path)
                    #elseif canImport(AppKit)
                    return NSImage(contentsOfFile: fileURL.path)
                    #endif
                }
                #if canImport(UIKit)
                return UIImage(data: data)
                #elseif canImport(AppKit)
                return NSImage(data: data)
                #endif
            }.value
            
            if let result = loaded {
                await ImageCache.shared.setImage(result, for: fileURL.path)
                await MainActor.run {
                    self.image = result
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - macOS Pager Views with Full Keyboard & Click Zone Navigation

#if os(macOS)
struct ComicPagerView: View {
    let pages: [ComicPageSource]
    @Binding var currentPage: Int
    @Binding var showControls: Bool
    
    init(pages: [ComicPageSource], currentPage: Binding<Int>, showControls: Binding<Bool>) {
        self.pages = pages
        self._currentPage = currentPage
        self._showControls = showControls
    }
    
    init(pageURLs: [URL], currentPage: Binding<Int>, showControls: Binding<Bool>) {
        self.pages = pageURLs.map { .url($0) }
        self._currentPage = currentPage
        self._showControls = showControls
    }
    
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Active Comic Page with unique identity & Pinch to Zoom
                if currentPage < pages.count {
                    ComicPageItemView(page: pages[currentPage], isWebtoonFit: false)
                        .id(pages[currentPage].id)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                
                // Click zones: Left 25% = Previous, Right 25% = Next, Center 50% = Toggle controls
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: proxy.size.width * 0.25)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            previousPage()
                        }
                    
                    Color.clear
                        .frame(width: proxy.size.width * 0.50)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: DS.Animation.fast)) {
                                showControls.toggle()
                            }
                        }
                    
                    Color.clear
                        .frame(width: proxy.size.width * 0.25)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            nextPage()
                        }
                }
                
                // Floating Side Navigation Buttons
                HStack {
                    Button(action: previousPage) {
                        Image(systemName: "chevron.left")
                            .font(.title3.bold())
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .overlay(
                                Circle().stroke(DS.Colors.border, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(currentPage <= 0)
                    .opacity(currentPage <= 0 ? 0.2 : 0.85)
                    .padding(.leading, DS.Spacing.lg)
                    
                    Spacer()
                    
                    Button(action: nextPage) {
                        Image(systemName: "chevron.right")
                            .font(.title3.bold())
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .overlay(
                                Circle().stroke(DS.Colors.border, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(currentPage >= pages.count - 1)
                    .opacity(currentPage >= pages.count - 1 ? 0.2 : 0.85)
                    .padding(.trailing, DS.Spacing.lg)
                }
                
                // Hidden keyboard shortcut buttons
                hiddenKeyboardNavigators
            }
        }
    }
    
    private var hiddenKeyboardNavigators: some View {
        Group {
            Button("") { previousPage() }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .opacity(0)
            
            Button("") { nextPage() }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .opacity(0)
            
            Button("") { nextPage() }
                .keyboardShortcut(.space, modifiers: [])
                .opacity(0)
            
            Button("") { currentPage = 0 }
                .keyboardShortcut(.home, modifiers: [])
                .opacity(0)
            
            Button("") { currentPage = max(0, pages.count - 1) }
                .keyboardShortcut(.end, modifiers: [])
                .opacity(0)
        }
    }
    
    private func nextPage() {
        if currentPage < pages.count - 1 {
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
    @State private var showControls = true
    
    var body: some View {
        ComicPagerView(
            pages: images.map { .mock($0) },
            currentPage: $currentPage,
            showControls: $showControls
        )
    }
}
#endif
