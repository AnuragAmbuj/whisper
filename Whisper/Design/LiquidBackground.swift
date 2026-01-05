//
//  LiquidBackground.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI

struct LiquidBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var start = UnitPoint(x: 0, y: -2)
    @State private var end = UnitPoint(x: 4, y: 0)
    
    private var colors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.1, green: 0.2, blue: 0.5),
                Color(red: 0.2, green: 0.1, blue: 0.6),
                Color(red: 0.0, green: 0.4, blue: 0.7),
                Color(red: 0.1, green: 0.3, blue: 0.6)
            ]
        } else {
            return [
                Color(red: 0.3, green: 0.5, blue: 0.9),
                Color(red: 0.5, green: 0.3, blue: 0.95),
                Color(red: 0.2, green: 0.6, blue: 0.85),
                Color(red: 0.3, green: 0.5, blue: 0.8)
            ]
        }
    }
    
    private var orb1Color: Color {
        colorScheme == .dark ? Color.cyan.opacity(0.3) : Color.purple.opacity(0.3)
    }
    
    private var orb2Color: Color {
        colorScheme == .dark ? Color.green.opacity(0.3) : Color.blue.opacity(0.3)
    }
    
    var body: some View {
        LinearGradient(
            colors: colors,
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
                    .fill(orb1Color)
                    .frame(width: 300, height: 300)
                    .blur(radius: 60)
                    .offset(x: -100, y: -200)
                    
                Circle()
                    .fill(orb2Color)
                    .frame(width: 350, height: 350)
                    .blur(radius: 60)
                    .offset(x: 150, y: 200)
            }
        }
    }
}
