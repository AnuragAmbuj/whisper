//
//  StoreBook.swift
//  Whisper
//
//  Created by Anurag Ambuj on 18/09/26.
//

import Foundation

struct StoreBook: Identifiable, Hashable {
    let id: UUID
    let title: String
    let author: String
    let category: String
    let summary: String
    let price: String
    let isWhisperPlusIncluded: Bool
    let rating: Double
    let reviewCount: Int
    let format: BookFormat
    let pageCount: Int
    let sampleContent: String
    
    init(
        id: UUID = UUID(),
        title: String,
        author: String,
        category: String,
        summary: String,
        price: String,
        isWhisperPlusIncluded: Bool = true,
        rating: Double = 4.8,
        reviewCount: Int = 120,
        format: BookFormat = .text,
        pageCount: Int = 300,
        sampleContent: String = ""
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.category = category
        self.summary = summary
        self.price = price
        self.isWhisperPlusIncluded = isWhisperPlusIncluded
        self.rating = rating
        self.reviewCount = reviewCount
        self.format = format
        self.pageCount = pageCount
        self.sampleContent = sampleContent
    }
}
