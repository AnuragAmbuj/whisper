//
//  AIReaderInsightsSheet.swift
//  Whisper
//
//  Created by Anurag Ambuj on 24/09/26.
//

import SwiftUI

struct AIReaderInsightsSheet: View {
    let book: Book
    var currentChapterPath: String? = nil
    var currentPageIndex: Int = 0
    @Environment(\.dismiss) private var dismiss
    
    @State private var insights: AISummarizerService.AIReadingInsights? = nil
    @State private var isLoading: Bool = true
    @State private var selectedTab: InsightsTab = .summary
    @State private var analysisScope: AnalysisScope = .currentSection
    @State private var showCopiedAlert: Bool = false
    
    enum AnalysisScope: String, CaseIterable, Identifiable {
        case currentSection = "Current Section"
        case fullBook = "Full Book"
        var id: String { rawValue }
    }
    
    enum InsightsTab: String, CaseIterable, Identifiable {
        case summary = "Synopsis"
        case takeaways = "Takeaways"
        case characters = "Dramatis Personae"
        
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
                        
                        Text("Synthesizing with Apple Intelligence...")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)
                        
                        Text("Extracting character dynamics and thematic structure")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                } else if let insights = insights {
                    ScrollView {
                        VStack(spacing: DS.Spacing.md) {
                            // Apple Intelligence Neural Engine Banner
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .symbolRenderingMode(.multicolor)
                                    .font(.caption.weight(.bold))
                                
                                Text(insights.isLiveAI ? "TypeSafe System One & Apple Neural AI" : "Apple Intelligence & On-Device Neural Synthesis")
                                    .font(.caption2.weight(.bold))
                                
                                Spacer()
                                
                                Text(insights.literaryGenre)
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(DS.Colors.accent.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                LinearGradient(
                                    colors: [
                                        DS.Colors.accent.opacity(0.12),
                                        Color.purple.opacity(0.08)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                    .stroke(DS.Colors.accent.opacity(0.2), lineWidth: 1)
                            )
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.top, DS.Spacing.xs)
                            
                            // Scope Picker (Section vs Book)
                            if (book.format ?? .text) != .text || currentChapterPath != nil {
                                Picker("Scope", selection: $analysisScope) {
                                    ForEach(AnalysisScope.allCases) { scope in
                                        Text(scope.rawValue).tag(scope)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal, DS.Spacing.md)
                                .onChange(of: analysisScope) { _, _ in
                                    Task {
                                        await loadInsights()
                                    }
                                }
                            }
                            
                            // Header Metric Pill
                            HStack(spacing: DS.Spacing.sm) {
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
                            
                            // Segmented Selector
                            Picker("Insights", selection: $selectedTab) {
                                ForEach(InsightsTab.allCases) { tab in
                                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, DS.Spacing.md)
                            
                            // Content Cards
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
                ToolbarItem(placement: .cancellationAction) {
                    if let ins = insights {
                        Button(action: {
                            copyInsightsToClipboard(insights: ins)
                        }) {
                            Image(systemName: "doc.on.doc")
                        }
                        .help("Copy AI Insights to Clipboard")
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
            .overlay(alignment: .bottom) {
                if showCopiedAlert {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Copied insights to clipboard")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .shadow(radius: 8)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(analysisScope == .currentSection ? "Section Synopsis" : "Full Work Overview")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Synthesized by Apple Intelligence")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Render executive summary paragraphs
            let paragraphs = insights.executiveSummary.components(separatedBy: "\n\n")
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, para in
                Text(para)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineSpacing(6)
                    .padding(.vertical, 2)
                    .textSelection(.enabled)
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
    
    private func takeawaysCard(insights: AISummarizerService.AIReadingInsights) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Key Takeaways & Core Ideas")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Thematic analysis and narrative takeaways")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            if insights.keyTakeaways.isEmpty {
                Text("No specific analytical takeaways generated for this section.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: DS.Spacing.md) {
                    ForEach(Array(insights.keyTakeaways.enumerated()), id: \.offset) { index, takeaway in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                                Text("\(index + 1)")
                                    .font(.caption.bold())
                                    .foregroundColor(DS.Colors.accent)
                                    .frame(width: 24, height: 24)
                                    .background(DS.Colors.accent.opacity(0.12))
                                    .clipShape(Circle())
                                
                                // Parse Title vs Content if formatted with a colon
                                let parts = takeaway.components(separatedBy: ": ")
                                if parts.count >= 2 {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(parts[0])
                                            .font(.subheadline.bold())
                                            .foregroundColor(DS.Colors.accent)
                                        Text(parts.dropFirst().joined(separator: ": "))
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                            .lineSpacing(4)
                                            .textSelection(.enabled)
                                    }
                                } else {
                                    Text(takeaway)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                        .lineSpacing(4)
                                        .textSelection(.enabled)
                                }
                                
                                Spacer()
                            }
                        }
                        .padding(10)
                        .background(DS.Colors.background.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
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
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dramatis Personae & Entities")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Key figures and roles active in this section")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
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
                                        .textSelection(.enabled)
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
        
        let contentToAnalyze: String
        let sectionTitle: String
        
        if analysisScope == .currentSection {
            let section = book.resolveSectionContent(chapterPath: currentChapterPath, pageIndex: currentPageIndex)
            sectionTitle = section.title
            contentToAnalyze = section.content
        } else {
            sectionTitle = book.title
            let full = book.resolveSearchableContent()
            contentToAnalyze = full.isEmpty ? book.content : full
        }
        
        let analysis = await AISummarizerService.shared.generateInsights(
            for: contentToAnalyze,
            bookTitle: book.title,
            sectionName: sectionTitle
        )
        
        await MainActor.run {
            self.insights = analysis
            self.isLoading = false
        }
    }
    
    private func copyInsightsToClipboard(insights: AISummarizerService.AIReadingInsights) {
        var text = "AI Reading Insights for \(insights.title)\n"
        text += "Mood: \(insights.toneAndMood) • Genre: \(insights.literaryGenre)\n\n"
        text += "--- SYNOPSIS ---\n\(insights.executiveSummary)\n\n"
        text += "--- KEY TAKEAWAYS ---\n"
        for (i, takeaway) in insights.keyTakeaways.enumerated() {
            text += "\(i + 1). \(takeaway)\n"
        }
        
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        
        withAnimation {
            showCopiedAlert = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showCopiedAlert = false
            }
        }
    }
}
