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
        VStack(spacing: DS.Spacing.xl) {
            Text("Appearance")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Font Size
            HStack {
                Text("Size")
                    .foregroundColor(.white.opacity(DS.Opacity.secondary))
                Spacer()
                Button(action: { viewModel.fontSize -= 2 }) {
                    Image(systemName: "minus.circle")
                }
                Text("\(Int(viewModel.fontSize))")
                    .foregroundColor(.white)
                    .frame(width: 30)
                Button(action: { viewModel.fontSize += 2 }) {
                    Image(systemName: "plus.circle")
                }
            }
            .font(.system(size: DS.Spacing.xl))
            .foregroundColor(.white)
            
            Divider().background(.white.opacity(DS.Opacity.stroke))
            
            // Line Height (Simulated via padding/spacing logic in VM, or updated here)
            HStack {
                Text("Spacing")
                    .foregroundColor(.white.opacity(DS.Opacity.secondary))
                Spacer()
                Button(action: { viewModel.lineHeight = max(0, viewModel.lineHeight - 2) }) {
                    Image(systemName: "decrease.indent")
                }
                Button(action: { viewModel.lineHeight += 2 }) {
                    Image(systemName: "increase.indent")
                }
            }
            .font(.system(size: DS.Spacing.xl))
            .foregroundColor(.white)
            
            Divider().background(.white.opacity(DS.Opacity.stroke))

            // Global Theme toggle re-used here for access
            Button(action: { viewModel.toggleTheme() }) {
                HStack {
                    Text("Theme")
                        .foregroundColor(.white.opacity(DS.Opacity.secondary))
                    Spacer()
                    Circle()
                        .fill(viewModel.theme.backgroundColor)
                        .frame(width: DS.Spacing.xxl, height: DS.Spacing.xxl)
                        .overlay(Circle().stroke(.white, lineWidth: 1))
                }
            }
            
        }
        .padding(DS.Spacing.xxl)
        .glass(cornerRadius: DS.Radius.xl)
        .padding()
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
