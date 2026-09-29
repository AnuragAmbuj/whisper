//
//  TextReaderView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI

struct TextReaderView: View {
    let book: Book
    let theme: AppTheme
    let fontSize: Double
    let lineHeight: CGFloat
    @Binding var targetLocation: Int?
    @Binding var targetSearchSnippet: String?
    @Binding var showControls: Bool
    
    @State private var highlightedID: Int? = nil
    
    init(
        book: Book,
        theme: AppTheme,
        fontSize: Double,
        lineHeight: CGFloat,
        targetLocation: Binding<Int?> = .constant(nil),
        targetSearchSnippet: Binding<String?> = .constant(nil),
        showControls: Binding<Bool> = .constant(true)
    ) {
        self.book = book
        self.theme = theme
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self._targetLocation = targetLocation
        self._targetSearchSnippet = targetSearchSnippet
        self._showControls = showControls
    }
    
    struct ParagraphItem: Identifiable {
        let id: Int
        let text: String
        let isHeader: Bool
    }
    
    private var paragraphs: [ParagraphItem] {
        let lines = book.content.components(separatedBy: "\n")
        var result: [ParagraphItem] = []
        var currentChunk: [String] = []
        var chunkStartLine = 0
        
        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isHeader = trimmed.hasPrefix("#") ||
                           trimmed.hasPrefix("Chapter") ||
                           trimmed.hasPrefix("CHAPTER") ||
                           trimmed.hasPrefix("Part") ||
                           trimmed.hasPrefix("PART") ||
                           trimmed.hasPrefix("Section") ||
                           trimmed.hasPrefix("---")
            
            if isHeader {
                if !currentChunk.isEmpty {
                    result.append(ParagraphItem(id: chunkStartLine, text: currentChunk.joined(separator: "\n"), isHeader: false))
                    currentChunk.removeAll()
                }
                result.append(ParagraphItem(id: idx, text: line, isHeader: true))
                chunkStartLine = idx + 1
            } else if trimmed.isEmpty {
                if !currentChunk.isEmpty {
                    result.append(ParagraphItem(id: chunkStartLine, text: currentChunk.joined(separator: "\n"), isHeader: false))
                    currentChunk.removeAll()
                }
                chunkStartLine = idx + 1
            } else {
                if currentChunk.isEmpty {
                    chunkStartLine = idx
                }
                currentChunk.append(line)
            }
        }
        if !currentChunk.isEmpty {
            result.append(ParagraphItem(id: chunkStartLine, text: currentChunk.joined(separator: "\n"), isHeader: false))
        }
        return result.isEmpty ? [ParagraphItem(id: 0, text: book.content, isHeader: false)] : result
    }
    
    private var titleFont: Font {
        switch theme.fontName.lowercased() {
        case "serif":
            return .system(size: fontSize * 1.5, weight: .bold, design: .serif)
        case "sans", "system":
            return .system(size: fontSize * 1.5, weight: .bold, design: .default)
        case "mono", "monospace":
            return .system(size: fontSize * 1.5, weight: .bold, design: .monospaced)
        case "round", "rounded":
            return .system(size: fontSize * 1.5, weight: .bold, design: .rounded)
        default:
            return .custom(theme.fontName, size: fontSize * 1.5).bold()
        }
    }
    
    private var bodyFont: Font {
        switch theme.fontName.lowercased() {
        case "serif":
            return .system(size: fontSize, design: .serif)
        case "sans", "system":
            return .system(size: fontSize, design: .default)
        case "mono", "monospace":
            return .system(size: fontSize, design: .monospaced)
        case "round", "rounded":
            return .system(size: fontSize, design: .rounded)
        default:
            return .custom(theme.fontName, size: fontSize)
        }
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    Text(book.title)
                        .font(titleFont)
                        .foregroundColor(theme.textColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, max(68, DS.Spacing.xxl))
                    
                    if !book.author.isEmpty {
                        Text(book.author)
                            .font(bodyFont)
                            .foregroundColor(theme.textColor.opacity(0.7))
                            .padding(.bottom, DS.Spacing.sm)
                    }
                    
                    LazyVStack(alignment: .leading, spacing: DS.Spacing.md) {
                        ForEach(paragraphs) { item in
                            Text(item.text)
                                .font(item.isHeader ? titleFont : bodyFont)
                                .fontWeight(item.isHeader ? .bold : .regular)
                                .foregroundColor(theme.textColor)
                                .lineSpacing(lineHeight * 3.5)
                                .textSelection(.enabled)
                                .padding(.horizontal, highlightedID == item.id ? 8 : 0)
                                .padding(.vertical, highlightedID == item.id ? 4 : 0)
                                .background(
                                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                                        .fill(DS.Colors.accent.opacity(highlightedID == item.id ? 0.25 : 0.0))
                                )
                                .id(item.id)
                        }
                    }
                    .padding(.bottom, DS.Spacing.xxxl)
                }
                .padding(.horizontal, DS.Spacing.xxl)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
                .pinchToZoom(minScale: 0.85, maxScale: 3.0, doubleTapScale: 1.8)
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        showControls.toggle()
                    }
                }
            )
            .onChange(of: targetLocation) { _, newLoc in
                guard let target = newLoc else { return }
                scrollToLocation(target, proxy: proxy)
            }
            .onChange(of: targetSearchSnippet) { _, snippet in
                guard let text = snippet, !text.isEmpty else { return }
                scrollToSnippet(text, proxy: proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.backgroundColor)
        .animation(.easeInOut(duration: 0.25), value: theme.style)
    }
    
    private func scrollToLocation(_ target: Int, proxy: ScrollViewProxy) {
        let bestMatch = paragraphs.last(where: { $0.id <= target }) ?? paragraphs.first
        guard let item = bestMatch else { return }
        highlightedID = item.id
        withAnimation(.easeInOut(duration: 0.35)) {
            proxy.scrollTo(item.id, anchor: .center)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if highlightedID == item.id {
                withAnimation(.easeOut(duration: 0.5)) {
                    highlightedID = nil
                }
            }
        }
    }
    
    private func scrollToSnippet(_ snippet: String, proxy: ScrollViewProxy) {
        let clean = snippet.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let shortTerm = String(clean.prefix(35))
        
        let found = paragraphs.first(where: {
            $0.text.lowercased().contains(clean) || $0.text.lowercased().contains(shortTerm)
        })
        
        if let item = found {
            scrollToLocation(item.id, proxy: proxy)
        }
    }
}
