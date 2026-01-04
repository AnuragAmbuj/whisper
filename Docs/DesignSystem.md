# Design System

Whisper uses a centralized design system (`DS`) to ensure UI consistency across all views.

## Design Tokens

All design values are defined in `Whisper/Design/DesignSystem.swift`.

### Spacing Scale

Based on a 4pt grid system:

| Token | Value | Usage |
|-------|-------|-------|
| `DS.Spacing.xxs` | 4pt | Minimal gaps |
| `DS.Spacing.xs` | 6pt | Small gaps |
| `DS.Spacing.sm` | 8pt | Button padding, small margins |
| `DS.Spacing.md` | 12pt | Medium spacing |
| `DS.Spacing.lg` | 16pt | Standard padding |
| `DS.Spacing.xl` | 20pt | Section spacing |
| `DS.Spacing.xxl` | 24pt | Large padding |
| `DS.Spacing.xxxl` | 32pt | Container padding |

### Corner Radius

| Token | Value | Usage |
|-------|-------|-------|
| `DS.Radius.sm` | 8pt | Chips, small elements |
| `DS.Radius.md` | 12pt | Buttons, cards |
| `DS.Radius.lg` | 16pt | Large cards, covers |
| `DS.Radius.xl` | 20pt | Sheets, modals |

### Opacity Values

For text hierarchy and overlays:

| Token | Value | Usage |
|-------|-------|-------|
| `DS.Opacity.primary` | 1.0 | Primary text |
| `DS.Opacity.secondary` | 0.85 | Secondary text, subtitles |
| `DS.Opacity.tertiary` | 0.7 | Tertiary text, hints |
| `DS.Opacity.quaternary` | 0.5 | Disabled states |
| `DS.Opacity.stroke` | 0.2 | Border strokes |
| `DS.Opacity.subtleStroke` | 0.1 | Subtle borders |

### Shadows

Predefined shadow configurations:

```swift
DS.Shadow.sm     // Small shadow for cards
DS.Shadow.md     // Medium shadow
DS.Shadow.lg     // Large shadow for covers
DS.Shadow.glass  // Glass effect shadow
```

### Animation Durations

| Token | Value | Usage |
|-------|-------|-------|
| `DS.Animation.fast` | 0.2s | Quick transitions |
| `DS.Animation.normal` | 0.3s | Standard animations |
| `DS.Animation.slow` | 0.5s | Slow transitions |
| `DS.Animation.background` | 5.0s | Background animations |

### Layout Constants

| Token | Value | Usage |
|-------|-------|-------|
| `DS.Layout.maxContentWidth` | 700pt | Content max width |
| `DS.Layout.maxSplitWidth` | 1200pt | Split view max width |
| `DS.Layout.maxCoverWidth` | 420pt | Book cover max width |
| `DS.Layout.maxButtonWidth` | 420pt | Button max width |
| `DS.Layout.gridItemMin` | 140pt | Grid minimum item width |
| `DS.Layout.gridItemMax` | 180pt | Grid maximum item width |

## View Modifiers

### Primary Button Style

```swift
Button("Start Reading") {
    // action
}
.primaryButtonStyle()
```

Applies: headline font, black text, white background, rounded corners, shadow.

### Icon Button Style

```swift
Image(systemName: "plus")
    .iconButtonStyle()
```

Applies: white foreground, padding, ultraThinMaterial background, circular shape.

### Book Cover Style

```swift
Rectangle()
    .bookCoverStyle(size: .small)  // or .large
```

Applies: 2:3 aspect ratio, rounded corners, shadow, stroke overlay.

### Synopsis Container Style

```swift
VStack {
    // content
}
.synopsisContainerStyle()
```

Applies: padding, ultraThinMaterial background, rounded corners.

### Chip Style

```swift
Text("Chapter 1")
    .chipStyle()
```

Applies: small padding, ultraThinMaterial background, small corner radius.

### Glass Modifier

```swift
VStack {
    // content
}
.glass(cornerRadius: DS.Radius.xl)
```

Applies: ultraThinMaterial background, shadow, subtle stroke.

## Color Scheme

The app uses a dark color scheme with:
- **Background**: Animated liquid gradient (cyan/blue/purple)
- **Surface**: `.ultraThinMaterial` for glass effects
- **Text**: White with varying opacity for hierarchy
- **Accent**: System accent color

## Typography

Uses system fonts with semantic sizing:
- `.largeTitle.bold()` - Book titles
- `.title2` - Author names
- `.headline` - Section headers
- `.body` - Body text
- `.caption` - Metadata, timestamps
