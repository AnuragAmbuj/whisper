//
//  SmartFindSheet.swift
//  Whisper
//
//  Created by Anurag Ambuj on 22/09/26.
//

import SwiftUI

struct SmartFindSheet: View {
  let book: Book
  let theme: AppTheme
  var onSelectSnippet: ((_ lineIndex: Int, _ text: String) -> Void)? = nil
  @Environment(\.dismiss) private var dismiss

  @State private var query: String = ""
  @State private var searchResult: TypeSafeService.SemanticFindResult? = nil
  @State private var isSearching: Bool = false

  private let exampleSuggestions = [
    "First meeting",
    "Secret revealed",
    "Journey begins",
    "Decisive moment"
  ]

  var body: some View {
    NavigationStack {
      VStack(spacing: DS.Spacing.md) {
        // Search bar
        searchBar
          .padding(.horizontal, DS.Spacing.lg)
          .padding(.top, DS.Spacing.sm)

        // Suggestion chips when query is empty
        if query.isEmpty {
          suggestionChips
            .padding(.horizontal, DS.Spacing.lg)
        }

        // Result Content
        if isSearching {
          Spacer()
          ProgressView("Scanning document semantically...")
            .foregroundColor(theme.textColor.opacity(0.8))
          Spacer()
        } else if let result = searchResult {
          resultView(result)
        } else {
          emptyPromptView
        }
      }
      .background(theme.backgroundColor.ignoresSafeArea())
      .navigationTitle("Smart Find")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            dismiss()
          }
          .foregroundColor(theme.textColor)
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  // MARK: - Subviews

  private var searchBar: some View {
    HStack(spacing: DS.Spacing.sm) {
      Image(systemName: "sparkle.magnifyingglass")
        .foregroundColor(theme.textColor.opacity(0.6))
        .font(.subheadline)

      TextField("Ask anything or describe a scene...", text: $query)
        .textFieldStyle(.plain)
        .foregroundColor(theme.textColor)
        .font(.body)
        .onSubmit {
          performSearch()
        }

      if !query.isEmpty {
        Button(action: {
          query = ""
          searchResult = nil
        }) {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(theme.textColor.opacity(0.5))
        }
        .buttonStyle(.plain)
      }

      Button(action: performSearch) {
        Text("Search")
          .font(.subheadline.bold())
          .foregroundColor(theme.backgroundColor)
          .padding(.horizontal, DS.Spacing.md)
          .padding(.vertical, DS.Spacing.xs)
          .background(theme.textColor)
          .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
      }
      .buttonStyle(.plain)
    }
    .padding(DS.Spacing.sm)
    .background(theme.textColor.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
  }

  private var suggestionChips: some View {
    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
      Text("NATURAL LANGUAGE SUGGESTIONS")
        .font(.caption2.bold())
        .foregroundColor(theme.textColor.opacity(0.5))

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: DS.Spacing.xs) {
          ForEach(exampleSuggestions, id: \.self) { suggestion in
            Button(action: {
              query = suggestion
              performSearch()
            }) {
              Text(suggestion)
                .font(.caption)
                .foregroundColor(theme.textColor.opacity(0.85))
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, 6)
                .background(theme.textColor.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  private var emptyPromptView: some View {
    VStack(spacing: DS.Spacing.md) {
      Spacer()
      Image(systemName: "brain.head.profile")
        .font(.system(size: 40))
        .foregroundColor(theme.textColor.opacity(0.3))

      Text("TypeSafe Semantic Search")
        .font(.headline)
        .foregroundColor(theme.textColor)

      Text("Search by concepts, questions, or descriptions instead of exact words.\nPowered by TypeSafe System One.")
        .font(.subheadline)
        .foregroundColor(theme.textColor.opacity(0.65))
        .multilineTextAlignment(.center)
        .padding(.horizontal, DS.Spacing.xl)
      Spacer()
    }
  }

  @ViewBuilder
  private func resultView(_ result: TypeSafeService.SemanticFindResult) -> some View {
    VStack(spacing: DS.Spacing.sm) {
      // Existence Verdict Banner
      HStack(spacing: DS.Spacing.xs) {
        Image(systemName: result.verdict.systemIcon)
          .foregroundColor(verdictColor(for: result.verdict))

        Text(result.verdict.rawValue)
          .font(.subheadline.bold())
          .foregroundColor(verdictColor(for: result.verdict))

        Spacer()

        Text("\(Int(result.existsScore * 100))% confidence")
          .font(.caption2)
          .foregroundColor(theme.textColor.opacity(0.6))
      }
      .padding(.horizontal, DS.Spacing.lg)
      .padding(.vertical, DS.Spacing.xs)
      .background(
        RoundedRectangle(cornerRadius: DS.Radius.sm)
          .fill(verdictColor(for: result.verdict).opacity(0.12))
      )
      .padding(.horizontal, DS.Spacing.lg)

      // Matches List
      if result.matches.isEmpty {
        VStack(spacing: DS.Spacing.sm) {
          Spacer()
          Text("No matching passages found for this query.")
            .font(.subheadline)
            .foregroundColor(theme.textColor.opacity(0.6))
          Spacer()
        }
      } else {
        List(result.matches, id: \.lineID) { match in
          MatchRowView(match: match, theme: theme) {
            onSelectSnippet?(match.lineIndex, match.excerpt)
            dismiss()
          }
          .listRowBackground(theme.backgroundColor)
        }
        #if os(iOS)
        .listStyle(.plain)
        #else
        .listStyle(.inset)
        #endif
      }
    }
  }

  // MARK: - Actions

  private func performSearch() {
    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

    isSearching = true
    Task {
      // Allow keyboard animation to settle
      try? await Task.sleep(nanoseconds: 150_000_000)

      let documentText = book.content
      let result = TypeSafeService.shared.semanticFind(query: query, inDocument: documentText)

      await MainActor.run {
        self.searchResult = result
        self.isSearching = false
      }
    }
  }

  private func verdictColor(for verdict: TypeSafeService.SemanticVerdict) -> Color {
    switch verdict {
    case .answered: return .green
    case .partial: return .orange
    case .absent: return .secondary
    }
  }
}

private struct MatchRowView: View {
  let match: TypeSafeService.SemanticMatch
  let theme: AppTheme
  let onSelect: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(match.lineID)
          .font(.caption2)
          .foregroundColor(theme.textColor)
        Spacer()
        Text("\(match.relevancePercentage)% match")
          .font(.caption2)
          .foregroundColor(theme.textColor)
      }
      Text(match.excerpt)
        .font(.body)
        .foregroundColor(theme.textColor)
        .lineLimit(4)
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .onTapGesture {
      onSelect()
    }
  }
}
