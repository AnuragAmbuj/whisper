<div align="center">

  <img src="Docs/images/logo.svg" alt="Whisper Mark" width="112" height="112" />

  # Whisper

  **A sanctuary for your books, comics, and audiobooks.**  
  *Crafted natively with SwiftUI, AppKit/UIKit, and on-device Apple Intelligence.*

  [![Platform](https://img.shields.io/badge/Platform-iOS%2018%20%7C%20iPadOS%2018%20%7C%20macOS%2015-black?style=flat-square&logo=apple)](https://developer.apple.com)
  [![Language](https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift)](https://swift.org)
  [![SwiftUI](https://img.shields.io/badge/UI-SwiftUI%20Native-007AFF?style=flat-square&logo=swift)](https://developer.apple.com/xcode/swiftui/)
  [![Privacy](https://img.shields.io/badge/Privacy-100%25%20On--Device-success?style=flat-square&logo=apple)](LICENSE)
  [![License](https://img.shields.io/badge/License-MIT-green.svg?style=flat-square)](LICENSE)

  <br />

  <table>
    <tr>
      <td align="center" width="50%">
        <img src="Docs/images/screenshot_library.jpg" alt="Whisper Library" width="100%" />
        <br />
        <sub><b>Universal Library</b> &bull; Fluid glass cards, category filters & reading progress</sub>
      </td>
      <td align="center" width="50%">
        <img src="Docs/images/screenshot_reader.jpg" alt="Whisper Reader" width="100%" />
        <br />
        <sub><b>Reading Sanctuary</b> &bull; Warm Sepia palette with TypeSafe AI passage highlight</sub>
      </td>
    </tr>
    <tr>
      <td align="center" width="50%">
        <img src="Docs/images/screenshot_audiobook.jpg" alt="Audiobook Player" width="100%" />
        <br />
        <sub><b>Audiobook Player</b> &bull; Dynamic waveform, chapter markers & sleep timer</sub>
      </td>
      <td align="center" width="50%">
        <img src="Docs/images/screenshot_comic.jpg" alt="Comic & Webtoon Reader" width="100%" />
        <br />
        <sub><b>Comics & Manga</b> &bull; Continuous Webtoon vertical flow & focal zoom</sub>
      </td>
    </tr>
  </table>

</div>

---

## The Story Behind Whisper

Most reading applications today have forgotten what it feels like to lose yourself in a book. They have become cluttered with telemetry, aggressive upsells, sluggish cross-platform wrappers, and fragmented file support. Readers find themselves juggling one app for EPUBs, another for PDF documents, a separate viewer for manga and comics, and a fourth app for audiobooks.

**Whisper was built to be different.**

It is an uncompromising, unified reading sanctuary engineered natively in Swift 6 and SwiftUI. Whether you are engrossed in an 800-page fantasy tome, studying an academic PDF, scrolling through a vertical full-color webtoon, or listening to a 20-hour audiobook during your evening walk—Whisper handles each medium with the exact same fluid responsiveness, aesthetic elegance, and battery-friendly performance.

---

## 🎨 Design Philosophy & Craftsmanship

### The Whisper Mark
Our icon represents a visual triple-entendre:
1. **A flowing 'W'** for Whisper.
2. **An alternating soundwave** reflecting spoken word and audiobook narration.
3. **The silhouette of an open book**, with fluttering pages catching the light.

### Eye Comfort Color Science
Extended reading demands typography and contrast that respect your circadian rhythm. Whisper ships with four meticulously calibrated palettes:
* 📄 **Paper White**: Neutral daylight balance with soft contrast for bright ambient environments.
* 📜 **Warm Sepia**: Low blue-light tint reminiscent of aged parchment, engineered to minimize eye strain.
* 🌌 **Midnight OLED**: True pure black (`#000000`) for zero pixel glow and battery conservation on OLED displays.
* 🌲 **Forest Moss**: A calming organic sage undertone popular for long technical or academic study sessions.

### Native Glassmorphism
Toolbars and HUD navigation surfaces utilize translucent frosted materials (`.ultraThinMaterial`) that gracefully blur underlying illustrations and pages, keeping the focal priority squarely on the author's words.

---

## ⚡ Core Capabilities

### 📚 Universal Multi-Format Reading Engine

| Format | Native Engine | Key Features |
|---|---|---|
| **EPUB (2.0 / 3.0)** | WebKit + Custom CSS Engine | Buttery smooth vertical scrolling or paginated edge-tap column reading, custom font families, dynamic line height, instant chapter transitions. |
| **PDF** | Native `PDFKit` | Full document outline tree navigation, pinch-to-zoom, high-res vector rendering, search selection jumps with visual highlights. |
| **CBZ / CBR Comics** | High-Speed Archive Pipeline | Instant archive extraction with zero memory bloat. Switch seamlessly between horizontal page flipping and continuous vertical **Webtoon Mode** with dynamic focal zoom. |
| **Plain Text / Markdown** | Pure SwiftUI Engine | Auto-detected markdown headings (`#`, `##`, `###`), structured line indexing, smooth programmatic scrolling via `ScrollViewReader`. |
| **Audiobooks (M4B, MP3, M4A, AAC)** | `AVFoundation` Audio Suite | Dynamic waveform scrubber, 15-second skip buttons, chapter cue extraction, playback speeds (0.75x–2.0x), sleep timer, and lock screen Now Playing controls. |

---

### 🧠 TypeSafe AI Smart Find (Zero-Cloud Semantic Search)

Finding a specific moment shouldn't require remembering the exact phrasing of a sentence. Whisper integrates an on-device semantic passage locator powered by Apple’s **Natural Language (`NLEmbedding`)** framework:

* **Vectorless Neural Retrieval**: Pinpoints passages matching concepts, themes, or emotional tone without external cloud vector databases or third-party dependencies.
* **Interactive Navigation**: Tap any search match to jump directly to that exact page, line, or audio timestamp.
* **Visual Glow Feedback**: Navigated text pulses with an ambient golden glow for 2.5 seconds, orienting your eyes immediately.
* **Dramatis Personae**: Automatically extracts and maps character lore, recurring figures, and role descriptions across your books.

---

### 📸 Physical Book Scanner
Turn physical paperbacks into digital EPUBs directly on your device:
* Point your camera at any printed book page using Apple's **Vision OCR**.
* Whisper automatically cleans, straightens, and formats captured text into structured chapters.
* Append newly scanned pages to an existing reading file or generate a standalone digital edition in seconds.

---

### ☁️ Dual-Engine Cloud Sync
Keep your entire reading universe in sync across iPhone, iPad, and Mac:
* **iCloud Drive**: Transparent background synchronization. Whisper detects `.icloud` dataless files and automatically triggers background hydration with zero reader stalls.
* **Direct Google Drive Engine**: A lightweight, zero-dependency REST implementation allowing seamless multi-device syncing without heavy SDKs.
* **Intelligent Debouncing**: Reading locations are saved instantly in memory and flushed to cloud storage during pauses and view transitions, protecting battery and cellular bandwidth.

---

## 🎙️ Siri & Apple Intelligence Shortcuts

Whisper deeply integrates with Apple's **App Intents** architecture. You can control your reading hands-free via Siri or automate routines in the Shortcuts app:

```swift
"Hey Siri, continue reading in Whisper"
↳ Resumes your most recent book or audiobook right where you left off.

"Hey Siri, read Dune in Whisper"
↳ Queries your library and opens the requested title immediately.

"Hey Siri, what am I reading in Whisper?"
↳ Informs you of your active book title, author, and reading percentage.

"Hey Siri, bookmark this page in Whisper"
↳ Creates a bookmark at your exact location without interrupting your session.

"Hey Siri, summarize book in Whisper"
↳ Generates an executive on-device AI synopsis of your active book.
```

---

## ⌨️ Keyboard Shortcuts (iPad & Mac)

Whisper provides desktop-class productivity shortcuts:

| Shortcut | Action |
|---|---|
| <kbd>⌘</kbd> <kbd>F</kbd> | Open TypeSafe AI Smart Find |
| <kbd>⌘</kbd> <kbd>B</kbd> | Open Chapters, Bookmarks & Lore Sheet |
| <kbd>⌘</kbd> <kbd>,</kbd> | Open Reading Settings & Appearance |
| <kbd>⌘</kbd> <kbd>W</kbd> or <kbd>Esc</kbd> | Close Reader and Return to Library |
| <kbd>Space</kbd> | Play / Pause Audiobook |
| <kbd>→</kbd> / <kbd>←</kbd> | Next / Previous Page or Chapter |

---

## 🏗️ Clean Modular Architecture

```
Whisper/
├── Design/
│   ├── DesignSystem.swift           # Central design tokens (DS.Spacing, DS.Colors, DS.Fonts)
│   ├── GlassModifier.swift          # Ultra-thin material glassmorphic styling
│   └── LiquidBackground.swift       # Fluid ambient canvas reactive to theme
├── Helpers/
│   ├── MiniZip.swift                # Streaming ZIP extraction with low memory footprint
│   ├── ImageCache.swift             # Actor-isolated memory-bounded cover cache
│   └── WebKitWarmer.swift           # Pre-warmed WKWebView pool eliminating cold starts
├── Intents/
│   ├── BookEntity.swift             # AppEntity & EntityQuery for Spotlight & Siri
│   └── WhisperIntents.swift         # AppShortcutsProvider & Siri action handlers
├── Models/
│   ├── Book.swift                   # SwiftData model with automatic format resolution
│   ├── Bookmark.swift               # Time and page-based bookmark entity
│   └── AppTheme.swift               # Eye Comfort theme definitions
├── Services/
│   ├── AudiobookPlayerService.swift # AVFoundation audio player & Now Playing engine
│   ├── ChapterService.swift         # Universal chapter extractor (EPUB, PDF, Comic, Text, Audio)
│   ├── CloudSyncService.swift       # iCloud Drive sync & fault downloader
│   ├── GoogleDriveSyncService.swift # Zero-dependency Google Drive REST engine
│   ├── TypeSafeService.swift        # NLEmbedding semantic search & Dramatis Personae
│   ├── EpubGeneratorService.swift   # Camera OCR text to EPUB synthesizer
│   └── ImportService.swift          # Universal drag-and-drop & file coordinator
├── ViewModels/
│   ├── LibraryViewModel.swift       # Library category filtering and search queries
│   └── ReaderViewModel.swift        # Reading location tracking & progress debouncing
└── Views/
    ├── BookmarksList.swift          # Segmented Chapters, Bookmarks, and Lore inspector
    ├── LibraryView.swift            # Main library grid with animated progress rings
    ├── ReaderView.swift             # Universal reader container
    └── Readers/
        ├── AudiobookPlayerView.swift # Native audio player with dynamic waveform
        ├── ComicReaderView.swift     # Paged & Webtoon comic reader with focal zoom
        ├── EpubReaderView.swift      # WebKit continuous & paginated EPUB viewer
        ├── PDFKitView.swift          # Native PDFKit representable with search jumps
        └── TextReaderView.swift      # ScrollViewReader paragraph-indexed text reader
```

---

## 🛠️ Requirements & Getting Started

### Prerequisites
* **macOS 15.0+** (Sequoia)
* **Xcode 16.0+**
* Deployment targets: **iOS 18.0+**, **iPadOS 18.0+**, **macOS 15.0+**
* Swift 6.0 toolchain

### Build Instructions
```bash
# 1. Clone the repository
git clone https://github.com/AnuragAmbuj/whisper.git
cd whisper

# 2. Open project in Xcode
open Whisper.xcodeproj

# 3. Select target scheme (Whisper) and your device/simulator
# 4. Press ⌘R to build and run
# 5. Press ⌘U to run the test suite (54/54 tests passing)
```

---

## 🛡️ Privacy & Sovereignty

Whisper respects your digital sovereignty:
* **No Telemetry**: Zero tracking pixels, user tracking frameworks, or analytics beacons.
* **On-Device Machine Learning**: AI summaries and semantic searches run entirely on your local Apple Neural Engine.
* **Direct Cloud Synchronization**: Cloud sync communicates exclusively with your personal iCloud container or your direct authenticated Google Drive folder.

---

## 📄 License

Whisper is open-source software released under the [MIT License](LICENSE).
