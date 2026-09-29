//
//  BookmarksList.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI

struct BookmarksList: View {
    @Bindable var book: Book
    var currentChapterPath: String? = nil
    var currentLocation: Int = 0
    var onSelectChapter: ((Chapter) -> Void)? = nil
    var onSelectBookmark: ((Bookmark) -> Void)? = nil
    var onFindCharacter: ((String) -> Void)? = nil
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedSection: ReaderInspectorSection = .chapters
    @State private var chapters: [Chapter] = []
    @State private var entities: [TypeSafeService.CharacterLoreEntity] = []
    
    enum ReaderInspectorSection: String, CaseIterable, Identifiable {
        case chapters = "Chapters"
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
                    case .chapters:
                        chaptersListView
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
                loadChapters()
                loadEntities()
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Chapters List
    
    @ViewBuilder
    private var chaptersListView: some View {
        if chapters.isEmpty {
            ContentUnavailableView(
                "No Chapters Found",
                systemImage: "list.bullet.rectangle.portrait",
                description: Text("Table of contents is not available for this book.")
            )
        } else {
            List {
                ForEach(chapters) { chapter in
                    Button(action: {
                        onSelectChapter?(chapter)
                        dismiss()
                    }) {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: chapterIconName(for: book.format ?? .text))
                                .font(.body)
                                .foregroundColor(isChapterActive(chapter) ? DS.Colors.accent : .secondary)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(chapter.title)
                                    .font(.body.weight(isChapterActive(chapter) ? .semibold : .regular))
                                    .foregroundColor(isChapterActive(chapter) ? DS.Colors.accent : .primary)
                                
                                if let subtitle = chapter.subtitle {
                                    Text(subtitle)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            if isChapterActive(chapter) {
                                Text("Current")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(DS.Colors.accent.opacity(0.15)))
                                    .foregroundColor(DS.Colors.accent)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
        }
    }
    
    private func isChapterActive(_ chapter: Chapter) -> Bool {
        if let path = currentChapterPath, !path.isEmpty {
            return chapter.path == path || chapter.path.hasSuffix(path) || path.hasSuffix(chapter.path)
        }
        return chapter.pageOrLocation == currentLocation
    }
    
    private func chapterIconName(for format: BookFormat) -> String {
        switch format {
        case .epub: return "book.pages"
        case .pdf: return "doc.text"
        case .comic: return "photo.stack"
        case .text: return "text.alignleft"
        case .audiobook: return "headphones"
        }
    }
    
    private func loadChapters() {
        if chapters.isEmpty {
            chapters = ChapterService.shared.extractChapters(for: book)
        }
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
                LoreRowView(entity: entity) {
                    onFindCharacter?(entity.name)
                    dismiss()
                }
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
        case .audiobook:
            let mins = bookmark.pageOrLocation / 60
            let secs = bookmark.pageOrLocation % 60
            return String(format: "%d:%02d", mins, secs)
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
    var onSelect: (() -> Void)? = nil
    
    var body: some View {
        Button(action: { onSelect?() }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entity.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(entity.mentionCount) mentions")
                        .font(.caption2.bold())
                        .foregroundColor(DS.Colors.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(DS.Colors.accent.opacity(0.12))
                        )
                }
                
                HStack(alignment: .top, spacing: 6) {
                    Text(entity.role)
                        .font(.caption.bold())
                        .foregroundColor(DS.Colors.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(DS.Colors.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    
                    Text(entity.preview)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
