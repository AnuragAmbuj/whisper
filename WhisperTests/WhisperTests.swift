//
//  WhisperTests.swift
//  WhisperTests
//
//  Created by Anurag Ambuj on 28/12/25.
//

import Testing
import Foundation
import SwiftData
import UniformTypeIdentifiers
import SwiftUI
@testable import Whisper

struct WhisperTests {

    @Test @MainActor func testLibraryViewModelCategoryFiltering() async throws {
        let viewModel = LibraryViewModel()
        
        let book1 = Book(title: "Swift Guide", author: "Apple", coverImageName: "", content: "", format: .text)
        let book2 = Book(title: "Architecture PDF", author: "Architect", coverImageName: "", content: "", format: .pdf)
        let book3 = Book(title: "Manga Issue 1", author: "Artist", coverImageName: "", content: "", format: .comic)
        let book4 = Book(title: "Classic Novel", author: "Author", coverImageName: "", content: "", format: .epub)
        let allBooks = [book1, book2, book3, book4]
        
        // All
        viewModel.selectedCategory = "All"
        #expect(viewModel.filterBooks(allBooks).count == 4)
        
        // PDF only
        viewModel.selectedCategory = "PDF"
        let pdfs = viewModel.filterBooks(allBooks)
        #expect(pdfs.count == 1)
        #expect(pdfs.first?.format == .pdf)
        
        // Comics only
        viewModel.selectedCategory = "Comics"
        let comics = viewModel.filterBooks(allBooks)
        #expect(comics.count == 1)
        #expect(comics.first?.format == .comic)
        
        // EPUB only
        viewModel.selectedCategory = "EPUB"
        let epubs = viewModel.filterBooks(allBooks)
        #expect(epubs.count == 1)
        #expect(epubs.first?.format == .epub)
        
        // Search filter
        viewModel.selectedCategory = "All"
        viewModel.searchText = "Swift"
        let searchResults = viewModel.filterBooks(allBooks)
        #expect(searchResults.count == 1)
        #expect(searchResults.first?.title == "Swift Guide")
    }

    @Test @MainActor func testReaderViewModelBookmarkToggle() async throws {
        let book = Book(title: "Bookmark Test", author: "Tester", coverImageName: "", content: "Sample content", format: .text)
        let vm = ReaderViewModel(book: book)
        
        // Initially not bookmarked
        #expect(vm.isBookmarked == false)
        #expect(book.safeBookmarks.isEmpty)
        
        // Toggle bookmark ON
        vm.updateLocation(42)
        vm.toggleBookmark()
        #expect(vm.isBookmarked == true)
        #expect(book.safeBookmarks.count == 1)
        #expect(book.safeBookmarks.first?.pageOrLocation == 42)
        
        // Toggle bookmark OFF
        vm.toggleBookmark()
        #expect(vm.isBookmarked == false)
        #expect(book.safeBookmarks.isEmpty)
    }

    @Test @MainActor func testReaderViewModelSettingsBounds() async throws {
        let book = Book(title: "Settings Test", author: "Tester", coverImageName: "", content: "", format: .text)
        let vm = ReaderViewModel(book: book)
        
        // Font size bounds
        vm.fontSize = 32
        vm.increaseFontSize()
        #expect(vm.fontSize <= 32)
        
        vm.fontSize = 12
        vm.decreaseFontSize()
        #expect(vm.fontSize >= 12)
        
        // Line height bounds
        vm.lineHeight = 3.0
        vm.increaseLineHeight()
        #expect(vm.lineHeight <= 3.0)
        
        vm.lineHeight = 1.0
        vm.decreaseLineHeight()
        #expect(vm.lineHeight >= 1.0)
        
        // Theme switching
        vm.setTheme(.sepia)
        #expect(vm.theme.style == .sepia)
        
        vm.setTheme(.greyscale)
        #expect(vm.theme.style == .greyscale)
        
        vm.setTheme(.sage)
        #expect(vm.theme.style == .sage)
        
        vm.setTheme(.dusk)
        #expect(vm.theme.style == .dusk)
        
        vm.setTheme(.dark)
        #expect(vm.theme.style == .dark)
        
        // Typography font family
        vm.setFontName("Mono")
        #expect(vm.fontName == "Mono")
        #expect(vm.theme.fontName == "Mono")
    }

    @Test @MainActor func testEyeComfortThemes() async throws {
        // Ensure all eye-comfort themes are defined with valid displays & icons
        let styles = AppTheme.ThemeStyle.allCases
        #expect(styles.contains(.sepia))
        #expect(styles.contains(.greyscale))
        #expect(styles.contains(.sage))
        #expect(styles.contains(.dusk))
        #expect(styles.contains(.dark))
        #expect(styles.contains(.light))
        #expect(styles.contains(.default))
        
        for style in styles {
            #expect(!style.displayName.isEmpty)
            #expect(!style.description.isEmpty)
            #expect(!style.iconName.isEmpty)
            
            let lightTheme = AppTheme(style: style, isDarkMode: false)
            let darkTheme = AppTheme(style: style, isDarkMode: true)
            #expect(lightTheme.style == style)
            #expect(darkTheme.style == style)
        }
        
        // Specific checks for Sepia and Greyscale
        let sepia = AppTheme(style: .sepia, isDarkMode: false)
        #expect(sepia.style == .sepia)
        
        let greyscale = AppTheme(style: .greyscale, isDarkMode: false)
        #expect(greyscale.style == .greyscale)
        
        let sage = AppTheme(style: .sage, isDarkMode: false)
        #expect(sage.style == .sage)
    }

    @Test @MainActor func testBookServiceRichSampleBooks() async throws {
        let sampleBooks = BookService.shared.generateRichSampleBooks()
        #expect(sampleBooks.count >= 4)
        
        let hasText = sampleBooks.contains(where: { $0.format == .text })
        let hasComic = sampleBooks.contains(where: { $0.format == .comic })
        let hasEpub = sampleBooks.contains(where: { $0.format == .epub })
        
        #expect(hasText == true)
        #expect(hasComic == true)
        #expect(hasEpub == true)
    }

    @Test func testBookDirResolution() async throws {
        let textBook = Book(title: "Text", author: "Author", coverImageName: "", content: "", format: .text, url: URL(fileURLWithPath: "/tmp/sample.txt"))
        #expect(textBook.bookDir?.path == "/tmp/sample.txt")
        
        let epubBook = Book(title: "Epub", author: "Author", coverImageName: "", content: "", format: .epub)
        #expect(epubBook.bookDir != nil)
        #expect(epubBook.bookDir?.lastPathComponent == epubBook.id.uuidString)
    }

    @Test func testLegacyBookFormatMigrationNilHandling() async throws {
        let legacyBook = Book(title: "Legacy Book", author: "Old Author", coverImageName: "", content: "Old Content", format: nil)
        // In init, format defaults to .text
        #expect(legacyBook.format == .text)
        
        // When simulated as raw nil from legacy database
        legacyBook.format = nil
        #expect(legacyBook.format == nil)
        
        // Effective fallback is text
        let effectiveFormat = legacyBook.format ?? .text
        #expect(effectiveFormat == .text)
        
        // Ensure bookDir handles nil format safely without crashing
        #expect(legacyBook.bookDir == nil)
    }

    @Test @MainActor func testStoreServiceCatalogAndPurchase() async throws {
        let store = StoreService.shared
        #expect(!store.catalog.isEmpty)
        #expect(store.categories.contains("Bestsellers"))
        #expect(store.categories.contains("Sci-Fi"))
        
        let sampleStoreBook = try #require(store.catalog.first)
        #expect(!sampleStoreBook.title.isEmpty)
        #expect(!sampleStoreBook.author.isEmpty)
        #expect(!sampleStoreBook.price.isEmpty)
        
        // Test in-memory ModelContext purchase/download
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, configurations: config)
        let context = container.mainContext
        
        let purchasedBook = store.purchaseOrDownload(sampleStoreBook, context: context)
        #expect(purchasedBook.title == sampleStoreBook.title)
        #expect(purchasedBook.author == sampleStoreBook.author)
        #expect(purchasedBook.format == sampleStoreBook.format)
        #expect(store.isPurchased(id: sampleStoreBook.id))
    }

    @Test @MainActor func testStoreServiceSubscription() async throws {
        let store = StoreService.shared
        let originalState = store.isWhisperPlusSubscribed
        
        store.isWhisperPlusSubscribed = true
        #expect(store.isWhisperPlusSubscribed == true)
        
        store.isWhisperPlusSubscribed = false
        #expect(store.isWhisperPlusSubscribed == false)
        
        // Restore
        store.isWhisperPlusSubscribed = originalState
    }

    @Test @MainActor func testComicPageResolutionAndOrdering() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create mock images out of order
        let files = ["page2.png", "page10.jpg", "page1.png", "page0.webp"]
        let dummyData = Data([0x89, 0x50, 0x4E, 0x47]) // PNG header bytes
        for file in files {
            try dummyData.write(to: tempDir.appendingPathComponent(file))
        }

        // Test fallback scanning and natural sorting
        let resolved = ComicParser.shared.getPages(from: tempDir)
        #expect(resolved.count == 4)
        #expect(resolved[0].lastPathComponent == "page0.webp")
        #expect(resolved[1].lastPathComponent == "page1.png")
        #expect(resolved[2].lastPathComponent == "page2.png")
        #expect(resolved[3].lastPathComponent == "page10.jpg")

        // Save pages.json with relative paths and verify getPages uses it
        let relativePaths = resolved.map { $0.lastPathComponent }
        let pagesJSON = try JSONEncoder().encode(relativePaths)
        try pagesJSON.write(to: tempDir.appendingPathComponent("pages.json"))

        let fromJSON = ComicParser.shared.getPages(from: tempDir)
        #expect(fromJSON.count == 4)
        #expect(fromJSON[0].lastPathComponent == "page0.webp")
        #expect(fromJSON[3].lastPathComponent == "page10.jpg")
    }

    @Test @MainActor func testComicReadingModes() async throws {
        #expect(ComicReadingMode.allCases.count == 2)
        #expect(ComicReadingMode.paged.iconName == "book.pages")
        #expect(ComicReadingMode.continuous.iconName == "scroll")
    }

    @Test @MainActor func testWebtoonFocalPageTracking() async throws {
        let positions = [
            WebtoonPagePos(index: 0, midY: 100),
            WebtoonPagePos(index: 1, midY: 400),
            WebtoonPagePos(index: 2, midY: 700)
        ]
        let viewportCenterY: CGFloat = 390
        let closest = positions.min(by: { abs($0.midY - viewportCenterY) < abs($1.midY - viewportCenterY) })
        #expect(closest?.index == 1)
    }

    @Test func testWebtoonDynamicFocalZoomMetrics() async throws {
        let viewportHeight: CGFloat = 1000
        let viewportCenterY: CGFloat = 500
        let focalThreshold = viewportHeight * 0.26 // 260
        let maxFalloff = viewportHeight * 0.44     // 440

        func calculateScale(midY: CGFloat) -> CGFloat {
            let distance = abs(midY - viewportCenterY)
            if distance <= focalThreshold {
                return 1.06
            } else if distance < (focalThreshold + maxFalloff) {
                let progress = (distance - focalThreshold) / maxFalloff
                return 1.06 - (progress * 0.06)
            } else {
                return 1.0
            }
        }

        // Center item (focal): scale should be 1.06
        let centerScale = calculateScale(midY: 500)
        #expect(centerScale == 1.06)

        // Inside focal zone: scale should remain 1.06
        let insideThresholdScale = calculateScale(midY: 600)
        #expect(insideThresholdScale == 1.06)

        // Midway transitioning out of center: scale between 1.00 and 1.06
        let midScrollScale = calculateScale(midY: 850)
        #expect(midScrollScale > 1.00 && midScrollScale < 1.06)

        // Far away from center: scale returns to 1.0
        let distantScale = calculateScale(midY: 1500)
        #expect(distantScale == 1.0)
    }

    @Test @MainActor func testImportServiceSupportedTypesAndFormats() async throws {
        let types = ImportService.supportedTypes
        #expect(types.contains(.pdf))
        #expect(types.contains(.plainText))
        #expect(types.contains(.zip))
    }

    @Test @MainActor func testEpubReadingModesAndIcons() async throws {
        let paged = EpubReadingMode.paginated
        let scroll = EpubReadingMode.scroll

        #expect(paged.id == "Pages")
        #expect(scroll.id == "Scroll")
        #expect(paged.icon == "book.pages")
        #expect(scroll.icon == "doc.text.below.ecg")
    }

    @Test @MainActor func testEpubControllerInitializationAndModeSwitch() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let controller = EpubReaderController(bookDir: tempDir)
        #expect(controller.isLoading == true)
        #expect(controller.currentPage == 1)
        #expect(controller.totalPages == 1)
        #expect(controller.readingMode == .paginated)
        #expect(controller.errorMessage == nil)

        // Reading mode switch
        controller.setReadingMode(.scroll)
        #expect(controller.readingMode == .scroll)

        controller.setReadingMode(.paginated)
        #expect(controller.readingMode == .paginated)
    }

    @Test func testEpubFallbackChapterDiscovery() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create sample chapter files
        let files = ["chapter2.xhtml", "chapter1.xhtml", "chapter10.xhtml", "toc.xhtml", "nav.xhtml"]
        for file in files {
            let fileURL = tempDir.appendingPathComponent(file)
            try "<html><body><p>Test</p></body></html>".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        // Test fallback scanning and filtering out nav/toc
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: tempDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            Issue.record("Failed to create enumerator")
            return
        }

        var found: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            let name = fileURL.lastPathComponent.lowercased()
            if (ext == "xhtml" || ext == "html" || ext == "htm"),
               !name.contains("toc"),
               !name.contains("nav"),
               !name.hasPrefix(".") {
                found.append(fileURL)
            }
        }
        let sorted = found.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        #expect(sorted.count == 3)
        #expect(sorted[0].lastPathComponent == "chapter1.xhtml")
        #expect(sorted[1].lastPathComponent == "chapter2.xhtml")
        #expect(sorted[2].lastPathComponent == "chapter10.xhtml")
    }

    @Test @MainActor func testCloudSyncServiceInitialization() async throws {
        let syncService = CloudSyncService.shared
        #expect(CloudSyncService.containerIdentifier == "iCloud.club.ironlattice.Whisper")
        #expect(!syncService.status.localizedDescription.isEmpty)
        #expect(!syncService.status.iconName.isEmpty)
    }

    @Test func testWhisperMarkShapeGeometry() async throws {
        let shape = WhisperMarkShape()
        let rect = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        let path = shape.path(in: rect)

        #expect(!path.isEmpty)
        let bounds = path.boundingRect
        #expect(bounds.minX >= 90 && bounds.maxX <= 930)
        #expect(bounds.minY >= 230 && bounds.maxY <= 795)
    }

    @Test func testWhisperMarkGradientStops() async throws {
        let stops = WhisperMarkShape.brandGradientStops
        #expect(stops.count == 4)
        #expect(stops[0].location == 0.0)
        #expect(stops[1].location == 0.33)
        #expect(stops[2].location == 0.66)
        #expect(stops[3].location == 1.0)
    }

    @Test @MainActor func testCloudSyncServiceReadingProgressSync() async throws {
        let book = Book(
            title: "Cloud Sync Test",
            author: "Author",
            content: "Testing iCloud Sync",
            lastReadDate: Date(timeIntervalSince1970: 1000),
            progress: 0.45
        )
        
        let syncService = CloudSyncService.shared
        syncService.saveReadingProgress(for: book)
        
        let remoteBookState = Book(
            id: book.id,
            title: book.title,
            author: book.author,
            content: book.content,
            lastReadDate: Date(timeIntervalSince1970: 2000),
            progress: 0.85
        )
        syncService.saveReadingProgress(for: remoteBookState)
        
        syncService.applyLatestCloudReadingProgress(for: book)
        #expect(book.progress == 0.85)
        #expect(book.lastReadDate == Date(timeIntervalSince1970: 2000))
    }

    @Test func testBookResolvedURLFallback() async throws {
        let uniqueID = UUID().uuidString
        let nonExistentURL = URL(fileURLWithPath: "/var/mobile/Containers/Data/Application/ABC-123/Documents/Books/\(uniqueID).epub")
        let book = Book(
            title: "Path Resiliency Test",
            author: "Author",
            format: .epub,
            url: nonExistentURL
        )
        
        let resolved = book.resolvedURL
        #expect(resolved != nil)
        
        let bookDir = book.bookDir
        #expect(bookDir != nil)
    }

    @Test @MainActor func testCloudSyncStatusProperties() async throws {
        let statuses: [CloudSyncService.SyncStatus] = [
            .checking,
            .available,
            .noAccount,
            .restricted,
            .temporarilyUnavailable,
            .error("Sample Error")
        ]
        
        for status in statuses {
            #expect(!status.localizedDescription.isEmpty)
            #expect(!status.iconName.isEmpty)
        }
    }
}

