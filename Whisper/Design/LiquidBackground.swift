//
//  LiquidBackground.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI

struct LiquidBackground: View {
    @State private var start = UnitPoint(x: 0, y: -2)
    @State private var end = UnitPoint(x: 4, y: 0)
    
    let colors: [Color] = [
        Color(red: 0.1, green: 0.2, blue: 0.5),
        Color(red: 0.3, green: 0.1, blue: 0.6),
        Color(red: 0.0, green: 0.5, blue: 0.7),
        Color(red: 0.1, green: 0.2, blue: 0.5)
    ]
    
    var body: some View {
        LinearGradient(colors: colors, startPoint: start, endPoint: end)
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 5.0).repeatForever(autoreverses: true)) {
                    self.start = UnitPoint(x: 1, y: 0)
                    self.end = UnitPoint(x: 0, y: 2)
                }
            }
            .overlay(
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.3))
                        .frame(width: 300, height: 300)
                        .blur(radius: 60)
                        .offset(x: -100, y: -200)
                    
                    Circle()
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: 350, height: 350)
                        .blur(radius: 60)
                        .offset(x: 150, y: 200)
                }
            )
    }
}
