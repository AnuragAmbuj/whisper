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
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DS.Colors.border, lineWidth: 1)
            )
    }
}

extension View {
    func glass(cornerRadius: CGFloat = DS.Radius.xl) -> some View {
        self.modifier(GlassModifier(cornerRadius: cornerRadius))
    }
}
