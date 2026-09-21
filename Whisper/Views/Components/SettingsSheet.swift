//
//  SettingsSheet.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI

struct SettingsSheet: View {
    @Bindable var viewModel: ReaderViewModel
    
    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reading Comfort")
                        .font(.headline.bold())
                        .foregroundColor(.primary)
                    Text(viewModel.theme.style.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            // Theme Selector
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack {
                    Text("EYE COMFORT THEMES")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(viewModel.theme.style.displayName)
                        .font(.caption2.bold())
                        .foregroundColor(.primary)
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.sm) {
                        ForEach(AppTheme.ThemeStyle.allCases, id: \.self) { style in
                            themeButton(style: style)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Divider()
            
            // Typography Font Family
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("TYPOGRAPHY")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                
                HStack(spacing: DS.Spacing.xs) {
                    fontFamilyButton(title: "Serif", fontName: "Serif")
                    fontFamilyButton(title: "Sans", fontName: "Sans")
                    fontFamilyButton(title: "Mono", fontName: "Mono")
                    fontFamilyButton(title: "Rounded", fontName: "Rounded")
                }
            }
            
            Divider()
            
            // Font Size
            HStack {
                Text("Font Size")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { viewModel.decreaseFontSize() }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(viewModel.fontSize <= 12)
                
                Text("\(Int(viewModel.fontSize)) pt")
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                    .frame(width: 50)
                
                Button(action: { viewModel.increaseFontSize() }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(viewModel.fontSize >= 32)
            }
            .foregroundColor(.primary)
            
            Divider()
            
            // Line Spacing
            HStack {
                Text("Line Spacing")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { viewModel.decreaseLineHeight() }) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(viewModel.lineHeight <= 1.2)
                
                Text(String(format: "%.1fx", viewModel.lineHeight))
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                    .frame(width: 50)
                
                Button(action: { viewModel.increaseLineHeight() }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(viewModel.lineHeight >= 2.6)
            }
            .foregroundColor(.primary)
        }
        .padding(DS.Spacing.xxl)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .shadow(DS.Shadow.lg)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func themeButton(style: AppTheme.ThemeStyle) -> some View {
        let isSelected = viewModel.theme.style == style
        Button(action: {
            withAnimation(.easeInOut(duration: DS.Animation.fast)) {
                viewModel.setTheme(style)
            }
        }) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(style.swatchColor)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .stroke(
                                    isSelected ? Color.primary : DS.Colors.border,
                                    lineWidth: isSelected ? 2.5 : 1
                                )
                        )
                    
                    Image(systemName: style.iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(
                            style == .light || style == .sepia || style == .greyscale || style == .sage
                                ? Color(white: 0.25)
                                : Color(white: 0.90)
                        )
                }
                
                Text(style.displayName)
                    .font(.caption2.weight(isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .frame(width: 62)
            .padding(.vertical, 6)
            .background(isSelected ? DS.Colors.unselectedFill : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func fontFamilyButton(title: String, fontName: String) -> some View {
        let isSelected = viewModel.fontName.lowercased() == fontName.lowercased()
        Button(action: {
            withAnimation(.easeInOut(duration: DS.Animation.fast)) {
                viewModel.setFontName(fontName)
            }
        }) {
            Text(title)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? DS.Colors.onSelection : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? Color.primary : DS.Colors.unselectedFill)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let mockBook = Book(title: "Test", author: "Test", coverImageName: "", content: "")
    let vm = ReaderViewModel(book: mockBook)
    
    return ZStack {
        Color.gray
        SettingsSheet(viewModel: vm)
    }
}
