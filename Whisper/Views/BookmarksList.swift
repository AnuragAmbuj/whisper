//
//  BookmarksList.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI

struct BookmarksList: View {
    @Bindable var book: Book
    var onSelectBookmark: ((Bookmark) -> Void)? = nil
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Group {
                if book.safeBookmarks.isEmpty {
                    ContentUnavailableView(
                        "No Bookmarks",
                        systemImage: "bookmark.slash",
                        description: Text("Tap the bookmark icon while reading to save your spot.")
                    )
                } else {
                    List {
                        ForEach(book.safeBookmarks) { bookmark in
                            Button(action: {
                                onSelectBookmark?(bookmark)
                                dismiss()
                            }) {
                                HStack(alignment: .center) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(locationTitle(for: bookmark))
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        if let note = bookmark.note {
                                            Text(note)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(bookmark.date.formatted(.relative(presentation: .named)))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: deleteBookmark)
                    }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    #else
                    .listStyle(.inset)
                    #endif
                }
            }
            .navigationTitle("Bookmarks")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private func locationTitle(for bookmark: Bookmark) -> String {
        switch book.format ?? .text {
        case .pdf, .comic:
            return "Page \(bookmark.pageOrLocation + 1)"
        case .epub:
            return "Chapter \(bookmark.pageOrLocation + 1)"
        case .text:
            return "Position \(bookmark.pageOrLocation)%"
        }
    }
    
    func deleteBookmark(at offsets: IndexSet) {
        book.bookmarks?.remove(atOffsets: offsets)
    }
}

#Preview {
    let mockBook = Book(title: "Preview Book", author: "Author", coverImageName: "", content: "Content")
    mockBook.addBookmark(Bookmark(pageOrLocation: 10, note: "Interesting part"))
    
    return BookmarksList(book: mockBook)
}
