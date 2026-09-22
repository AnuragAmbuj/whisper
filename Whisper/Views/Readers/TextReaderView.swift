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
    @Binding var showControls: Bool
    
    init(book: Book, theme: AppTheme, fontSize: Double, lineHeight: CGFloat, showControls: Binding<Bool> = .constant(true)) {
        self.book = book
        self.theme = theme
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self._showControls = showControls
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
                
                Text(book.content)
                    .font(bodyFont)
                    .foregroundColor(theme.textColor)
                    .lineSpacing(lineHeight * 3.5)
                    .textSelection(.enabled)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.backgroundColor)
        .animation(.easeInOut(duration: 0.25), value: theme.style)
    }
}
