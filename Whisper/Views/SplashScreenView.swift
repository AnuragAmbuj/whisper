//
//  SplashScreenView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 05/01/26.
//

import SwiftUI

struct SplashScreenView: View {
    @State private var isAnimating = false
    @State private var bookOffset: CGFloat = 0
    @State private var pageFlip: Double = 0
    @State private var glowOpacity: Double = 0.3
    
    var body: some View {
        ZStack {
            LiquidBackground()
            
            VStack(spacing: 40) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(glowOpacity))
                        .frame(width: 180, height: 180)
                        .blur(radius: 40)
                    
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [.white, Color(white: 0.95)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 70, height: 90)
                            .shadow(color: .black.opacity(0.3), radius: 10, x: 5, y: 5)
                        
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [Color(white: 0.98), .white],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 60, height: 80)
                            .offset(x: 2)
                            .rotation3DEffect(
                                .degrees(pageFlip),
                                axis: (x: 0, y: 1, z: 0),
                                anchor: .leading
                            )
                        
                        VStack(spacing: 4) {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 40, height: 3)
                            }
                        }
                        .offset(x: 5, y: -5)
                    }
                    .offset(y: bookOffset)
                }
                .frame(height: 200)
                
                VStack(spacing: 16) {
                    Text("Whisper")
                        .font(.system(size: 42, weight: .bold, design: .serif))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(.white)
                                .frame(width: 8, height: 8)
                                .scaleEffect(isAnimating ? 1.0 : 0.5)
                                .opacity(isAnimating ? 1.0 : 0.3)
                                .animation(
                                    .easeInOut(duration: 0.6)
                                    .repeatForever()
                                    .delay(Double(index) * 0.2),
                                    value: isAnimating
                                )
                        }
                    }
                }
            }
        }
        .onAppear {
            isAnimating = true
            
            WebKitWarmer.shared.prewarm()
            
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                bookOffset = -10
                glowOpacity = 0.6
            }
            
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pageFlip = -30
            }
        }
    }
}

#Preview {
    SplashScreenView()
}
