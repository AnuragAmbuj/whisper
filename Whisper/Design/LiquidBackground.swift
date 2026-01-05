//
//  LiquidBackground.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI

/// Animated liquid background that adapts to theme
struct LiquidBackground: View {
    @State private var start = UnitPoint(x: 0, y: -2)
    @State private var end = UnitPoint(x: 4, y: 0)
    
    // Theme-aware colors
    private var lightColors: [Color] {
        [
            Color(red: 0.2, green: 0.4, blue: 0.8),
            Color(red: 0.4, green: 0.6, blue: 1.0),
            Color(red: 0.1, green: 0.5, blue: 0.8),
            Color(red: 0.2, green: 0.4, blue: 0.7)
        ]
    }
    
    private var darkColors: [Color] {
        [
            Color(red: 0.1, green: 0.2, blue: 0.5),
            Color(red: 0.2, green: 0.1, blue: 0.6),
            Color(red: 0.0, green: 0.4, blue: 0.7),
            Color(red: 0.1, green: 0.3, blue: 0.6)
        ]
    }
    
    var body: some View {
        LinearGradient(
            colors: [
                Color.red: 0.2, green: 0.4, blue: 0.8),
                Color(red: 0.4, green: 0.6, blue: 1.0),
                Color(red: 0.1, green: 0.5, blue: 0.8),
                Color(red: 0.2, green: 0.4, blue: 0.7)
            ],
            startPoint: start,
            endPoint: end
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 5.0).repeatForever(autoreverses: true)) {
                self.start = UnitPoint(x: 1, y: 0)
                self.end = UnitPoint(x: 0, y: 2)
            }
        }
        .overlay {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: 300, height: 300)
                    .blur(radius: 60)
                    .offset(x: -100, y: -200)
                    
                Circle()
                    .fill(Color.green.opacity(0.3))
                    .frame(width: 350, height: 350)
                    .blur(radius: 60)
                    .offset(x: 150, y: 200)
            }
        }
    }
}