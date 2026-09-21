//
//  StoreService.swift
//  Whisper
//
//  Created by Anurag Ambuj on 18/09/26.
//

import Foundation
import SwiftData

@Observable
final class StoreService {
    static let shared = StoreService()
    
    private let subscriptionKey = "WhisperPlusSubscriptionActive"
    private let purchasedBooksKey = "WhisperPurchasedBookIDs"
    
    var isWhisperPlusSubscribed: Bool {
        didSet {
            UserDefaults.standard.set(isWhisperPlusSubscribed, forKey: subscriptionKey)
        }
    }
    
    var purchasedBookIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(purchasedBookIDs), forKey: purchasedBooksKey)
        }
    }
    
    let categories = ["All", "Bestsellers", "Sci-Fi", "Comics", "Classics", "Tech"]
    
    private(set) var catalog: [StoreBook] = []
    
    private init() {
        self.isWhisperPlusSubscribed = UserDefaults.standard.bool(forKey: subscriptionKey)
        let savedIDs = UserDefaults.standard.stringArray(forKey: purchasedBooksKey) ?? []
        self.purchasedBookIDs = Set(savedIDs)
        self.catalog = Self.generateCuratedCatalog()
    }
    
    func isPurchased(id: UUID) -> Bool {
        purchasedBookIDs.contains(id.uuidString)
    }
    
    func purchaseOrDownload(_ storeBook: StoreBook, context: ModelContext) -> Book {
        purchasedBookIDs.insert(storeBook.id.uuidString)
        
        let newBook = Book(
            id: storeBook.id,
            title: storeBook.title,
            author: storeBook.author,
            coverImageName: "",
            content: storeBook.sampleContent,
            progress: 0.0,
            format: storeBook.format
        )
        
        context.insert(newBook)
        try? context.save()
        return newBook
    }
    
    private static func generateCuratedCatalog() -> [StoreBook] {
        [
            StoreBook(
                title: "Project Hail Mary",
                author: "Andy Weir",
                category: "Sci-Fi",
                summary: "Ryland Grace is the sole survivor on a desperate, last-chance mission to save humanity from an extinction-level event.",
                price: "$9.99",
                isWhisperPlusIncluded: true,
                rating: 4.9,
                reviewCount: 3420,
                format: .epub,
                pageCount: 496,
                sampleContent: "I'm asleep. Then I'm not.\n\nI open my eyes. There is a bright, white light. Two circular shapes stare down at me. Robots. No, cameras.\n\n\"What is two plus two?\" a synthesized voice asks from above."
            ),
            StoreBook(
                title: "Cyberpunk: Neon District #1",
                author: "M. K. Vance",
                category: "Comics",
                summary: "High-octane graphic comic following cyber-mercenary Ren as she uncovers high-level corporate espionage in Neo-Shinjuku.",
                price: "$4.99",
                isWhisperPlusIncluded: true,
                rating: 4.8,
                reviewCount: 890,
                format: .comic,
                pageCount: 48,
                sampleContent: "Night in the Neon District never ends. Rain falls through holographic advertisements of synthetic memories."
            ),
            StoreBook(
                title: "Atomic Habits",
                author: "James Clear",
                category: "Bestsellers",
                summary: "An easy & proven way to build good habits & break bad ones. Small changes lead to remarkable results.",
                price: "$11.99",
                isWhisperPlusIncluded: true,
                rating: 4.9,
                reviewCount: 15400,
                format: .text,
                pageCount: 320,
                sampleContent: "The fate of British Cycling changed one day in 2003. The organization had hired Dave Brailsford as its new performance director..."
            ),
            StoreBook(
                title: "Designing Data-Intensive Applications",
                author: "Martin Kleppmann",
                category: "Tech",
                summary: "The definitive guide to distributed data architectures, replication, partitioning, consistency, and fault tolerance.",
                price: "$19.99",
                isWhisperPlusIncluded: false,
                rating: 4.9,
                reviewCount: 4120,
                format: .pdf,
                pageCount: 616,
                sampleContent: "Data-intensive applications are pushing the boundaries of what is possible by making use of capabilities that were previously unprecedented."
            ),
            StoreBook(
                title: "Dune: Chronicles",
                author: "Frank Herbert",
                category: "Sci-Fi",
                summary: "Set on the desert planet Arrakis, Dune is the story of the boy Paul Atreides, heir to a noble family tasked with ruling an inhospitable world.",
                price: "$8.99",
                isWhisperPlusIncluded: true,
                rating: 4.8,
                reviewCount: 9800,
                format: .epub,
                pageCount: 680,
                sampleContent: "A beginning is the time for taking the most delicate care that the balances are correct."
            ),
            StoreBook(
                title: "1984: Definitive Edition",
                author: "George Orwell",
                category: "Classics",
                summary: "Winston Smith lives in a society where the Party scrutinizes human actions with ever watchful Big Brother.",
                price: "Free",
                isWhisperPlusIncluded: true,
                rating: 4.7,
                reviewCount: 18200,
                format: .text,
                pageCount: 328,
                sampleContent: "It was a bright cold day in April, and the clocks were striking thirteen."
            )
        ]
    }
}
