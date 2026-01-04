//
//  GlassModifier.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI

struct GlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .cornerRadius(cornerRadius)
            .shadow(DS.Shadow.glass)
            .overlay(
                 RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(.white.opacity(DS.Opacity.subtleStroke), lineWidth: 0.5)
            )
    }
}

extension View {
    func glass(cornerRadius: CGFloat = DS.Radius.xl) -> some View {
        self.modifier(GlassModifier(cornerRadius: cornerRadius))
    }
}
