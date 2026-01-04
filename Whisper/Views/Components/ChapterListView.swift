//
//  ChapterListView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI

struct Chapter: Identifiable, Codable {
  var id = UUID()
  let title: String
  let path: String

  enum CodingKeys: String, CodingKey {
    case id, title, path
  }
}

struct ChapterListView: View {
  let bookDir: URL
  @Binding var isPresented: Bool
  let onSelect: (String) -> Void

  @State private var chapters: [Chapter] = []

  var body: some View {
    NavigationStack {
      List(chapters) { chapter in
        Button(action: {
          onSelect(chapter.path)
          isPresented = false
        }) {
          Text(chapter.title)
            .foregroundColor(.primary)
        }
      }
      .navigationTitle("Table of Contents")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Close") { isPresented = false }
        }
      }
      .onAppear(perform: loadTOC)
      .overlay {
        if chapters.isEmpty {
          ContentUnavailableView("No Chapters Found", systemImage: "list.bullet.rectangle.portrait")
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  func loadTOC() {
    let tocURL = bookDir.appendingPathComponent("toc.json")
    do {
      let data = try Data(contentsOf: tocURL)
      // Reuse the structure defined implicitly or explicitly.
      // In EpubParser it was TOCItem (id, title, path).
      // We need to match that structure.
      // Let's redefine 'Chapter' to match what we saved or reuse a shared type if possible.
      // Since we can't easily share types across FILES without a common model file (which we have but didn't update),
      // I'll ensure `Chapter` matches the JSON structure.
      // EpubParser uses `id` (UUID), `title`, `path`.
      chapters = try JSONDecoder().decode([Chapter].self, from: data)
    } catch {
      print("Failed to load TOC: \(error)")
    }
  }
}
