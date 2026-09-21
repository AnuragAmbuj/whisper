//
//  LiquidBackground.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI

struct LiquidBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        DS.Colors.background
            .ignoresSafeArea()
    }
}
