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

  private var contextualSuggestions: [String] {
    let titleLower = book.title.lowercased()
    if titleLower.contains("alice") || titleLower.contains("wonderland") {
      return [
        "Rabbit with watch",
        "Down the rabbit-hole",
        "Curiouser and curiouser",
        "Pool of tears"
      ]
    } else if titleLower.contains("pride") || titleLower.contains("prejudice") {
      return [
        "Single man of large fortune",
        "Netherfield Park",
        "Marriage and daughters",
        "Mr. Bennet's reply"
      ]
    } else if titleLower.contains("time") {
      return [
        "Time machine invention",
        "Levers for travelling",
        "Incandescent lights",
        "Recondite matter"
      ]
    } else {
      return [
        "First meeting",
        "Secret revealed",
        "Journey begins",
        "Decisive moment"
      ]
    }
  }

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
          VStack(spacing: DS.Spacing.sm) {
            ProgressView()
              .controlSize(.large)
              .tint(theme.textColor)
            Text("Scanning with TypeSafe System One...")
              .font(.subheadline.weight(.medium))
              .foregroundColor(theme.textColor.opacity(0.8))
            Text("Evaluating semantic passages & existence probabilities")
              .font(.caption2)
              .foregroundColor(theme.textColor.opacity(0.5))
          }
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
      Text("RECOMMENDED QUERIES FOR THIS BOOK")
        .font(.caption2.bold())
        .foregroundColor(theme.textColor.opacity(0.5))

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: DS.Spacing.xs) {
          ForEach(contextualSuggestions, id: \.self) { suggestion in
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
      Image(systemName: "sparkles")
        .font(.system(size: 40))
        .foregroundColor(theme.textColor.opacity(0.3))

      Text("TypeSafe System One")
        .font(.headline)
        .foregroundColor(theme.textColor)

      Text("Vectorless semantic passage localization powered by TypeSafe AI (Jev).\nSearch by concepts, actions, or descriptions instead of exact keywords.")
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

        if result.isLiveAI {
          Text("• Live TypeSafe AI")
            .font(.caption2.weight(.semibold))
            .foregroundColor(.green)
        }

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
          Text("No matching passages found for this query in the document.")
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
      let documentText = book.resolveSearchableContent()
      let result = await TypeSafeService.shared.semanticFind(query: query, inDocument: documentText)

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

// MARK: - Match Row Component

private struct MatchRowView: View {
  let match: TypeSafeService.SemanticMatch
  let theme: AppTheme
  let onSelect: () -> Void

  var body: some View {
    Button(action: onSelect) {
      VStack(alignment: .leading, spacing: DS.Spacing.xs) {
        HStack {
          Text(match.lineID)
            .font(.caption2.monospaced().bold())
            .foregroundColor(theme.textColor.opacity(0.45))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(theme.textColor.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 4))

          Spacer()

          HStack(spacing: 4) {
            Image(systemName: "sparkles")
              .font(.caption2)
            Text("\(match.relevancePercentage)% relevance")
              .font(.caption2.bold())
          }
          .foregroundColor(relevanceColor(match.relevance))
        }

        Text(match.excerpt)
          .font(.subheadline)
          .foregroundColor(theme.textColor)
          .lineLimit(4)
          .multilineTextAlignment(.leading)
      }
      .padding(.vertical, 4)
    }
    .buttonStyle(.plain)
  }

  private func relevanceColor(_ relevance: Double) -> Color {
    if relevance >= 0.75 {
      return .green
    } else if relevance >= 0.50 {
      return .orange
    } else {
      return .secondary
    }
  }
}
