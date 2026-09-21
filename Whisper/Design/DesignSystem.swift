//
//  DesignSystem.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI

// MARK: - Design System
/// Centralized design tokens for consistent, minimal, and flat UI across the app

enum DS {
    
    // MARK: - Colors (Minimal, High-Contrast, Apple First-Party Style)
    enum Colors {
        /// Unified app primary accent color: High-contrast primary matching Apple Books
        static let accent = Color.primary
        
        /// Subtle secondary tint for muted labels and icons
        static let secondary = Color.secondary
        
        /// Minimal, flat 1px hairline border
        static let border = Color.primary.opacity(0.08)
        
        /// Subtle divider
        static let divider = Color.primary.opacity(0.06)
        
        /// High-contrast active selection background (Apple Books style: solid black in light mode, solid white in dark mode)
        static let selection = Color.primary
        
        /// Foreground text / icons on top of active selection
        static var onSelection: Color {
            #if os(iOS)
            return Color(uiColor: .systemBackground)
            #elseif os(macOS)
            return Color(nsColor: .windowBackgroundColor)
            #else
            return Color.black
            #endif
        }
        
        /// Subtle neutral hover background for buttons and navigation items
        static let hover = Color.primary.opacity(0.08)
        
        /// Neutral unselected chip / pill background
        static let unselectedFill = Color.primary.opacity(0.06)
        
        /// Consistent system surface / card background
        static var cardBackground: Color {
            #if os(iOS)
            return Color(uiColor: .secondarySystemGroupedBackground)
            #elseif os(macOS)
            return Color(nsColor: .controlBackgroundColor)
            #else
            return Color.gray.opacity(0.12)
            #endif
        }
        
        /// Consistent page / canvas background
        static var background: Color {
            #if os(iOS)
            return Color(uiColor: .systemBackground)
            #elseif os(macOS)
            return Color(nsColor: .windowBackgroundColor)
            #else
            return Color.black
            #endif
        }
        
        /// Consistent grouped canvas background
        static var groupedBackground: Color {
            #if os(iOS)
            return Color(uiColor: .systemGroupedBackground)
            #elseif os(macOS)
            return Color(nsColor: .windowBackgroundColor)
            #else
            return Color.black
            #endif
        }
    }
    
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
    
    // MARK: - Shadows (Subtle, Flat, Non-Glowing)
    enum Shadow {
        struct Config {
            let color: Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
        }
        
        static let sm = Config(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
        static let md = Config(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        static let lg = Config(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
        static let glass = Config(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
        static let none = Config(color: .clear, radius: 0, x: 0, y: 0)
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
}

// MARK: - Shadow View Extension
extension View {
    func shadow(_ config: DS.Shadow.Config) -> some View {
        self.shadow(color: config.color, radius: config.radius, x: config.x, y: config.y)
    }
}

// MARK: - Primary Button Style (Minimal, Flat, Clean, High Contrast)
struct PrimaryButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.headline.weight(.semibold))
            .foregroundColor(DS.Colors.onSelection)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
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
            .foregroundColor(.primary)
            .padding(padding)
            #if os(iOS)
            .background(Color(uiColor: .secondarySystemFill))
            #elseif os(macOS)
            .background(Color.secondary.opacity(0.15))
            #else
            .background(.regularMaterial)
            #endif
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
            .clipShape(RoundedRectangle(cornerRadius: size == .small ? DS.Radius.md : DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size == .small ? DS.Radius.md : DS.Radius.lg, style: .continuous)
                    .stroke(DS.Colors.border, lineWidth: 1)
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
            .padding(DS.Spacing.lg)
            .background(DS.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(DS.Colors.border, lineWidth: 1)
            )
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
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .stroke(DS.Colors.border, lineWidth: 0.5)
            )
    }
}

extension View {
    func chipStyle() -> some View {
        self.modifier(ChipStyle())
    }
}
