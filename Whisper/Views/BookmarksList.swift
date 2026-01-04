//
//  BookmarksList.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI

struct BookmarksList: View {
    @Bindable var book: Book
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackground()
                    .opacity(DS.BackgroundOpacity.overlay)
                    .ignoresSafeArea()
                
                if book.bookmarks.isEmpty {
                    ContentUnavailableView(
                        "No Bookmarks",
                        systemImage: "bookmark.slash",
                        description: Text("Tap the bookmark icon while reading to save your spot.")
                    )
                    .foregroundColor(.white)
                } else {
                    List {
                        ForEach(book.bookmarks) { bookmark in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Page \(bookmark.pageOrLocation)")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    if let note = bookmark.note {
                                        Text(note)
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(DS.Opacity.tertiary))
                                    }
                                }
                                Spacer()
                                Text(bookmark.date.formatted(.relative(presentation: .named)))
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(DS.Opacity.quaternary))
                            }
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(DS.Radius.md)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        .onDelete(perform: deleteBookmark)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Bookmarks")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
    
    func deleteBookmark(at offsets: IndexSet) {
        book.bookmarks.remove(atOffsets: offsets)
        // In real SwiftData, context would auto-save or might need explicit save
    }
}

#Preview {
    let mockBook = Book(title: "Preview Book", author: "Author", coverImageName: "", content: "Content")
    mockBook.bookmarks.append(Bookmark(pageOrLocation: 10, note: "Interesting part"))
    
    return BookmarksList(book: mockBook)
}
