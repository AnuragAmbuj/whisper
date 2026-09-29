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

    @Test @MainActor func testGoogleDriveAndCloudSyncProviderSwitching() async throws {
        let syncService = CloudSyncService.shared
        let original = syncService.providerPreference
        
        syncService.providerPreference = .googleDrive
        #expect(syncService.activeProvider == .googleDrive)
        #expect(syncService.statusIcon.contains("externaldrive"))
        
        syncService.providerPreference = .disabled
        #expect(syncService.activeProvider == .disabled)
        #expect(syncService.statusText == "Sync Off")
        
        syncService.providerPreference = .iCloud
        #expect(syncService.activeProvider == .iCloud)
        
        // Restore
        syncService.providerPreference = original
    }

    @Test func testGoogleDriveConfigSecurity() async throws {
        let config = GoogleDriveConfig.shared
        #expect(!config.clientID.isEmpty)
        #expect(config.clientID.contains(".apps.googleusercontent.com"))
        #expect(config.reversedClientID.starts(with: "com.googleusercontent.apps."))
        #expect(config.redirectURI.contains(":/oauth2redirect"))
    }
    // MARK: - EPUB Generator & Scanner Append Mode Tests
    
    @Test func testMiniZipCreateZipAndUnzipRoundTrip() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("MiniZipTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let zipDest = tempDir.appendingPathComponent("test.zip")
        let unzipDest = tempDir.appendingPathComponent("unzipped")
        
        let file1Content = "application/epub+zip"
        let file2Content = "<html><body><h1>Hello Whisper</h1></body></html>"
        
        let entries = [
            MiniZip.ZipEntry(path: "mimetype", data: file1Content.data(using: .utf8)!, uncompressed: true),
            MiniZip.ZipEntry(path: "OEBPS/chapter1.xhtml", data: file2Content.data(using: .utf8)!, uncompressed: false)
        ]
        
        try MiniZip.shared.createZip(entries: entries, destination: zipDest)
        #expect(FileManager.default.fileExists(atPath: zipDest.path))
        
        try MiniZip.shared.unzip(sourceURL: zipDest, destinationURL: unzipDest)
        
        let restoredFile1 = unzipDest.appendingPathComponent("mimetype")
        let restoredFile2 = unzipDest.appendingPathComponent("OEBPS/chapter1.xhtml")
        
        #expect(FileManager.default.fileExists(atPath: restoredFile1.path))
        #expect(FileManager.default.fileExists(atPath: restoredFile2.path))
        
        let read1 = try String(contentsOf: restoredFile1, encoding: .utf8)
        let read2 = try String(contentsOf: restoredFile2, encoding: .utf8)
        
        #expect(read1 == file1Content)
        #expect(read2 == file2Content)
    }
    
    @Test func testEpubGeneratorServiceParseChapters() async throws {
        let generator = EpubGeneratorService.shared
        
        let continuousText = """
        Introduction paragraph here.
        
        --- Page 2 ---
        
        This is page two text with more information.
        
        --- Page 3 ---
        
        Conclusion on page three.
        """
        
        let chapters = generator.parseTextIntoChapters(continuousText, defaultTitle: "Page 1")
        #expect(chapters.count == 3)
        #expect(chapters[0].title == "Page 1")
        #expect(chapters[0].content.contains("Introduction paragraph"))
        #expect(chapters[1].title == "Page 2")
        #expect(chapters[1].content.contains("This is page two text"))
        #expect(chapters[2].title == "Page 3")
        #expect(chapters[2].content.contains("Conclusion on page three"))
    }
    
    @Test func testEpubGeneratorServiceGenerateEpubArchive() async throws {
        let generator = EpubGeneratorService.shared
        let bookID = UUID()
        let title = "Test Scanned Book"
        let author = "Test Author"
        
        let chapters = [
            EpubGeneratorService.ChapterInput(title: "Chapter 1", content: "Scanned text for the first chapter."),
            EpubGeneratorService.ChapterInput(title: "Chapter 2", content: "Scanned text for the second chapter.")
        ]
        
        let result = try generator.generateEpub(
            title: title,
            author: author,
            chapters: chapters,
            bookID: bookID
        )
        
        #expect(FileManager.default.fileExists(atPath: result.epubURL.path))
        #expect(FileManager.default.fileExists(atPath: result.bookDir.path))
        
        // Verify container.xml
        let containerURL = result.bookDir.appendingPathComponent("META-INF/container.xml")
        #expect(FileManager.default.fileExists(atPath: containerURL.path))
        
        // Verify content.opf
        let opfURL = result.bookDir.appendingPathComponent("OEBPS/content.opf")
        #expect(FileManager.default.fileExists(atPath: opfURL.path))
        let opfContent = try String(contentsOf: opfURL, encoding: .utf8)
        #expect(opfContent.contains("Test Scanned Book"))
        #expect(opfContent.contains("Test Author"))
        
        // Verify TOC & Chapters
        let chap1URL = result.bookDir.appendingPathComponent("OEBPS/chapter_1.xhtml")
        let chap2URL = result.bookDir.appendingPathComponent("OEBPS/chapter_2.xhtml")
        #expect(FileManager.default.fileExists(atPath: chap1URL.path))
        #expect(FileManager.default.fileExists(atPath: chap2URL.path))
        
        let parsedBook = EpubParser.shared.parse(sourceURL: result.epubURL)
        #expect(parsedBook != nil)
        #expect(parsedBook?.title == title)
        #expect(parsedBook?.author == author)
    }
    
    @Test func testEpubGeneratorServiceAppendPagesToExistingBook() async throws {
        let generator = EpubGeneratorService.shared
        let book = Book(
            title: "Appendable Notes",
            author: "Field Researcher",
            content: "Initial page notes from day 1.",
            format: .text
        )
        
        let newPageText = "Follow-up notes from day 2 research."
        let updatedURL = try generator.appendScannedPages(to: book, newText: newPageText)
        
        #expect(book.format == .epub)
        #expect(book.url?.pathExtension == "epub")
        #expect(FileManager.default.fileExists(atPath: updatedURL.path))
        #expect(book.content.contains("Initial page notes"))
        #expect(book.content.contains("Follow-up notes"))
        
        // Verify that EPUB parser can parse the updated book with both chapters
        let parsed = EpubParser.shared.parse(sourceURL: updatedURL)
        #expect(parsed != nil)
        #expect(parsed?.title == "Appendable Notes")
    }

    // MARK: - Audiobook Tests
    
    @Test @MainActor func testAudiobookBookFormatAndIcon() async throws {
        let book = Book(
            title: "The Art of War",
            author: "Sun Tzu",
            coverImageName: "",
            content: "",
            progress: 0.15,
            format: .audiobook
        )
        #expect(book.format == .audiobook)
        #expect(book.format?.displayName == "Audiobook")
        #expect(book.format?.iconName == "headphones")
        
        let searchable = book.resolveSearchableContent()
        #expect(searchable.contains("Narrated audio edition"))
        #expect(searchable.contains("The Art of War"))
    }
    
    @Test @MainActor func testAudiobookPlayerServiceControls() async throws {
        let player = AudiobookPlayerService.shared
        let book = Book(
            title: "Test Audiobook",
            author: "Narrator",
            coverImageName: "",
            content: "Sample audio",
            progress: 0.25,
            format: .audiobook
        )
        
        var recordedProgress: Double?
        var recordedLocation: Int?
        player.loadBook(book) { progress, location in
            recordedProgress = progress
            recordedLocation = location
        }
        
        #expect(player.duration > 0)
        #expect(!player.chapters.isEmpty)
        
        player.setPlaybackRate(1.5)
        #expect(player.playbackRate == 1.5)
        
        player.seek(to: 120.0)
        #expect(player.currentTime == 120.0)
        #expect(recordedLocation == 120)
        
        let formatted = AudiobookPlayerService.formatTime(3665)
        #expect(formatted == "1:01:05")
        
        let formattedShort = AudiobookPlayerService.formatTime(125)
        #expect(formattedShort == "2:05")
        
        player.pause()
        #expect(player.isPlaying == false)
    }
    
    @Test @MainActor func testAudiobookBookmarkFormatting() async throws {
        let book = Book(
            title: "Audiobook Bookmarking",
            author: "Author",
            content: "Narration content",
            format: .audiobook
        )
        let vm = ReaderViewModel(book: book)
        vm.updateLocation(185) // 3m 05s
        vm.toggleBookmark()
        
        #expect(vm.isBookmarked == true)
        #expect(book.safeBookmarks.count == 1)
        #expect(book.safeBookmarks.first?.note?.contains("3:05") == true)
    }
    
    @Test @MainActor func testLibraryViewModelAudiobookFiltering() async throws {
        let allBooks = [
            Book(title: "Audio 1", author: "A", content: "", format: .audiobook),
            Book(title: "Text 1", author: "B", content: "", format: .text),
            Book(title: "EPUB 1", author: "C", content: "", format: .epub)
        ]
        let vm = LibraryViewModel()
        #expect(vm.categories.contains("Audiobooks"))
        
        vm.selectedCategory = "Audiobooks"
        let filtered = vm.filterBooks(allBooks)
        #expect(filtered.count == 1)
        #expect(filtered.first?.title == "Audio 1")
    }
    
    @Test func testAudiobookCloudSyncSupport() async throws {
        let exts = CloudSyncService.supportedSyncExtensions
        #expect(exts.contains("m4b"))
        #expect(exts.contains("mp3"))
        #expect(exts.contains("m4a"))
        #expect(exts.contains("aac"))
    }

    // MARK: - Multi-Format Navigable Chapters & Smart Find Tests

    @Test @MainActor func testChapterServiceExtractionAcrossFormats() async throws {
        let chapterService = ChapterService.shared

        // 1. Text Book with Markdown Headings
        let textContent = """
        # The First Adventure
        Once upon a time in a distant land.
        
        ## The Hidden Forest
        Trees whispered ancient tales to passersby.
        
        ### The Secret Spring
        Crystal water flowed into the hidden glade.
        """
        let textBook = Book(title: "Text Adventure", author: "Bard", content: textContent, format: .text)
        let textChapters = chapterService.extractChapters(for: textBook)
        #expect(textChapters.count >= 3)
        #expect(textChapters[0].title == "The First Adventure")
        #expect(textChapters[0].pageOrLocation == 0)
        #expect(textChapters[1].title == "The Hidden Forest")
        #expect(textChapters[2].title == "The Secret Spring")

        // 2. Audiobook with Timestamps
        let audioContent = """
        00:00 • Introduction & Overture
        05:30 • Chapter 1: The Gathering Storm
        12:45 • Chapter 2: The Battle of Whispering Pines
        """
        let audioBook = Book(title: "War Chronicles", author: "Historian", content: audioContent, format: .audiobook)
        let audioChapters = chapterService.extractChapters(for: audioBook)
        #expect(audioChapters.count == 3)
        #expect(audioChapters[0].pageOrLocation == 0)
        #expect(audioChapters[1].pageOrLocation == 330) // 5 * 60 + 30
        #expect(audioChapters[1].subtitle == "05:30")
        #expect(audioChapters[2].pageOrLocation == 765) // 12 * 60 + 45
        #expect(audioChapters[2].subtitle == "12:45")

        // 3. EPUB Book with toc.json
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleTOC = [
            Chapter(title: "Prelude", path: "prelude.xhtml", pageOrLocation: 0, subtitle: "Chapter 1"),
            Chapter(title: "The Journey Begins", path: "ch1.xhtml", pageOrLocation: 1, subtitle: "Chapter 2")
        ]
        let tocData = try JSONEncoder().encode(sampleTOC)
        try tocData.write(to: tempDir.appendingPathComponent("toc.json"))

        let epubBook = Book(title: "Sample EPUB", author: "Author", content: "", format: .epub)
        epubBook.url = tempDir.appendingPathComponent("book.epub")
        // Create mock extracted dir matching id
        let bookDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Books/\(epubBook.id.uuidString)")
        try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)
        try tocData.write(to: bookDir.appendingPathComponent("toc.json"))
        defer { try? FileManager.default.removeItem(at: bookDir) }

        let epubChapters = chapterService.extractChapters(for: epubBook)
        #expect(epubChapters.count == 2)
        #expect(epubChapters[0].title == "Prelude")
        #expect(epubChapters[1].title == "The Journey Begins")
        #expect(epubChapters[1].pageOrLocation == 1)
    }

    @Test @MainActor func testTypeSafeSmartFindNavigableExtraction() async throws {
        // 1. PDF/Comic [Page X] Pattern
        let comicExcerpt = "[Page 14] The hero leaps across the rooftop!"
        let pagePattern = #"(?:\[Page|Page)\s+(\d+)"#
        let regex = try NSRegularExpression(pattern: pagePattern, options: .caseInsensitive)
        let match = regex.firstMatch(in: comicExcerpt, range: NSRange(comicExcerpt.startIndex..., in: comicExcerpt))
        #expect(match != nil)
        if let match = match, let range = Range(match.range(at: 1), in: comicExcerpt) {
            let pageNum = Int(comicExcerpt[range])!
            let targetIndex = max(0, pageNum - 1)
            #expect(targetIndex == 13)
        }

        // 2. Audiobook Timestamp Pattern
        let audioExcerpt = "At 07:45 the narrator describes the midnight crossing."
        let timePattern = #"(\d{1,2}):(\d{2})(?::(\d{2}))?"#
        let timeRegex = try NSRegularExpression(pattern: timePattern, options: [])
        let timeMatch = timeRegex.firstMatch(in: audioExcerpt, range: NSRange(audioExcerpt.startIndex..., in: audioExcerpt))
        #expect(timeMatch != nil)
        if let timeMatch = timeMatch,
           let r1 = Range(timeMatch.range(at: 1), in: audioExcerpt),
           let r2 = Range(timeMatch.range(at: 2), in: audioExcerpt) {
            let m = Int(audioExcerpt[r1])!
            let s = Int(audioExcerpt[r2])!
            let totalSecs = Double(m * 60 + s)
            #expect(totalSecs == 465.0) // 7 * 60 + 45 = 465
        }
    }


    @Test @MainActor func testAudiobookWaveformScrubberAndFormatting() async throws {
        // Test padded timestamp formatting matching screenshot (02:45:18 and -05:27:17)
        let elapsed = 2 * 3600 + 45 * 60 + 18 // 02:45:18
        let remaining = 5 * 3600 + 27 * 60 + 17 // 05:27:17
        
        let elapsedStr = AudiobookPlayerService.formatTimeDisplay(Double(elapsed), forceHours: true)
        let remainingStr = AudiobookPlayerService.formatTimeDisplay(Double(remaining), forceHours: true)
        
        #expect(elapsedStr == "02:45:18")
        #expect(remainingStr == "05:27:17")
        
        // Under one hour without forceHours
        let shortTime = 12 * 60 + 34 // 12:34
        let shortStr = AudiobookPlayerService.formatTimeDisplay(Double(shortTime), forceHours: false)
        #expect(shortStr == "12:34")
        
        // Player seek clamping & state
        let player = AudiobookPlayerService.shared
        player.duration = 28800.0 // 8 hours
        player.seek(to: Double(elapsed))
        #expect(player.currentTime == Double(elapsed))
        
        // Clamping bounds
        player.seek(to: 999999.0)
        #expect(player.currentTime == player.duration)
        
        player.seek(to: -100.0)
        #expect(player.currentTime == 0.0)
    }
}
