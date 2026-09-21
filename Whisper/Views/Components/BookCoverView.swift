//
//  BookCoverView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI

struct BookCoverView: View {
    let book: Book
    var showMetadata: Bool = true
    
    private var coverBackground: Color {
        DS.Colors.cardBackground
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            coverImage
            
            if showMetadata {
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(book.author)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if book.progress > 0 {
                        ProgressView(value: book.progress)
                            .tint(DS.Colors.accent)
                            .scaleEffect(x: 1, y: 0.5, anchor: .center)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
            }
        }
        .frame(maxWidth: DS.Layout.gridItemMax)
    }
    
    private var coverImage: some View {
        ZStack(alignment: .topTrailing) {
            CachedAsyncImage(
                imageName: book.coverImageName,
                placeholder: {
                    coverPlaceholder
                },
                fallback: {
                    generatedCover
                }
            )
            .aspectRatio(2/3, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Colors.border, lineWidth: 1)
            )
            
            // Subtle format badge at top-right
            Text((book.format ?? .text).rawValue.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(DS.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(DS.Colors.border, lineWidth: 0.5)
                )
                .padding(8)
        }
    }
    
    private var coverPlaceholder: some View {
        Rectangle()
            .fill(coverBackground)
            .overlay {
                ProgressView()
                    .tint(.primary)
            }
    }
    
    private var generatedCover: some View {
        ZStack {
            Rectangle()
                .fill(coverBackground)
            
            VStack(spacing: DS.Spacing.sm) {
                Image(systemName: iconForFormat)
                    .font(.system(size: 30))
                    .foregroundColor(.primary)
                
                Text(book.title)
                    .font(.system(size: 13, weight: .bold, design: .serif))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 8)
                
                if !book.author.isEmpty {
                    Text(book.author)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.all, 12)
        }
    }
    
    private var iconForFormat: String {
        switch book.format ?? .text {
        case .epub: return "book.closed.fill"
        case .pdf: return "doc.text.fill"
        case .comic: return "photo.stack.fill"
        case .text: return "text.quote"
        }
    }
}

#Preview {
    let mockBook = Book(
        title: "The Great Gatsby", author: "F. Scott Fitzgerald", coverImageName: "", content: "")
    return BookCoverView(book: mockBook)
        .padding()
        .background(Color.black)
}
