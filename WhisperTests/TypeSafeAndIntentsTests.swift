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
}
