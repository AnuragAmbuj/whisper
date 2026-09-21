//
//  StoreView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 18/09/26.
//

import SwiftUI
import SwiftData

struct StoreView: View {
    @State private var storeService = StoreService.shared
    @State private var selectedCategory = "All"
    @State private var hoveredCategory: String? = nil
    @State private var searchText = ""
    @State private var selectedBookForDetails: StoreBook? = nil
    @State private var showPurchasedAlert = false
    @State private var purchasedBookTitle = ""
    
    @Environment(\.modelContext) private var modelContext
    @Query private var existingBooks: [Book]
    
    private var filteredCatalog: [StoreBook] {
        var list = storeService.catalog
        if selectedCategory != "All" {
            list = list.filter { $0.category == selectedCategory }
        }
        if !searchText.isEmpty {
            list = TypeSafeService.shared.rerankStoreBooks(books: list, query: searchText)
        }
        return list
    }

    private var recommendedBooks: [StoreBook] {
        TypeSafeService.shared.recommendStoreBooks(library: existingBooks, catalog: storeService.catalog, limit: 4)
    }
    
    var body: some View {
        #if os(iOS)
        NavigationStack {
            storeScrollContent
                .navigationTitle("Bookstore")
                .background(systemBackground.ignoresSafeArea())
        }
        #else
        storeScrollContent
            .background(systemBackground)
        #endif
    }
    
    private var storeScrollContent: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.xl) {
                subscriptionBanner
                    .padding(.horizontal)
                    #if os(macOS)
                    .padding(.top, DS.Spacing.lg)
                    #else
                    .padding(.top, DS.Spacing.xs)
                    #endif
                
                categoryChipsView

                if searchText.isEmpty && selectedCategory == "All" && !recommendedBooks.isEmpty {
                    pickedForYouSection
                }
                
                featuredBooksGrid
                    .padding(.horizontal)
                    .padding(.bottom, DS.Spacing.xxl)
            }
            .frame(maxWidth: DS.Layout.maxSplitWidth)
            .frame(maxWidth: .infinity)
        }
        .searchable(text: $searchText, prompt: "Search titles, authors, genres, concepts")
        .sheet(item: $selectedBookForDetails) { book in
            StoreBookDetailSheet(storeBook: book) {
                handlePurchase(book)
            }
        }
        .alert("Added to Library", isPresented: $showPurchasedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\"\(purchasedBookTitle)\" is ready to read in your Library.")
        }
    }
    
    private var systemBackground: Color {
        DS.Colors.background
    }
    
    private var subscriptionBanner: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Label("Whisper+", systemImage: "sparkles")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(storeService.isWhisperPlusSubscribed ? "Active Member" : "Special Offer")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DS.Colors.unselectedFill)
                    .clipShape(Capsule())
                    .foregroundColor(.primary)
            }
            
            Text(storeService.isWhisperPlusSubscribed ? "Unlimited access to all Whisper+ books & audiobooks is unlocked." : "Read 50,000+ books, comics, and magazines without limits.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: DS.Animation.fast)) {
                        storeService.isWhisperPlusSubscribed.toggle()
                    }
                }) {
                    Text(storeService.isWhisperPlusSubscribed ? "Manage Plan" : "Try 1 Month Free")
                        .font(.subheadline.bold())
                        .foregroundColor(DS.Colors.onSelection)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(DS.Spacing.lg)
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Colors.border, lineWidth: 1)
        )
    }

    private var pickedForYouSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Label("Picked For You", systemImage: "sparkles")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text("TypeSafe Taste Match")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.md) {
                    ForEach(recommendedBooks) { book in
                        Button(action: { selectedBookForDetails = book }) {
                            VStack(alignment: .leading, spacing: 4) {
                                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                    .fill(DS.Colors.cardBackground)
                                    .frame(width: 100, height: 140)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                            .stroke(DS.Colors.border, lineWidth: 1)
                                    )
                                    .overlay {
                                        Image(systemName: "book.pages")
                                            .foregroundColor(.secondary)
                                    }
                                Text(book.title)
                                    .font(.caption.bold())
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Text(book.author)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 100)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var categoryChipsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(storeService.categories, id: \.self) { cat in
                    let isSelected = selectedCategory == cat
                    let isHovered = hoveredCategory == cat && !isSelected
                    Button(action: {
                        withAnimation(.easeInOut(duration: DS.Animation.fast)) {
                            selectedCategory = cat
                        }
                    }) {
                        Text(cat)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundColor(
                                isSelected
                                    ? DS.Colors.onSelection
                                    : (isHovered ? Color.primary : Color.secondary)
                            )
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.xs)
                            .background(
                                Capsule()
                                    .fill(
                                        isSelected
                                            ? DS.Colors.selection
                                            : (isHovered ? DS.Colors.hover : DS.Colors.unselectedFill)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.12)) {
                            hoveredCategory = hovering ? cat : nil
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var featuredBooksGrid: some View {
        let columns = [
            GridItem(.adaptive(minimum: DS.Layout.gridItemMin, maximum: DS.Layout.gridItemMax), spacing: DS.Layout.gridSpacing)
        ]
        
        return LazyVGrid(columns: columns, spacing: DS.Spacing.xxl) {
            ForEach(filteredCatalog) { book in
                StoreBookItemView(
                    book: book,
                    isWhisperPlusActive: storeService.isWhisperPlusSubscribed,
                    isAlreadyOwned: existingBooks.contains { $0.title.lowercased() == book.title.lowercased() },
                    onSelect: {
                        selectedBookForDetails = book
                    },
                    onBuyOrAdd: {
                        handlePurchase(book)
                    }
                )
            }
        }
    }
    
    private func handlePurchase(_ book: StoreBook) {
        let purchased = storeService.purchaseOrDownload(book, context: modelContext)
        BookService.shared.indexBookInSpotlight(purchased)
        purchasedBookTitle = book.title
        showPurchasedAlert = true
    }
}

// MARK: - Store Book Item View
private struct StoreBookItemView: View {
    let book: StoreBook
    let isWhisperPlusActive: Bool
    let isAlreadyOwned: Bool
    let onSelect: () -> Void
    let onBuyOrAdd: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // Flat Cover
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(DS.Colors.cardBackground)
                    .aspectRatio(0.68, contentMode: .fit)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .stroke(DS.Colors.border, lineWidth: 1)
                    )
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "book.closed")
                                .font(.system(size: 28))
                                .foregroundColor(.secondary)
                            Text(book.title)
                                .font(.caption.bold())
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .padding(.horizontal, 8)
                        }
                    }
                    .onTapGesture {
                        onSelect()
                    }
                
                // Format badge
                Text(book.format.rawValue.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(DS.Colors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(DS.Colors.border, lineWidth: 0.5)
                    )
                    .padding(6)
            }
            
            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(book.author)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                    Text(String(format: "%.1f", book.rating))
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.primary)
                }
                .padding(.top, 1)
                
                // Price / Add Button (Apple High Contrast Style)
                Button(action: onBuyOrAdd) {
                    HStack(spacing: 4) {
                        if isAlreadyOwned {
                            Image(systemName: "checkmark.circle.fill")
                            Text("In Library")
                        } else if isWhisperPlusActive && book.isWhisperPlusIncluded {
                            Image(systemName: "sparkles")
                            Text("Read")
                        } else {
                            Text(book.price)
                        }
                    }
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(isAlreadyOwned ? DS.Colors.unselectedFill : Color.primary)
                    .foregroundColor(isAlreadyOwned ? .secondary : DS.Colors.onSelection)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isAlreadyOwned)
                .padding(.top, 4)
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: DS.Layout.gridItemMax)
    }
}

// MARK: - Store Book Detail Sheet
private struct StoreBookDetailSheet: View {
    let storeBook: StoreBook
    let onPurchase: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.xl) {
                    // Flat Cover
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Colors.cardBackground)
                        .frame(width: 160, height: 240)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .stroke(DS.Colors.border, lineWidth: 1)
                        )
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "book.pages.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.primary)
                                Text(storeBook.title)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        }
                    
                    VStack(spacing: 4) {
                        Text(storeBook.title)
                            .font(.title2.bold())
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                        
                        Text(storeBook.author)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: DS.Spacing.xxl) {
                        VStack(spacing: 2) {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                Text(String(format: "%.1f", storeBook.rating))
                                    .bold()
                            }
                            Text("\(storeBook.reviewCount) reviews")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider().frame(height: 28)
                        
                        VStack(spacing: 2) {
                            Text("\(storeBook.pageCount)")
                                .bold()
                            Text("Pages")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider().frame(height: 28)
                        
                        VStack(spacing: 2) {
                            Text(storeBook.format.rawValue.uppercased())
                                .bold()
                            Text("Format")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(DS.Colors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .stroke(DS.Colors.border, lineWidth: 1)
                    )
                    
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Text("About This Book")
                            .font(.headline)
                        Text(storeBook.summary)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .lineSpacing(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    
                    Button(action: {
                        onPurchase()
                        dismiss()
                    }) {
                        Text("Buy for \(storeBook.price)")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(DS.Colors.onSelection)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.primary)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.bottom, DS.Spacing.xl)
                }
                .padding(.top, DS.Spacing.lg)
            }
            .navigationTitle("Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    StoreView()
}
