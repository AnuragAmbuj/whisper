# Whisper

A universal e-book and comic reader app for iOS, iPadOS, and macOS.

## Features

- **Multi-Format Support**: Read EPUB, PDF, CBZ/CBR comics, and plain text files
- **Universal App**: Native support for iPhone, iPad, and Mac
- **Beautiful UI**: Glass-morphism design with liquid animated backgrounds
- **Library Management**: Organize your books with search and filtering
- **Reading Progress**: Automatically saves your reading position
- **Bookmarks**: Save and manage bookmarks across all formats
- **Customizable Reading**: Adjust font size, line spacing, and themes

## Supported Formats

| Format | Description | Features |
|--------|-------------|----------|
| **EPUB** | Electronic Publication | Full parsing of EPUB 2 & 3, TOC navigation, cover extraction |
| **PDF** | Portable Document Format | Native rendering, page navigation, metadata extraction |
| **CBZ** | Comic Book ZIP | Image extraction, page-by-page reading, pinch-to-zoom |
| **CBR** | Comic Book RAR | Partial support (ZIP-encoded CBR files) |
| **TXT** | Plain Text | Full text rendering with customizable typography |

## Requirements

- iOS 18.0+ / iPadOS 18.0+ / macOS 15.0+
- Xcode 16.0+
- Swift 5.9+

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/Whisper.git
   ```

2. Open `Whisper.xcodeproj` in Xcode

3. Select your target device/simulator

4. Build and run (Cmd + R)

## Architecture

```
Whisper/
├── Design/           # UI design system and modifiers
├── Helpers/          # Utility classes (ZIP extraction, etc.)
├── Models/           # Data models (Book, Bookmark)
├── Services/         # Business logic (parsing, import)
├── ViewModels/       # View state management
└── Views/            # SwiftUI views
    ├── Components/   # Reusable UI components
    └── Readers/      # Format-specific reader views
```

## Documentation

See the [Docs](./Docs) folder for detailed documentation:

- [Architecture Overview](./Docs/Architecture.md)
- [Design System](./Docs/DesignSystem.md)
- [File Format Support](./Docs/FileFormats.md)
- [Import & Parsing](./Docs/ImportParsing.md)

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- SwiftUI for the declarative UI framework
- PDFKit for PDF rendering
- SwiftData for persistence
