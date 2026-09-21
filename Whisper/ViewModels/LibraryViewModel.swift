//
//  LibraryViewModel.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import Foundation
import SwiftData
import SwiftUI

@Observable
class LibraryViewModel {
    var searchText: String = ""
    var selectedCategory: String = "All"
    let categories: [String] = ["All", "EPUB", "PDF", "Comics", "Text"]
    
    func filterBooks(_ books: [Book]) -> [Book] {
        var result = books
        
        if selectedCategory != "All" {
            result = result.filter { book in
                let fmt = book.format ?? .text
                switch selectedCategory {
                case "EPUB":
                    return fmt == .epub
                case "PDF":
                    return fmt == .pdf
                case "Comics":
                    return fmt == .comic
                case "Text":
                    return fmt == .text
                default:
                    return true
                }
            }
        }
        
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(trimmedQuery) ||
                $0.author.localizedCaseInsensitiveContains(trimmedQuery)
            }
        }
        
        return result
    }
}
