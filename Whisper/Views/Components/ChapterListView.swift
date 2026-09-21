//
//  ChapterListView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI

struct Chapter: Identifiable, Codable {
  var id: UUID = UUID()
  let title: String
  let path: String

  enum CodingKeys: String, CodingKey {
    case id, title, path
  }

  init(id: UUID = UUID(), title: String, path: String) {
    self.id = id
    self.title = title
    self.path = path
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
    self.title = try container.decode(String.self, forKey: .title)
    self.path = try container.decode(String.self, forKey: .path)
  }
}

struct ChapterListView: View {
  let bookDir: URL
  var chapterPaths: [String] = []
  @Binding var isPresented: Bool
  let onSelect: (String) -> Void

  @State private var chapters: [Chapter] = []

  var body: some View {
    NavigationStack {
      Group {
        if chapters.isEmpty {
          ContentUnavailableView(
            "No Chapters Found",
            systemImage: "list.bullet.rectangle.portrait",
            description: Text("Table of contents is not available for this book.")
          )
        } else {
          List(chapters) { chapter in
            Button(action: {
              onSelect(chapter.path)
              isPresented = false
            }) {
              HStack {
                Text(chapter.title)
                  .font(.body)
                  .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                  .font(.caption2.weight(.semibold))
                  .foregroundColor(.secondary)
              }
              .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
          }
          #if os(iOS)
          .listStyle(.insetGrouped)
          #else
          .listStyle(.inset)
          #endif
        }
      }
      .navigationTitle("Table of Contents")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { isPresented = false }
        }
      }
      .onAppear(perform: loadTOC)
    }
    .presentationDetents([.medium, .large])
  }

  func loadTOC() {
    let tocURL = bookDir.appendingPathComponent("toc.json")
    if let data = try? Data(contentsOf: tocURL),
       let loaded = try? JSONDecoder().decode([Chapter].self, from: data),
       !loaded.isEmpty {
      self.chapters = loaded
      return
    }

    // Fallback: generate chapters from chapterPaths
    if !chapterPaths.isEmpty {
      self.chapters = chapterPaths.enumerated().map { index, path in
        let filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let formattedTitle = filename.replacingOccurrences(of: "_", with: " ")
          .replacingOccurrences(of: "-", with: " ")
          .capitalized
        return Chapter(title: formattedTitle.isEmpty ? "Chapter \(index + 1)" : formattedTitle, path: path)
      }
    }
  }
}
