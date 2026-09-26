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

@Suite(.serialized)
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

    @Test func testTypeSafeConfigAndSecretProtection() async throws {
        let config = TypeSafeConfig.shared
        #expect(config.isConfigured)
        #expect(!config.apiKey.isEmpty)
        #expect(config.apiKey.hasPrefix("apikey_"))
        #expect(config.defaultModel == "jev-latest")
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
        let findPresent = await service.semanticFind(query: "levers for travelling in time", inDocument: sampleDocument)
        #expect(findPresent.verdict == .answered || findPresent.verdict == .partial)
        #expect(findPresent.existsScore >= 0.50)
        #expect(!findPresent.matches.isEmpty)

        // Test absent query
        let findAbsent = await service.semanticFind(query: "quantum smartphone satellite wireless antenna", inDocument: sampleDocument)
        #expect(findAbsent.verdict == .absent || findAbsent.existsScore < 0.35)
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

    @Test func testBookResolveSearchableContent() async throws {
        let book = Book(
            title: "Pride and Prejudice",
            author: "Jane Austen",
            content: "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.",
            format: .text
        )
        let resolved = book.resolveSearchableContent()
        #expect(resolved.contains("truth universally acknowledged"))
    }

    @Test func testAISummarizerServiceInsights() async throws {
        let sample = """
        The Time Traveller was expounding a recondite matter to us. His grey eyes shone and twinkled, and his usually pale face was flushed and animated. The fire burned brightly, and the soft radiance of the incandescent lights in the lilies of silver caught the bubbles that flashed and passed in our glasses. Our chairs, being his patents, embraced and caressed us rather than submitted to be sat upon.
        There was that luxurious after-dinner atmosphere when thought roams gracefully free of the trammels of precision. He put it to us that time is simply a fourth dimension of space. Weena later accompanied him through the world of the Eloi and Morlocks.
        """
        let insights = await AISummarizerService.shared.generateInsights(for: sample, bookTitle: "The Time Machine")
        #expect(!insights.executiveSummary.isEmpty)
        #expect(insights.wordCount > 50)
        #expect(insights.estimatedReadMinutes >= 1)
        #expect(!insights.toneAndMood.isEmpty)
        #expect(insights.characters.contains { $0.name.contains("Time Traveller") || $0.name.contains("Weena") })
    }

    @Test func testAppleIntelligenceIntentsExecution() async throws {
        let intent = GetCurrentReadingBookIntent()
        let result = try await intent.perform()
        // Should execute and produce a valid localized dialog
        #expect(result != nil)
    }

    @Test func testSpotlightAppleIntelligenceIndexing() async throws {
        let book = Book(
            title: "Dune",
            author: "Frank Herbert",
            content: "A beginning is the time for taking the most delicate care that the balances are correct.",
            format: .text
        )
        // Should index safely without crash or assertion error
        BookService.shared.indexBookInSpotlight(book)
        #expect(book.title == "Dune")
    }

    @Test func testComicAIInsightsAndTakeaways() async throws {
        let comicScript = """
        [Metadata]
        Title: The Cosmic Odyssey #1
        Summary: A deep space expedition encounters an ancient crystalline anomaly emitting temporal signals.
        Characters: Commander Valen, Lieutenant Kira, Dr. Aris, Prometheus AI

        [Page 1]
        Commander Valen: "All stations report. Are we holding orbital stability around the pulsar?"
        Lieutenant Kira: "Thrusters holding at 84 percent, Commander. We are steady."

        [Page 2]
        Dr. Aris: "Sensors are detecting tachyon particles originating from the core of the anomaly."
        Prometheus AI: "Warning: Gravitational shear approaching critical thresholds."

        [Page 3]
        Commander Valen: "Prepare the landing shuttle. We are going down to investigate the monolith."
        """

        let insights = await AISummarizerService.shared.generateInsights(for: comicScript, bookTitle: "The Cosmic Odyssey #1")
        #expect(!insights.executiveSummary.isEmpty)
        #expect(insights.keyTakeaways.count >= 2)
        #expect(insights.characters.contains { $0.name.contains("Valen") })
        #expect(insights.characters.contains { $0.name.contains("Kira") })
    }

    @Test func testComicParserExtractionAndMetadata() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let xmlContent = """
        <?xml version="1.0" encoding="utf-8"?>
        <ComicInfo>
            <Title>Nebula Raiders #1</Title>
            <Series>Nebula Raiders</Series>
            <Number>1</Number>
            <Writer>Elena Vance</Writer>
            <Summary>A pirate crew salvages a derelict dreadnought near Jupiter.</Summary>
            <Characters>Elena Vance, Jax, Cora</Characters>
        </ComicInfo>
        """
        try xmlContent.write(to: tempDir.appendingPathComponent("ComicInfo.xml"), atomically: true, encoding: .utf8)
        let ocr = "[Page 1]\nElena: \"Look at that hull breach!\"\nJax: \"Stay alert, sensors are glitching.\""
        try ocr.write(to: tempDir.appendingPathComponent("ocr_transcript.txt"), atomically: true, encoding: .utf8)

        let extracted = ComicParser.shared.extractTextFromComic(bookDir: tempDir)
        #expect(extracted.contains("Nebula Raiders"))
        #expect(extracted.contains("derelict dreadnought"))
        #expect(extracted.contains("hull breach"))
    }

    @Test func testTypeSafeSemanticConceptFindInComic() async throws {
        let comicScript = """
        [Page 1]
        Commander Valen: "All stations report. Are we holding orbital stability around the pulsar?"
        Lieutenant Kira: "Thrusters holding at 84 percent, Commander. We are steady."

        [Page 2]
        Dr. Aris: "Sensors are detecting tachyon particles originating from the core of the anomaly."
        Prometheus AI: "Warning: Gravitational shear approaching critical thresholds."

        [Page 3]
        Commander Valen: "Prepare the landing shuttle. We are going down to investigate the alien monolith."
        """

        let result = await TypeSafeService.shared.semanticFind(query: "alien monolith anomaly", inDocument: comicScript)
        #expect(result.verdict == .answered || result.verdict == .partial)
        #expect(result.existsScore >= 0.50)
        #expect(!result.matches.isEmpty)
        #expect(result.matches.first?.excerpt.contains("monolith") == true || result.matches.first?.excerpt.contains("anomaly") == true)
    }
}
