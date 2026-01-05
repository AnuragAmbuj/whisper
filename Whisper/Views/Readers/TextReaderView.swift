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
    
    init(book: Book, theme: AppTheme, fontSize: Double, lineHeight: CGFloat) {
        self.book = book
        self.theme = theme
        self.fontSize = fontSize
        self.lineHeight = lineHeight
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.lineHeight) {
                Text(book.title)
                    .font(.custom(theme.fontName, size: fontSize * 1.5))
                    .fontWeight(.bold)
                    .foregroundColor(theme.textColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
                
                Text(book.content)
                    .font(.custom(theme.fontName, size: fontSize))
                    .foregroundColor(theme.textColor)
                    .lineSpacing(theme.lineHeight)
                    .padding(.horizontal)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity)
        .background(theme.backgroundColor)
    }
}