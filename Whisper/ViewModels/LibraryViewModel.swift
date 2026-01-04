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
    
    // In a real app with SwiftData @Query in the view, we might filter there or here. 
    // For MVVM purity, we can handle logic here, but SwiftData @Query is very View-centric.
    // We will use this VM for auxiliary logic and maybe actions.
    
    func filterBooks(_ books: [Book]) -> [Book] {
        if searchText.isEmpty {
            return books
        } else {
            return books.filter { $0.title.localizedCaseInsensitiveContains(searchText) || $0.author.localizedCaseInsensitiveContains(searchText) }
        }
    }
}
