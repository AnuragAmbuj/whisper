# File Format Support

Whisper supports multiple e-book and comic book formats with full parsing and reading capabilities.

## Supported Formats

### EPUB (Electronic Publication)

**Versions**: EPUB 2.0, EPUB 3.0

**Features**:
- Full metadata extraction (title, author, language)
- Table of Contents parsing (NCX for EPUB 2, Nav Document for EPUB 3)
- Cover image extraction
- Chapter-based navigation
- Reading progress tracking

**Parser**: `EpubParser.swift`

**File Structure**:
```
Documents/Books/{UUID}/
├── META-INF/container.xml
├── content.opf
├── toc.ncx (EPUB 2) or nav.xhtml (EPUB 3)
├── spine.json (generated)
├── toc.json (generated)
└── [content files]
```

### PDF (Portable Document Format)

**Features**:
- Native PDFKit rendering
- Metadata extraction (title, author, subject)
- Page-based navigation
- Thumbnail generation from first page
- Reading progress tracking

**Parser**: `ImportService.swift` (direct PDFKit usage)

**Storage**: Original PDF file stored in `Documents/Books/`

### CBZ (Comic Book ZIP)

**Features**:
- ZIP archive extraction
- Image file discovery and sorting
- Page-by-page reading
- Pinch-to-zoom support
- Cover generation from first page
- Reading progress tracking

**Parser**: `ComicParser.swift`

**Supported Images**: jpg, jpeg, png, gif, webp, bmp, tiff, tif

**File Structure**:
```
Documents/Books/{UUID}/
├── pages.json (generated)
└── [extracted images]
```

### CBR (Comic Book RAR)

**Status**: Partial support

**Features**:
- Attempts to treat as ZIP (many CBR files are ZIP-encoded)
- True RAR support requires additional library integration
- Same features as CBZ if successfully extracted

**Parser**: `ComicParser.swift` (with fallback handling)


### Audiobook (.m4b, .mp3, .m4a, .aac)

**Features**:
- Native `AVFoundation` streaming playback (`AVPlayer`, `AVURLAsset`)
- Variable playback rates: 0.75x, 1x, 1.25x, 1.5x, 1.75x, 2.0x
- Sleep timer presets: 5, 15, 30, 45, 60 minutes
- Skip forward 30s / rewind 15s quick scrubbing
- Lock Screen & Control Center integration via `MPNowPlayingInfoCenter` and remote commands
- Chapter cues & chapter navigation drawer
- Time-based bookmarks (`MM:SS` or `H:MM:SS`) with custom notes
- Embedded artwork and ID3 / MP4 metadata extraction during import
- Liquid Glass ambient audio player UI with reactive waveform animation

**Player**: `AudiobookPlayerService.swift` / `AudiobookPlayerView.swift`

**Parser**: `ImportService.swift` (`importAudiobookSync` using `AVURLAsset`)

**Storage**: Original audio file stored in `Documents/Books/{UUID}/`

### TXT (Plain Text)

**Features**:
- UTF-8 text rendering
- Customizable typography
- Scroll-based reading
- Reading progress tracking

**Parser**: `ImportService.swift` (direct file reading)

**Storage**: Original TXT file stored in `Documents/Books/`

## Import Process

1. **File Selection**: User selects file via system file picker
2. **Format Detection**: Extension determines parsing strategy
3. **Security Access**: `startAccessingSecurityScopedResource()` for sandboxed files
4. **Parsing**: Format-specific parser extracts content and metadata
5. **Storage**: Files stored in `Documents/Books/` with unique UUID folders
6. **Database**: Book object created and saved to SwiftData

## File Type Registration

The app registers these UTTypes for import:

```swift
ImportService.supportedTypes = [
    .pdf,           // PDF documents
    .epub,          // EPUB e-books
    .zip,           // CBZ comic books
    UTType(filenameExtension: "cbz"),  // Comic Book ZIP
    UTType(filenameExtension: "cbr"),  // Comic Book RAR
    .plainText      // TXT files
]
```

## Error Handling

Each parser defines specific error types:

- `EpubParserError`: Invalid EPUB, container not found, parsing failed
- `ComicParserError`: Invalid archive, no images found, unsupported format
- `ImportError`: File not found, copy failed, unsupported format

## Performance Considerations

- **EPUB**: Extracted once, cached in UUID folder
- **PDF**: Original file kept, PDFKit handles caching
- **CBZ/CBR**: Extracted once, page list cached in JSON
- **TXT**: Read directly from file

## Future Enhancements

- **CBR**: Full RAR support with UnRAR library integration
- **MOBI**: Kindle format support
- **AZW**: Amazon Kindle format support
- **DJVU**: DjVu document format support
- **Audio Books**: MP3/M4A with chapter support