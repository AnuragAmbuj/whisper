# Import & Parsing System

Whisper uses a modular import and parsing system that handles multiple file formats with dedicated parsers.

## Import Flow

```
User selects file
        ↓
ImportService.importFile(at:)
        ↓
Format detection (extension)
        ↓
┌─────────────────────────────────┐
│           Format Parsers          │
├─────────┬─────────┬─────────────┤
│ EPUB    │ PDF     │ Comic Books  │
│ Parser  │ Direct  │ Parser       │
└─────────┴─────────┴─────────────┘
        ↓
    Book object creation
        ↓
    SwiftData persistence
```

## ImportService

**Location**: `Services/ImportService.swift`

**Purpose**: Unified entry point for all file imports

**Key Methods**:
- `importFile(at: URL) -> Book?` - Main import method
- `importEPUB(from:booksDir:)` - EPUB-specific import
- `importPDF(from:booksDir:documentsDir:)` - PDF-specific import
- `importComic(from:booksDir:ext:)` - Comic book import
- `importText(from:booksDir:)` - Text file import

**Features**:
- Security-scoped resource access
- File copying to app sandbox
- Format-specific metadata extraction
- Cover thumbnail generation
- Error handling with user-friendly messages

## EPUB Parser

**Location**: `Services/EpubParser.swift`

**Purpose**: Extract and parse EPUB e-books

**Process**:
1. **Unzip**: Extract EPUB to UUID folder using MiniZip
2. **Container**: Parse `META-INF/container.xml` to find OPF
3. **OPF**: Parse content.opf for metadata, manifest, spine
4. **Cover**: Extract cover image from manifest
5. **Spine**: Generate reading order and save to `spine.json`
6. **TOC**: Parse table of contents (NCX or Nav Document)
7. **Book**: Create Book object with extracted data

**Supported Features**:
- EPUB 2.0 (NCX navigation)
- EPUB 3.0 (Nav Document navigation)
- Cover image extraction (multiple methods)
- Chapter-based reading order
- Metadata extraction (title, author)

**File Structure**:
```
Documents/Books/{UUID}/
├── META-INF/container.xml
├── [content-dir]/content.opf
├── [content-dir]/toc.ncx (EPUB 2)
├── [content-dir]/nav.xhtml (EPUB 3)
├── spine.json (generated)
├── toc.json (generated)
└── [content files]
```

## Comic Parser

**Location**: `Services/ComicParser.swift`

**Purpose**: Extract and index comic book archives

**Process**:
1. **Extract**: Unzip archive to UUID folder using MiniZip
2. **Discover**: Find all image files in archive
3. **Sort**: Natural sort for correct page order
4. **Cover**: Generate thumbnail from first page
5. **Index**: Save page list to `pages.json`
6. **Book**: Create Book object with page count

**Supported Formats**:
- CBZ (Comic Book ZIP) - Full support
- CBR (Comic Book RAR) - Partial (ZIP-encoded only)

**Supported Images**:
- jpg, jpeg, png, gif, webp, bmp, tiff, tif

**Features**:
- Skips hidden/system files (`__MACOSX`, `._*`)
- Natural alphanumeric sorting
- Cross-platform image handling
- Cover thumbnail generation

## MiniZip

**Location**: `Helpers/MiniZip.swift`

**Purpose**: Cross-platform ZIP extraction

**Features**:
- Works on iOS, iPadOS, and macOS
- No Process dependency (removed iOS build issue)
- Uses Apple's Compression framework
- Supports deflate and stored compression
- File listing capability
- Error handling with detailed messages

**Key Methods**:
- `unzip(sourceURL:destinationURL:)` - Extract archive
- `listFiles(in:)` - List files without extraction

## PDF Handling

**Location**: `ImportService.swift` (direct PDFKit usage)

**Process**:
1. **Copy**: Copy PDF to Books directory
2. **Metadata**: Extract title, author using PDFKit
3. **Thumbnail**: Generate thumbnail from first page
4. **Book**: Create Book object with page count

**Features**:
- Native PDFKit rendering
- Metadata extraction
- Thumbnail generation (300x450)
- Page count tracking

## Text File Handling

**Location**: `ImportService.swift` (direct file reading)

**Process**:
1. **Copy**: Copy TXT file to Books directory
2. **Read**: Load content as UTF-8 string
3. **Book**: Create Book object with content

**Features**:
- UTF-8 encoding support
- Direct file reading
- Customizable typography in reader

## Error Handling

Each parser defines specific error types:

### EpubParserError
```swift
enum EpubParserError: Error {
    case fileNotFound
    case invalidEpub
    case containerNotFound
    case opfNotFound
    case parsingFailed(String)
}
```

### ComicParserError
```swift
enum ComicParserError: Error {
    case fileNotFound
    case invalidArchive
    case noImagesFound
    case unsupportedFormat
    case extractionFailed(String)
}
```

### ImportError
```swift
enum ImportError: Error {
    case fileNotFound
    case copyFailed
    case unsupportedFormat
    case parseFailed(String)
}
```

## Performance Optimizations

### EPUB
- Extracted once to UUID folder
- Spine and TOC cached in JSON
- No re-extraction on subsequent reads

### Comic Books
- Extracted once to UUID folder
- Page list cached in JSON
- Images loaded on-demand

### PDF
- Original file kept (no extraction needed)
- PDFKit handles caching internally

### Text
- Read directly from file
- No caching needed (small files)

## Security Considerations

- **Sandbox Access**: Uses `startAccessingSecurityScopedResource()`
- **File Validation**: Checks file existence and size before parsing
- **Path Sanitization**: Skips hidden/system files in archives
- **Memory Management**: Efficient file reading and extraction

## Future Enhancements

- **Async Parsing**: Move to async/await for large files
- **Progress Reporting**: Show import progress to users
- **Batch Import**: Support importing multiple files at once
- **Cloud Integration**: Import from cloud storage services
- **Format Detection**: Magic number detection instead of extension