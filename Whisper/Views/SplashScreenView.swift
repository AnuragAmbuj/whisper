//
//  SplashScreenView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 05/01/26.
//

import SwiftUI

struct SplashScreenView: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            DS.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: DS.Spacing.xxl) {
                // Whisper Mark Emblem
                Image("WhisperLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                            .stroke(DS.Colors.border, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 10, y: 4)
                
                VStack(spacing: DS.Spacing.sm) {
                    Text("Whisper")
                        .font(.system(size: 32, weight: .bold, design: .serif))
                        .foregroundColor(.primary)
                    
                    Text("Read effortlessly")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                ProgressView()
                    .controlSize(.regular)
                    .tint(.primary)
                    .padding(.top, DS.Spacing.md)
            }
        }
        .onAppear {
            isAnimating = true
            WebKitWarmer.shared.prewarm()
        }
    }
}

#Preview {
    SplashScreenView()
}
