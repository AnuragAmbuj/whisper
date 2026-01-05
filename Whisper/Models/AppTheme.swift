//
//  AppTheme.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI

/// Reading theme configuration with light/dark mode support
struct AppTheme {
    var fontName: String = "Serif"
    var fontSize: Double = 18.0
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
            case .default:
                return "System"
            case .dark:
                return "Dark"
            case .sepia:
                return "Sepia"
            case .light:
                return "Light"
            }
        }
    }
    
    init(style: ThemeStyle = .default, isDarkMode: Bool = false) {
        self.style = style
        self.isDarkMode = isDarkMode
        
        // Determine colors based on style and system dark mode
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
    
    /// Initialize with current system appearance
    init(style: ThemeStyle = .default) {
        let isDarkMode = Self.getCurrentSystemDarkMode()
        self.init(style: style, isDarkMode: isDarkMode)
    }
    
    /// Update theme when system appearance changes
    mutating func updateForSystemAppearance() {
        let isDarkMode = Self.getCurrentSystemDarkMode()
        self.isDarkMode = isDarkMode
        
        // Re-calculate colors
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
    
    /// Get current system dark mode status
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
    
    // Legacy support for manual init
    init(backgroundColor: Color, textColor: Color) {
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.style = .default
        self.isDarkMode = Self.getCurrentSystemDarkMode()
    }
    
    // Predefined themes
    static let `default` = AppTheme(style: .default)
    static let dark = AppTheme(style: .dark)
    static let sepia = AppTheme(style: .sepia)
    static let light = AppTheme(style: .light)
}

// MARK: - Color Extensions for Theme Support

extension Color {
    /// Adaptive color that responds to theme changes
    static func adaptive(lightTheme: Color, darkTheme: Color) -> Color {
        #if os(iOS)
        return Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? darkTheme.uiColor() : lightTheme.uiColor()
        })
        #elseif os(macOS)
        return Color(NSColor { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkTheme.nsColor() : lightTheme.nsColor()
        })
        #else
        return lightTheme
        #endif
    }
    
    /// Glass material color that adapts to theme
    static var glassMaterial: Color {
        #if os(iOS)
        return Color(.systemBackground).opacity(0.8)
        #elseif os(macOS)
        return Color(.controlBackgroundColor).opacity(0.8)
        #else
        return .white.opacity(0.8)
        #endif
    }
    
    /// Text color that adapts to theme
    static var adaptiveText: Color {
        #if os(iOS)
        return Color(.label)
        #elseif os(macOS)
        return Color(.controlTextColor)
        #else
        return .black
        #endif
    }
    
    /// Secondary text color that adapts to theme
    static var adaptiveSecondaryText: Color {
        #if os(iOS)
        return Color(.secondaryLabel)
        #elseif os(macOS)
        return Color(.secondaryLabelColor)
        #else
        return .gray
        #endif
    }
    
    /// Background color that adapts to theme
    static var adaptiveBackground: Color {
        #if os(iOS)
        return Color(.systemBackground)
        #elseif os(macOS)
        return Color(.controlBackgroundColor)
        #else
        return .white
        #endif
    }
    
    /// Adaptive background for components (light/dark aware)
    static func adaptiveComponentBackground(isDark: Bool) -> Color {
        isDark ? Color(red: 0.1, green: 0.1, blue: 0.1) : .white
    }
    
    // MARK: - Platform Extensions

#if os(iOS)
extension Color {
    var uiColor: UIColor {
        return UIColor(self)
    }
}
#elseif os(macOS)
extension Color {
    var nsColor: NSColor {
        return NSColor(self)
    }
}
#endif