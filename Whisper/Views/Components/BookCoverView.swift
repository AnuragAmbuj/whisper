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
    ZStack(alignment: .bottom) {
      // Book Cover Art
      #if os(iOS)
      if let uiImage = loadImage(from: book.coverImageName) {
        Image(uiImage: uiImage)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: nil)  // let layout determine width
          .bookCoverStyle(size: .small)
      } else if !book.coverImageName.isEmpty, UIImage(named: book.coverImageName) != nil {
        // Asset Image
        Image(book.coverImageName)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: nil)
          .bookCoverStyle(size: .small)
      } else {
        // Gradient Fallback
        Rectangle()
          .fill(
            LinearGradient(
              colors: [.cyan.opacity(0.8), .blue.opacity(0.8)], startPoint: .topLeading,
              endPoint: .bottomTrailing)
          )
          .bookCoverStyle(size: .small)
      }
      #elseif os(macOS)
      if let nsImage = loadImageMac(from: book.coverImageName) {
        Image(nsImage: nsImage)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: nil)
          .bookCoverStyle(size: .small)
      } else if !book.coverImageName.isEmpty, NSImage(named: book.coverImageName) != nil {
        Image(book.coverImageName)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: nil)
          .bookCoverStyle(size: .small)
      } else {
        // Gradient Fallback
        Rectangle()
          .fill(
            LinearGradient(
              colors: [.cyan.opacity(0.8), .blue.opacity(0.8)], startPoint: .topLeading,
              endPoint: .bottomTrailing)
          )
          .bookCoverStyle(size: .small)
      }
      #endif

      // Glass Info overlay
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
  }

  private func loadImage(from name: String) -> UIImage? {
    guard !name.isEmpty else { return nil }
    // Check Documents Directory
    let nsDocumentDirectory = FileManager.SearchPathDirectory.documentDirectory
    let nsUserDomainMask = FileManager.SearchPathDomainMask.userDomainMask
    let paths = NSSearchPathForDirectoriesInDomains(nsDocumentDirectory, nsUserDomainMask, true)
    if let dirPath = paths.first {
      let imageURL = URL(fileURLWithPath: dirPath).appendingPathComponent(name)
      if let data = try? Data(contentsOf: imageURL) {
        return UIImage(data: data)
      }
    }
    return nil
  }
  
  #if os(macOS)
  private func loadImageMac(from name: String) -> NSImage? {
    guard !name.isEmpty else { return nil }
    // Check Documents Directory
    let nsDocumentDirectory = FileManager.SearchPathDirectory.documentDirectory
    let nsUserDomainMask = FileManager.SearchPathDomainMask.userDomainMask
    let paths = NSSearchPathForDirectoriesInDomains(nsDocumentDirectory, nsUserDomainMask, true)
    if let dirPath = paths.first {
      let imageURL = URL(fileURLWithPath: dirPath).appendingPathComponent(name)
      if let data = try? Data(contentsOf: imageURL) {
        return NSImage(data: data)
      }
    }
    return nil
  }
  #endif
}

#Preview {
  let mockBook = Book(
    title: "The Great Gatsby", author: "F. Scott Fitzgerald", coverImageName: "", content: "")
  return BookCoverView(book: mockBook)
    .padding()
    .background(Color.black)
}
