//
//  TypeSafeAndIntentsTests.swift
//  WhisperTests
//
//  Created by Anurag Ambuj on 22/09/26.
//

import Testing
import Foundation
import SwiftData
import AppIntents
@testable import Whisper

struct TypeSafeAndIntentsTests {

    @Test func testTypeSafeMetadataExtraction() async throws {
        let service = TypeSafeService.shared

        let complex1 = "Stephen_King_-_The_Shining_(1977)_[Retail]_[v1.0].epub"
        let meta1 = service.extractCleanMetadata(from: complex1)
        #expect(meta1.author == "Stephen King")
        #expect(meta1.title == "The Shining")

        let complex2 = "[ScanGroup]_Attack_on_Titan_Chapter_01_(Digital).cbz"
        let meta2 = service.extractCleanMetadata(from: complex2)
        #expect(meta2.title.contains("Attack On Titan") || meta2.title.contains("Chapter"))
    }

    @Test func testTypeSafeSemanticReranking() async throws {
        let service = TypeSafeService.shared

        let book1 = Book(
            title: "The Time Machine",
            author: "H.G. Wells",
            content: "A Victorian scientist travels into the far future with Eloi and Morlocks.",
            format: .text
        )
        let book2 = Book(
            title: "Pride and Prejudice",
            author: "Jane Austen",
            content: "A story of marriage, manners, and morality in Regency England.",
            format: .text
        )
        let book3 = Book(
            title: "Alice in Wonderland",
            author: "Lewis Carroll",
            content: "Alice falls down a rabbit hole into a fantasy dream world.",
            format: .epub
        )

        let books = [book1, book2, book3]

        let timeResults = service.rerank(books: books, query: "time travel future")
        #expect(timeResults.first?.title == "The Time Machine")

        let austenResults = service.rerank(books: books, query: "regency romance austen")
        #expect(austenResults.first?.title == "Pride and Prejudice")
    }

    @Test func testTypeSafeSemanticFind() async throws {
        let service = TypeSafeService.shared

        let sampleDocument = """
        The Time Traveller (for so it will be convenient to speak of him) was expounding a recondite matter to us.
        His grey eyes shone and twinkled, and his usually pale face was flushed and animated.
        The fire burned brightly, and the soft radiance of the incandescent lights in the lilies of silver caught the bubbles that flashed and passed in our glasses.
        Our chairs, being his patents, embraced and caressed us rather than submitted to be sat upon.
        There was that luxurious after-dinner atmosphere when thought roams gracefully free of the trammels of precision.
        He put it to us in this simple way, marking the points upon a lean forefinger.
        The thing the Time Traveller held in his hand was a glittering metallic framework, scarcely larger than a small clock.
        There was ivory in it, and some transparent crystalline substance.
        The machine was constructed with two levers, one for travelling forwards in time and one for travelling backwards.
        """

        // Test matching query (answered)
        let findPresent = service.semanticFind(query: "levers for travelling in time", inDocument: sampleDocument)
        #expect(findPresent.verdict == .answered)
        #expect(findPresent.existsScore >= 0.70)
        #expect(!findPresent.matches.isEmpty)
        #expect(findPresent.matches.first?.excerpt.contains("levers") == true)

        // Test absent query
        let findAbsent = service.semanticFind(query: "quantum smartphone satellite wireless antenna", inDocument: sampleDocument)
        #expect(findAbsent.verdict == .absent)
        #expect(findAbsent.existsScore < 0.35)
        #expect(findAbsent.matches.isEmpty)
    }

    @Test func testTypeSafeDramatisPersonaeExtraction() async throws {
        let service = TypeSafeService.shared

        let text = """
        The Time Traveller showed us his workshop. Weena, the gentle Eloi girl, held a white flower.
        Below the earth, the Morlocks plotted in darkness while the Time Traveller watched.
        """

        let entities = service.extractDramatisPersonae(from: text)
        #expect(!entities.isEmpty)

        let names = entities.map(\.name)
        #expect(names.contains("The Time Traveller"))
        #expect(names.contains("Weena"))
        #expect(names.contains("The Eloi"))
        #expect(names.contains("The Morlocks"))
    }

    @Test func testTypeSafeStoreRerankingAndRecommendations() async throws {
        let service = TypeSafeService.shared
        let catalog = StoreService.shared.catalog

        // Reranking by concept
        let comicResults = service.rerankStoreBooks(books: catalog, query: "superhero comic graphic novel")
        #expect(!comicResults.isEmpty)
        #expect(comicResults.contains { $0.category == "Comics" || $0.format == .comic })

        // Recommendations
        let library = [
            Book(title: "Cyberpunk 2099", author: "Neo Tokyo", format: .comic)
        ]
        let recommendations = service.recommendStoreBooks(library: library, catalog: catalog, limit: 3)
        #expect(!recommendations.isEmpty)
        #expect(recommendations.count <= 3)
    }

    @Test func testChapterTOCDecodingWithoutID() async throws {
        let jsonString = """
        [
            {"title": "Chapter 1: The Beginning", "path": "text/ch01.xhtml"},
            {"title": "Chapter 2: The Journey", "path": "text/ch02.xhtml"}
        ]
        """
        let data = jsonString.data(using: .utf8)!
        let chapters = try JSONDecoder().decode([Chapter].self, from: data)

        #expect(chapters.count == 2)
        #expect(chapters[0].title == "Chapter 1: The Beginning")
        #expect(chapters[0].path == "text/ch01.xhtml")
        #expect(chapters[1].title == "Chapter 2: The Journey")
        #expect(chapters[1].path == "text/ch02.xhtml")
    }

    @Test func testBookEntityAppIntentsConversion() async throws {
        let book = Book(
            title: "Cyberpunk 2099",
            author: "Neo Tokyo",
            format: .comic
        )
        let entity = book.toEntity()

        #expect(entity.id == book.id)
        #expect(entity.title == "Cyberpunk 2099")
        #expect(entity.author == "Neo Tokyo")
        #expect(entity.format == "Comic Book")
    }

    @Test @MainActor func testCloudKitEntitlementSafety() async throws {
        let isEntitled = CloudSyncService.isCloudKitEntitled
        #expect(isEntitled == false || isEntitled == true)

        let service = CloudSyncService.shared
        #expect(service.status == .available || service.status == .checking || service.status == .noAccount)
    }

    @Test @MainActor func testContinuousEpubDocumentConfiguration() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let textDir = tempDir.appendingPathComponent("OEBPS/Text", isDirectory: true)
        try FileManager.default.createDirectory(at: textDir, withIntermediateDirectories: true)

        let ch1URL = textDir.appendingPathComponent("ch1.xhtml")
        let ch2URL = textDir.appendingPathComponent("ch2.xhtml")

        let ch1Content = "<html><head><title>Ch 1</title></head><body><p>Hello world 1</p></body></html>"
        let ch2Content = "<html><head><title>Ch 2</title></head><body><p>Hello world 2</p></body></html>"

        try ch1Content.write(to: ch1URL, atomically: true, encoding: .utf8)
        try ch2Content.write(to: ch2URL, atomically: true, encoding: .utf8)

        let controller = EpubReaderController(bookDir: tempDir)
        controller.configureBook(
            chapterPaths: [ch1URL.path, ch2URL.path],
            bookTitle: "Test Multi-Chapter Book",
            theme: .default,
            fontSize: 18.0
        )

        #expect(controller.totalChapters == 2)
        #expect(controller.currentChapterIndex == 0)
        #expect(controller.readingMode == .paginated)

        controller.setReadingMode(.scroll)
        #expect(controller.readingMode == .scroll)
    }
}
