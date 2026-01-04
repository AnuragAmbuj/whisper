//
//  AppTheme.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI

struct AppTheme {
    var fontName: String = "Serif"
    var fontSize: Double = 18.0
    var backgroundColor: Color = .white
    var textColor: Color = .black
    var style: ThemeStyle = .default
    
    enum ThemeStyle: String, Codable, CaseIterable {
        case `default`
        case dark
        case sepia
    }
    
    init(style: ThemeStyle = .default) {
        self.style = style
        switch style {
        case .default:
            self.backgroundColor = .white
            self.textColor = .black
        case .dark:
            self.backgroundColor = Color(red: 0.1, green: 0.1, blue: 0.1)
            self.textColor = .white
        case .sepia:
             self.backgroundColor = Color(red: 0.96, green: 0.93, blue: 0.88)
             self.textColor = Color(red: 0.36, green: 0.25, blue: 0.20)
        }
    }
    
    // Legacy support for manual init if needed, or just extensions
    init(backgroundColor: Color, textColor: Color) {
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.style = .default // Fallback
    }

    static let `default` = AppTheme(style: .default)
    static let dark = AppTheme(style: .dark)
    static let sepia = AppTheme(style: .sepia)
}
