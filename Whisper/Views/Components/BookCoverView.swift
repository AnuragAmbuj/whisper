//
//  BookCoverView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI

struct BookCoverView: View {
    let book: Book
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                CachedAsyncImage(imageName: book.coverImageName) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.cyan.opacity(0.8), .blue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                }
                .aspectRatio(2/3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(book.title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    
                    Text(book.author)
                        .font(.caption)
                        .foregroundColor(.white.opacity(DS.Opacity.secondary))
                        .lineLimit(1)
                }
                .padding(DS.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
                .clipShape(
                    RoundedCornerShape(radius: DS.Radius.md, corners: [.bottomLeft, .bottomRight])
                )
            }
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(.white.opacity(DS.Opacity.stroke), lineWidth: 1)
            )
            .shadow(radius: DS.Shadow.sm.radius)
        }
        .frame(maxWidth: DS.Layout.gridItemMax)
    }
}

#Preview {
    let mockBook = Book(
        title: "The Great Gatsby", author: "F. Scott Fitzgerald", coverImageName: "", content: "")
    return BookCoverView(book: mockBook)
        .padding()
        .background(Color.black)
}
