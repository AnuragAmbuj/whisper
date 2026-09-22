//
//  SplashScreenView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 05/01/26.
//

import SwiftUI

struct SplashScreenView: View {
    @State private var hasAppeared = false
    @State private var showText = false
    
    var body: some View {
        ZStack {
            DS.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: DS.Spacing.xxl) {
                // Animated Vector Whisper Mark (Writes in on launch)
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                        .fill(DS.Colors.cardBackground)
                        .frame(width: 120, height: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                                .stroke(DS.Colors.border, lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.04), radius: 16, y: 8)
                    
                    WhisperMarkAnimatedView(
                        size: 92,
                        duration: 1.25,
                        autoStart: true
                    )
                }
                
                VStack(spacing: DS.Spacing.sm) {
                    Text("Whisper")
                        .font(.system(size: 34, weight: .bold, design: .serif))
                        .foregroundColor(.primary)
                    
                    Text("Read effortlessly")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .opacity(showText ? 1.0 : 0.0)
                .offset(y: showText ? 0 : 8)
                
                // Elegant Custom Whisper Loader
                WhisperMarkLoaderView(size: 28, style: .wave)
                    .opacity(showText ? 0.9 : 0.0)
                    .padding(.top, DS.Spacing.sm)
            }
        }
        .onAppear {
            hasAppeared = true
            withAnimation(.easeOut(duration: 0.6).delay(0.45)) {
                showText = true
            }
            WebKitWarmer.shared.prewarm()
        }
    }
}

#Preview {
    SplashScreenView()
}
