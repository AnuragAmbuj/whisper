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
    var lineHeight: CGFloat = 1.8
    var backgroundColor: Color
    var textColor: Color
    var style: ThemeStyle
    var isDarkMode: Bool
    
    enum ThemeStyle: String, Codable, CaseIterable {
        case `default`
        case dark
        case sepia
        case light
        
        var displayName: String {
            switch self {
            case .default: return "System"
            case .dark: return "Dark"
            case .sepia: return "Sepia"
            case .light: return "Light"
            }
        }
    }
    
    init(style: ThemeStyle = .default, isDarkMode: Bool = false) {
        self.style = style
        self.isDarkMode = isDarkMode
        
        switch style {
        case .default:
            if isDarkMode {
                self.backgroundColor = Color(red: 0.1, green: 0.1, blue: 0.1)
                self.textColor = .white
            } else {
                self.backgroundColor = .white
                self.textColor = .black
            }
        case .dark:
            self.backgroundColor = Color(red: 0.1, green: 0.1, blue: 0.1)
            self.textColor = .white
        case .sepia:
            if isDarkMode {
                self.backgroundColor = Color(red: 0.25, green: 0.20, blue: 0.15)
                self.textColor = Color(red: 0.9, green: 0.85, blue: 0.8)
            } else {
                self.backgroundColor = Color(red: 0.96, green: 0.93, blue: 0.88)
                self.textColor = Color(red: 0.36, green: 0.25, blue: 0.20)
            }
        case .light:
            self.backgroundColor = .white
            self.textColor = .black
        }
    }
    
    init(style: ThemeStyle = .default) {
        let isDarkMode = Self.getCurrentSystemDarkMode()
        self.init(style: style, isDarkMode: isDarkMode)
    }
    
    mutating func updateForSystemAppearance() {
        let isDarkMode = Self.getCurrentSystemDarkMode()
        self.isDarkMode = isDarkMode
        
        switch style {
        case .default:
            if isDarkMode {
                self.backgroundColor = Color(red: 0.1, green: 0.1, blue: 0.1)
                self.textColor = .white
            } else {
                self.backgroundColor = .white
                self.textColor = .black
            }
        case .dark:
            self.backgroundColor = Color(red: 0.1, green: 0.1, blue: 0.1)
            self.textColor = .white
        case .sepia:
            if isDarkMode {
                self.backgroundColor = Color(red: 0.25, green: 0.20, blue: 0.15)
                self.textColor = Color(red: 0.9, green: 0.85, blue: 0.8)
            } else {
                self.backgroundColor = Color(red: 0.96, green: 0.93, blue: 0.88)
                self.textColor = Color(red: 0.36, green: 0.25, blue: 0.20)
            }
        case .light:
            self.backgroundColor = .white
            self.textColor = .black
        }
    }
    
    private static func getCurrentSystemDarkMode() -> Bool {
        #if os(iOS)
        return UITraitCollection.current.userInterfaceStyle == .dark
        #elseif os(macOS)
        if #available(macOS 10.14, *) {
            let appearance = NSApp.effectiveAppearance
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return true
            }
        }
        return false
        #else
        return false
        #endif
    }
    
    init(backgroundColor: Color, textColor: Color) {
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.style = .default
        self.isDarkMode = Self.getCurrentSystemDarkMode()
    }
    
    static let `default` = AppTheme(style: .default)
    static let dark = AppTheme(style: .dark)
    static let sepia = AppTheme(style: .sepia)
    static let light = AppTheme(style: .light)
}

// MARK: - Color Extensions

extension Color {
    static var adaptiveText: Color {
        #if os(iOS)
        return Color(.label)
        #elseif os(macOS)
        return Color(.controlTextColor)
        #else
        return .black
        #endif
    }
    
    static var adaptiveSecondaryText: Color {
        #if os(iOS)
        return Color(.secondaryLabel)
        #elseif os(macOS)
        return Color(.secondaryLabelColor)
        #else
        return .gray
        #endif
    }
    
    static var adaptiveBackground: Color {
        #if os(iOS)
        return Color(.systemBackground)
        #elseif os(macOS)
        return Color(.controlBackgroundColor)
        #else
        return .white
        #endif
    }
    
    static func adaptiveComponentBackground(_ isDark: Bool) -> Color {
        isDark ? Color(red: 0.1, green: 0.1, blue: 0.1) : .white
    }
}
