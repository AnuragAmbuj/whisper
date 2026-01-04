# Architecture Overview

Whisper follows a clean architecture pattern with clear separation of concerns.

## Project Structure

```
Whisper/
├── Assets.xcassets/      # App icons, colors, and image assets
├── Design/               # Design system and UI modifiers
│   ├── DesignSystem.swift    # Centralized design tokens (DS)
│   ├── GlassModifier.swift   # Glass-morphism effect
│   └── LiquidBackground.swift # Animated gradient background
├── Helpers/              # Utility classes
│   ├── ContentSizePreferenceKey.swift
│   ├── MiniZip.swift         # Cross-platform ZIP extraction
│   └── ScrollOffsetPreferenceKey.swift
├── Models/               # Data models
│   ├── AppTheme.swift        # Reading theme configuration
│   ├── Book.swift            # Core book model (SwiftData)
│   └── Bookmark.swift        # Bookmark model
├── Services/             # Business logic layer
│   ├── BookService.swift     # Book management & seeding
│   ├── ComicParser.swift     # CBZ/CBR parsing
│   ├── EpubParser.swift      # EPUB parsing
│   └── ImportService.swift   # Unified file import
├── ViewModels/           # View state management
│   ├── LibraryViewModel.swift
│   └── ReaderViewModel.swift
└── Views/                # SwiftUI views
    ├── Components/           # Reusable components
    │   ├── BookCoverView.swift
    │   ├── ChapterListView.swift
    │   ├── RoundedCornerShape.swift
    │   └── SettingsSheet.swift
    ├── Readers/              # Format-specific readers
    │   ├── ComicReaderView.swift
    │   ├── EpubReaderView.swift
    │   ├── PDFKitView.swift
    │   └── TextReaderView.swift
    ├── BookDetailView.swift
    ├── BookmarksList.swift
    ├── LibraryView.swift
    └── ReaderView.swift
```

## Layer Responsibilities

### Models Layer
- **Book**: SwiftData model representing a book with metadata, format, progress, and bookmarks
- **Bookmark**: Represents saved positions within a book
- **AppTheme**: Reading customization (font, colors, spacing)

### Services Layer
- **ImportService**: Entry point for file imports, delegates to format-specific parsers
- **EpubParser**: Extracts and parses EPUB files (supports EPUB 2 & 3)
- **ComicParser**: Extracts and indexes comic book archives
- **BookService**: Manages the book library and sample data seeding

### ViewModels Layer
- **LibraryViewModel**: Search, filter, and sort books
- **ReaderViewModel**: Reading state, progress tracking, theme management

### Views Layer
- **LibraryView**: Main grid view of all books
- **BookDetailView**: Book information and "Start Reading" action
- **ReaderView**: Container that loads the appropriate reader based on format
- **Readers/**: Format-specific reading implementations

## Data Flow

```
User selects file
        ↓
ImportService.importFile(at:)
        ↓
    ┌───┴───┐
    ↓       ↓
EpubParser  ComicParser  (or direct PDF/TXT handling)
    ↓       ↓
    └───┬───┘
        ↓
    Book object created
        ↓
    SwiftData persistence
        ↓
    LibraryView updates
```

## Platform Considerations

The app uses conditional compilation for platform-specific code:

```swift
#if os(iOS)
    // iOS/iPadOS specific code
#elseif os(macOS)
    // macOS specific code
#endif

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif
```

Key platform differences:
- **Image handling**: UIImage vs NSImage
- **PDF thumbnails**: Different APIs for generating thumbnails
- **Tab views**: iOS uses `.page` style, macOS uses custom pager
- **Navigation bars**: Different appearance APIs
