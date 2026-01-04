//
//  DesignSystem.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI

// MARK: - Design System
/// Centralized design tokens for consistent UI across the app

enum DS {
    
    // MARK: - Spacing
    /// Standardized spacing scale (4pt base)
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }
    
    // MARK: - Corner Radius
    /// Standardized corner radius values
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
    }
    
    // MARK: - Opacity
    /// Standardized opacity values for text hierarchy
    enum Opacity {
        static let primary: Double = 1.0
        static let secondary: Double = 0.85
        static let tertiary: Double = 0.7
        static let quaternary: Double = 0.5
        static let stroke: Double = 0.2
        static let subtleStroke: Double = 0.1
    }
    
    // MARK: - Shadows
    /// Standardized shadow configurations
    enum Shadow {
        struct Config {
            let color: Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
        }
        
        static let sm = Config(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        static let md = Config(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
        static let lg = Config(color: .black.opacity(0.25), radius: 14, x: 0, y: 10)
        static let glass = Config(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
    }
    
    // MARK: - Animation
    /// Standardized animation durations
    enum Animation {
        static let fast: Double = 0.2
        static let normal: Double = 0.3
        static let slow: Double = 0.5
        static let background: Double = 5.0
    }
    
    // MARK: - Typography
    /// Standardized text line spacing
    enum Typography {
        static let lineSpacing: CGFloat = 6
    }
    
    // MARK: - Layout
    /// Standardized max widths for containers
    enum Layout {
        static let maxContentWidth: CGFloat = 700
        static let maxSplitWidth: CGFloat = 1200
        static let maxCoverWidth: CGFloat = 420
        static let maxButtonWidth: CGFloat = 420
        static let gridItemMin: CGFloat = 140
        static let gridItemMax: CGFloat = 180
        static let gridSpacing: CGFloat = 20
    }
    
    // MARK: - Background Opacity
    /// Opacity for LiquidBackground in different contexts
    enum BackgroundOpacity {
        static let full: Double = 1.0
        static let overlay: Double = 0.3
    }
}

// MARK: - Shadow View Extension
extension View {
    func shadow(_ config: DS.Shadow.Config) -> some View {
        self.shadow(color: config.color, radius: config.radius, x: config.x, y: config.y)
    }
}

// MARK: - Primary Button Style
struct PrimaryButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            .shadow(DS.Shadow.sm)
    }
}

extension View {
    func primaryButtonStyle() -> some View {
        self.modifier(PrimaryButtonStyle())
    }
}

// MARK: - Icon Button Style
struct IconButtonStyle: ViewModifier {
    var padding: CGFloat = DS.Spacing.sm
    
    func body(content: Content) -> some View {
        content
            .foregroundColor(.white)
            .padding(padding)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
    }
}

extension View {
    func iconButtonStyle(padding: CGFloat = DS.Spacing.sm) -> some View {
        self.modifier(IconButtonStyle(padding: padding))
    }
}

// MARK: - Book Cover Style
struct BookCoverStyle: ViewModifier {
    var size: CoverSize = .small
    
    enum CoverSize {
        case small
        case large
    }
    
    func body(content: Content) -> some View {
        content
            .aspectRatio(2/3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: size == .small ? DS.Radius.md : DS.Radius.lg))
            .shadow(size == .small ? DS.Shadow.sm : DS.Shadow.lg)
            .overlay(
                RoundedRectangle(cornerRadius: size == .small ? DS.Radius.md : DS.Radius.lg)
                    .stroke(.white.opacity(DS.Opacity.stroke), lineWidth: 1)
            )
    }
}

extension View {
    func bookCoverStyle(size: BookCoverStyle.CoverSize = .small) -> some View {
        self.modifier(BookCoverStyle(size: size))
    }
}

// MARK: - Synopsis Container Style
struct SynopsisContainerStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(DS.Spacing.xxl)
            .background(.ultraThinMaterial)
            .cornerRadius(DS.Radius.lg)
    }
}

extension View {
    func synopsisContainerStyle() -> some View {
        self.modifier(SynopsisContainerStyle())
    }
}

// MARK: - Chip Style (for indicators)
struct ChipStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(DS.Spacing.xs)
            .background(.ultraThinMaterial)
            .cornerRadius(DS.Radius.sm)
    }
}

extension View {
    func chipStyle() -> some View {
        self.modifier(ChipStyle())
    }
}
