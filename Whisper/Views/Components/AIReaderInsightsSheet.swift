//
//  AIReaderInsightsSheet.swift
//  Whisper
//
//  Created by Anurag Ambuj on 24/09/26.
//

import SwiftUI

struct AIReaderInsightsSheet: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    
    @State private var insights: AISummarizerService.AIReadingInsights? = nil
    @State private var isLoading: Bool = true
    @State private var selectedTab: InsightsTab = .summary
    
    enum InsightsTab: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case takeaways = "Takeaways"
        case characters = "Characters"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .summary: return "sparkles"
            case .takeaways: return "list.bullet.clipboard"
            case .characters: return "person.2.fill"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DS.Colors.background.ignoresSafeArea()
                
                if isLoading {
                    VStack(spacing: DS.Spacing.md) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(DS.Colors.accent)
                        
                        Text("Analyzing with Apple Intelligence...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if let insights = insights {
                    ScrollView {
                        VStack(spacing: DS.Spacing.lg) {
                            // Header Metric Pill
                            HStack(spacing: DS.Spacing.md) {
                                Label(insights.toneAndMood, systemImage: insights.moodIcon)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(DS.Colors.accent.opacity(0.12))
                                    .foregroundColor(DS.Colors.accent)
                                    .clipShape(Capsule())
                                
                                Spacer()
                                
                                Label("\(insights.estimatedReadMinutes) min read", systemImage: "clock.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text("•")
                                    .foregroundColor(.secondary)
                                
                                Text("\(insights.wordCount) words")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.top, DS.Spacing.xs)
                            
                            // Segmented Selector
                            Picker("Insights", selection: $selectedTab) {
                                ForEach(InsightsTab.allCases) { tab in
                                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, DS.Spacing.md)
                            
                            // Content
                            switch selectedTab {
                            case .summary:
                                summaryCard(insights: insights)
                            case .takeaways:
                                takeawaysCard(insights: insights)
                            case .characters:
                                charactersCard(insights: insights)
                            }
                        }
                        .padding(.vertical, DS.Spacing.md)
                        .frame(maxWidth: 640)
                        .padding(.horizontal, DS.Spacing.sm)
                    }
                }
            }
            .navigationTitle("AI Reading Insights")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
        .task {
            await loadInsights()
        }
    }
    
    private func summaryCard(insights: AISummarizerService.AIReadingInsights) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(DS.Colors.accent)
                    .font(.title3)
                
                Text("Chapter Synopsis")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            Text(insights.executiveSummary)
                .font(.body)
                .foregroundColor(.primary)
                .lineSpacing(6)
                .padding(.vertical, 4)
                .textSelection(.enabled)
        }
        .padding(DS.Spacing.lg)
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Colors.border, lineWidth: 1)
        )
        .padding(.horizontal, DS.Spacing.md)
    }
    
    private func takeawaysCard(insights: AISummarizerService.AIReadingInsights) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                    .font(.title3)
                
                Text("Key Takeaways & Core Ideas")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            if insights.keyTakeaways.isEmpty {
                Text("No specific bulleted takeaways identified in this section.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: DS.Spacing.md) {
                    ForEach(Array(insights.keyTakeaways.enumerated()), id: \.offset) { index, takeaway in
                        HStack(alignment: .top, spacing: DS.Spacing.sm) {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundColor(DS.Colors.accent)
                                .frame(width: 22, height: 22)
                                .background(DS.Colors.accent.opacity(0.12))
                                .clipShape(Circle())
                            
                            Text(takeaway)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .lineSpacing(4)
                                .textSelection(.enabled)
                            
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(DS.Spacing.lg)
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Colors.border, lineWidth: 1)
        )
        .padding(.horizontal, DS.Spacing.md)
    }
    
    private func charactersCard(insights: AISummarizerService.AIReadingInsights) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .foregroundColor(DS.Colors.accent)
                    .font(.title3)
                
                Text("Dramatis Personae (Characters)")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            if insights.characters.isEmpty {
                VStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    
                    Text("No Character Entities")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    
                    Text("This document is instructional, conceptual, or non-fiction. It focuses on architecture, gestures, and features rather than narrative characters.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Spacing.md)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.md)
            } else {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(insights.characters) { char in
                        HStack(alignment: .top, spacing: DS.Spacing.md) {
                            ZStack {
                                Circle()
                                    .fill(DS.Colors.accent.opacity(0.12))
                                    .frame(width: 40, height: 40)
                                
                                Text(String(char.name.prefix(1)))
                                    .font(.headline)
                                    .foregroundColor(DS.Colors.accent)
                            }
                            
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(char.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.primary)
                                    
                                    if char.mentionCount > 0 {
                                        Text("\(char.mentionCount) mentions")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(DS.Colors.unselectedFill)
                                            .clipShape(Capsule())
                                    }
                                }
                                
                                Text(char.role)
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(DS.Colors.accent)
                                
                                if !char.preview.isEmpty {
                                    Text(char.preview)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        
                        if char.id != insights.characters.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(DS.Spacing.lg)
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Colors.border, lineWidth: 1)
        )
        .padding(.horizontal, DS.Spacing.md)
    }
    
    private func loadInsights() async {
        isLoading = true
        let searchable = book.resolveSearchableContent()
        let trimmedSearchable = searchable.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPlaceholder = book.content.hasPrefix("EPUB Content") ||
            book.content.hasPrefix("Comic Book -") ||
            book.content.hasPrefix("PDF Document -")
        
        let contentToAnalyze: String
        if !trimmedSearchable.isEmpty && (isPlaceholder || trimmedSearchable.count > book.content.count) {
            contentToAnalyze = trimmedSearchable
        } else if !book.content.isEmpty && !isPlaceholder {
            contentToAnalyze = book.content
        } else if !trimmedSearchable.isEmpty {
            contentToAnalyze = trimmedSearchable
        } else {
            contentToAnalyze = "\(book.title) by \(book.author)"
        }
        
        let analysis = await AISummarizerService.shared.generateInsights(for: contentToAnalyze, bookTitle: book.title)
        await MainActor.run {
            self.insights = analysis
            self.isLoading = false
        }
    }
}
