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
        case sepia
        case greyscale
        case sage
        case dusk
        case dark
        case light
        
        var displayName: String {
            switch self {
            case .default: return "System"
            case .sepia: return "Sepia"
            case .greyscale: return "Greyscale"
            case .sage: return "Sage"
            case .dusk: return "Dusk"
            case .dark: return "Dark"
            case .light: return "Light"
            }
        }
        
        var description: String {
            switch self {
            case .default: return "Matches system appearance"
            case .sepia: return "Warm parchment, reduced blue light"
            case .greyscale: return "Matte paper, low contrast glare-free"
            case .sage: return "Soothing pale mint, relaxes eyes"
            case .dusk: return "Slate twilight, gentle on night eyes"
            case .dark: return "Deep night, soft off-white text"
            case .light: return "Crisp bright daylight"
            }
        }
        
        var iconName: String {
            switch self {
            case .default: return "circle.lefthalf.filled"
            case .sepia: return "sun.dust.fill"
            case .greyscale: return "newspaper.fill"
            case .sage: return "leaf.fill"
            case .dusk: return "sunset.fill"
            case .dark: return "moon.fill"
            case .light: return "sun.max.fill"
            }
        }
        
        var swatchColor: Color {
            switch self {
            case .default: return Color(white: 0.25)
            case .sepia: return Color(red: 0.96, green: 0.93, blue: 0.86)
            case .greyscale: return Color(red: 0.92, green: 0.92, blue: 0.93)
            case .sage: return Color(red: 0.91, green: 0.94, blue: 0.91)
            case .dusk: return Color(red: 0.15, green: 0.18, blue: 0.22)
            case .dark: return Color(red: 0.08, green: 0.08, blue: 0.09)
            case .light: return .white
            }
        }
    }
    
    init(style: ThemeStyle = .default, isDarkMode: Bool = false) {
        self.style = style
        self.isDarkMode = isDarkMode
        let colors = Self.resolvedColors(for: style, isDarkMode: isDarkMode)
        self.backgroundColor = colors.background
        self.textColor = colors.text
    }
    
    init(style: ThemeStyle = .default) {
        let isDarkMode = Self.getCurrentSystemDarkMode()
        self.init(style: style, isDarkMode: isDarkMode)
    }
    
    mutating func updateForSystemAppearance() {
        let isDarkMode = Self.getCurrentSystemDarkMode()
        self.isDarkMode = isDarkMode
        let colors = Self.resolvedColors(for: style, isDarkMode: isDarkMode)
        self.backgroundColor = colors.background
        self.textColor = colors.text
    }
    
    private static func resolvedColors(for style: ThemeStyle, isDarkMode: Bool) -> (background: Color, text: Color) {
        switch style {
        case .default:
            if isDarkMode {
                return (
                    background: Color(red: 0.10, green: 0.10, blue: 0.11),
                    text: Color(red: 0.92, green: 0.92, blue: 0.94)
                )
            } else {
                return (
                    background: .white,
                    text: Color(red: 0.12, green: 0.12, blue: 0.14)
                )
            }
            
        case .sepia:
            // Authentic parchment / amber tint that filters out blue light
            if isDarkMode {
                return (
                    background: Color(red: 0.18, green: 0.15, blue: 0.12),
                    text: Color(red: 0.90, green: 0.85, blue: 0.78)
                )
            } else {
                return (
                    background: Color(red: 0.96, green: 0.93, blue: 0.86),
                    text: Color(red: 0.30, green: 0.22, blue: 0.16)
                )
            }
            
        case .greyscale:
            // Light Greyscale / E-ink paper tone, glare-free and low-contrast
            if isDarkMode {
                return (
                    background: Color(red: 0.16, green: 0.16, blue: 0.17),
                    text: Color(red: 0.82, green: 0.82, blue: 0.84)
                )
            } else {
                return (
                    background: Color(red: 0.92, green: 0.92, blue: 0.93),
                    text: Color(red: 0.20, green: 0.21, blue: 0.24)
                )
            }
            
        case .sage:
            // Soft mint / pale sage - reduces optical fatigue and photophobia
            if isDarkMode {
                return (
                    background: Color(red: 0.12, green: 0.18, blue: 0.14),
                    text: Color(red: 0.84, green: 0.91, blue: 0.86)
                )
            } else {
                return (
                    background: Color(red: 0.91, green: 0.94, blue: 0.91),
                    text: Color(red: 0.16, green: 0.25, blue: 0.18)
                )
            }
            
        case .dusk:
            // Twilight navy - rests eyes in low light without pitch-black contrast
            if isDarkMode {
                return (
                    background: Color(red: 0.13, green: 0.16, blue: 0.21),
                    text: Color(red: 0.82, green: 0.86, blue: 0.91)
                )
            } else {
                return (
                    background: Color(red: 0.93, green: 0.94, blue: 0.96),
                    text: Color(red: 0.18, green: 0.22, blue: 0.28)
                )
            }
            
        case .dark:
            // Pure dark with softened off-white text to avoid astigmatism halation
            return (
                background: Color(red: 0.08, green: 0.08, blue: 0.09),
                text: Color(red: 0.86, green: 0.86, blue: 0.88)
            )
            
        case .light:
            // Clean crisp light
            return (
                background: .white,
                text: Color(red: 0.12, green: 0.12, blue: 0.14)
            )
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
    static let greyscale = AppTheme(style: .greyscale)
    static let sage = AppTheme(style: .sage)
    static let dusk = AppTheme(style: .dusk)
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
