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
    var onFindCharacter: ((String) -> Void)? = nil
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedSection: ReaderInspectorSection = .bookmarks
    @State private var entities: [TypeSafeService.CharacterLoreEntity] = []
    
    enum ReaderInspectorSection: String, CaseIterable, Identifiable {
        case bookmarks = "Bookmarks"
        case characters = "Characters & Lore"
        
        var id: String { rawValue }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $selectedSection) {
                    ForEach(ReaderInspectorSection.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)
                
                Group {
                    switch selectedSection {
                    case .bookmarks:
                        bookmarksListView
                    case .characters:
                        charactersLoreView
                    }
                }
            }
            .navigationTitle(selectedSection.rawValue)
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
            .onAppear {
                loadEntities()
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Bookmarks List
    
    @ViewBuilder
    private var bookmarksListView: some View {
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
    
    // MARK: - Characters & Lore (Dramatis Personae)
    
    @ViewBuilder
    private var charactersLoreView: some View {
        if entities.isEmpty {
            ContentUnavailableView(
                "No Key Figures Discovered",
                systemImage: "person.2",
                description: Text("TypeSafe AI analyzes text to extract figures and key lore.")
            )
        } else {
            List(entities, id: \.name) { entity in
                LoreRowView(entity: entity)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
        }
    }
    
    private func loadEntities() {
        if entities.isEmpty {
            let searchableText = book.resolveSearchableContent()
            entities = TypeSafeService.shared.extractDramatisPersonae(from: searchableText)
        }
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

private struct LoreRowView: View {
    let entity: TypeSafeService.CharacterLoreEntity
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entity.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Text("\(entity.mentionCount) mentions")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(entity.role)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(entity.preview)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
