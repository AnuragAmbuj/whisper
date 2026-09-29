# Whisper: Complete Android Product & Technical Specification (PRD)

> **Document Version**: 1.0.0  
> **Target Audience**: Antigravity Android Engineering Team / Lead Android Developers  
> **Reference iOS/macOS App**: Whisper (SwiftUI + SwiftData + Multiplatform)  
> **Shared Interoperability**: Cloud Sync protocol (Google Drive AppData), File Formats, AI Prompts & Schemas  

---

## 1. Executive Summary & Vision

### 1.1 Product Philosophy
Whisper is a privacy-first, minimalist, premium multi-format reading application designed to provide a completely distraction-free reading sanctuary. Unlike bloated e-readers burdened with ads, social feeds, and intrusive analytics, Whisper emphasizes:
1. **Apple & Material Minimalism**: Clean typography, high-contrast dark-mode aesthetics, subtle glass-morphism/acrylic surfaces, and fluid micro-interactions.
2. **Universal Format Mastery**: First-class native support for **EPUB** (2.0 & 3.0), **PDF**, **Comics (CBZ & CBR)**, and **Plain Text (TXT)**.
3. **Physical-to-Digital Bridge**: Integrated camera document scanner with on-device OCR that compiles physical pages into personal, readable EPUB books.
4. **Intelligent Reading Companion (TypeSafe AI)**: On-device & Gemini-powered semantic search ("Smart Find"), executive summaries, character relationship maps (Dramatis Personae), and personalized book recommendations.
5. **Seamless Cross-Device Sync**: Zero-lock-in Google Drive AppData synchronization sharing identical reading states, bookmarks, and progress between iOS, macOS, and Android.

### 1.2 Target Hardware & Form Factors
- **Android Phones**: Modern edge-to-edge displays, dynamic punch-hole / notch accommodation, one-handed scrubber navigation.
- **Foldables & Tablets**: Dual-pane layouts, side-by-side book spreads, foldable hinge posture awareness (`WindowSizeClass.EXPANDED`).
- **E-Ink Android Readers (e.g., Onyx Boox, Meebook, Bigme)**: High-contrast monochrome mode, full-refresh trigger support, reduced animations.

---

## 2. Shared Cross-Platform Interoperability Specifications

To allow a user to read on macOS or iPhone and instantly resume on an Android phone or tablet, both platforms **must strictly conform** to the shared data protocols below.

### 2.1 Google Drive Cloud Sync Protocol
- **Storage Location**: Google Drive `appDataFolder` (Hidden from user's Drive UI to prevent accidental modification).
- **Target Filename**: `whisper_cloud_sync.json`
- **Authentication**: Android Credential Manager / Google Sign-In (`com.google.android.gms:play-services-auth`) requesting the scope:
  - `https://www.googleapis.com/auth/drive.appdata`

#### Exact Cloud Sync JSON Schema
```json
{
  "version": 1,
  "lastSyncedTimestamp": 1727351400.123,
  "deviceId": "android-pixel8-uuid-string",
  "records": [
    {
      "bookId": "3FA85F64-5717-4562-B3FC-2C963F66AFA6",
      "title": "Neuromancer",
      "author": "William Gibson",
      "format": "epub",
      "readingProgress": 0.425,
      "currentPage": 118,
      "currentChapter": "Chapter 04",
      "lastReadDate": 1727351300.0,
      "bookmarks": [
        {
          "id": "A1B2C3D4-E5F6-7A8B-9C0D-1E2F3A4B5C6D",
          "pageOrLocation": 118,
          "title": "Chiba City Nightclub",
          "note": "Important character intro",
          "createdAt": 1727351200.0
        }
      ]
    }
  ]
}
```

#### Sync Conflict Resolution Rules
- **Strategy**: Field-level Last-Write-Wins (LWW) driven by `lastReadDate` (UTC Unix timestamp).
- When fetching `whisper_cloud_sync.json`:
  1. Compare local `lastReadDate` with cloud `lastReadDate` for each matching `bookId`.
  2. If cloud timestamp > local timestamp, update local progress, chapter, page, and merge bookmarks.
  3. If local timestamp > cloud timestamp, update cloud payload and push back using Drive `files.update`.

---

## 3. Core Feature Requirements

### 3.1 Library View (Home Experience)
- **Top Bar**:
  - Branding: "Whisper" in bold typography.
  - Search bar: Real-time fuzzy filtering of titles, authors, and conceptual tags.
  - Actions: Cloud Sync Status Indicator (`Synced`, `Syncing`, `Offline`, `Error`), Physical Book Scan button (`camera.viewfinder`), and Import File button (`+`).
- **Filter Chips**:
  - Horizontal scrolling row: `All`, `Comics`, `Books`, `Favorites`, `Recent`.
  - Selected state: High-contrast white background with black text (or inverse in light mode); unselected state: dark translucent capsule.
- **Book Grid**:
  - Adaptive 2 to 4-column responsive grid (`minColumnWidth: 140dp`, `maxColumnWidth: 180dp`).
  - Book Card elements:
    - Cover container (2:3 aspect ratio) with rounded corners (12dp) and 1dp subtle border (`#2A2A2E`).
    - Format badge (`EPUB`, `PDF`, `CBZ`, `TXT`) in top-left or top-right.
    - Cloud status icon on cover (Green checkmark if synced to Google Drive).
    - Bottom progress bar (thin 3dp line) showing completion percentage.
    - Book Title (semibold, max 1 line, ellipsis).
    - Author (caption, secondary color, max 1 line).
- **Long-Press / Context Menu**:
  - Mark as Finished / Reset Progress.
  - Toggle Favorite / Pin.
  - Force Cloud Re-sync.
  - Delete Book (with confirmation modal: "Delete local files").

---

### 3.2 Format-Specific Reading Engines

#### A. Comic & Manga Reader Engine (CBZ & CBR)
- **Archive Handling**:
  - Extract `.cbz` (standard ZIP) and `.cbr` (unrar/zip fallback) into sandbox directory `app_storage/books/{uuid}/`.
  - Filter images: `.jpg`, `.jpeg`, `.png`, `.webp`, `.bmp`, `.gif`.
  - Filter out junk: `__MACOSX`, `._*`, `.DS_Store`, hidden folders.
  - Natural alphanumeric sorting (e.g. `page_2.jpg` before `page_10.jpg`).
- **Reading Modes (Toggleable via bottom HUD)**:
  1. **Paged Mode**:
     - Horizontal `HorizontalPager` with swipe transitions.
     - 3 click zones: Left 25% = Previous Page, Right 25% = Next Page, Center 50% = Toggle Controls HUD.
     - Pinch-to-zoom (up to 3.5x scale) and pan.
  2. **Continuous Webtoon / Manga Mode (Crucial Differentiating Feature)**:
     - Vertical `LazyColumn` with zero or minimal gaps (6dp).
     - **Smart Focal Highlighting**: The page closest to the viewport center dynamically receives focus (1.04x scale spring transition, subtle dark dimming on non-focal pages).
     - Double-tap on active panel to zoom smoothly to 1.75x.
- **Bottom Scrubber Overlay**:
  - Minimal glassmorphism bar floating above reader.
  - Page slider scrubber (`Page X of Y`), Previous/Next arrows, Webtoon/Paged mode switcher, Focal Zoom toggle.
- **Memory Safety**:
  - Continuous image loading in `LazyColumn` **must** cancel image decode jobs as items leave the visible window.
  - Memory cache limit strictly bounded (64 MB to 128 MB max).

#### B. EPUB Reader Engine (EPUB 2.0 & 3.0)
- **Parsing Pipeline**:
  1. Extract archive into `app_storage/books/{uuid}/`.
  2. Locate root via `META-INF/container.xml` -> parse `full-path` attribute pointing to `.opf` package file.
  3. Parse `.opf`:
     - Metadata: `dc:title`, `dc:creator`, `dc:language`.
     - Manifest: Map of `id` to `href` and `media-type`.
     - Spine: Ordered list of `idref` determining reading sequence.
     - Cover: Identify `<meta name="cover">` or `<item properties="cover-image">`.
  4. Parse TOC:
     - EPUB 2: `toc.ncx` (`<navPoint>` tree).
     - EPUB 3: `nav.xhtml` (`<nav epub:type="toc">` list).
  5. Cache `spine.json` and `toc.json` for zero-latency subsequent opens.
- **Rendering Architecture**:
  - High-performance customized Android `WebView` or native Compose text renderer.
  - Inject custom CSS dynamically matching the active **Eye Comfort Theme**:
    - Dark mode, Pure Black, Sepia, Cream, Paper White, Midnight Blue.
    - Dynamic font size (12sp to 32sp), line spacing (1.2 to 2.0), margin width.
  - JavaScript bridge for scroll position reporting & chapter milestone progress.

#### C. PDF Reader Engine
- **Implementation**:
  - AndroidX PDF Viewer or `android.graphics.pdf.PdfRenderer` backed by native rendering.
  - Vertical continuous scroll with single-page snap option.
  - Support pinch-to-zoom (1.0x to 5.0x) with double-tap zoom reset.
  - First-page thumbnail generation stored as JPEG cover cache.

#### D. Plain Text (TXT) Reader Engine
- UTF-8 streaming reader with paragraph formatting, margin controls, and reading theme integration.

---

### 3.3 Physical Book Scanner & Instant EPUB Digitizer
This is one of Whisper's signature innovative features.
- **Workflow**:
  1. User taps Scanner icon in Library.
  2. Camera preview opens with edge detection overlay (using CameraX + ML Kit Document Scanner API or custom overlay).
  3. User captures 1 or more physical pages (e.g. pages from a printed book or paper magazine).
  4. On-Device OCR processes each page via Google ML Kit Text Recognition (`TextRecognizerOptions.DEFAULT_OPTIONS` - 100% offline, zero server calls).
  5. The user reviews scanned pages, edits OCR text if desired, and taps **"Create EPUB"** or **"Append to Book"**.
  6. **Instant EPUB Compilation**:
     - Creates EPUB container structure (`mimetype`, `container.xml`, `content.opf`, XHTML chapter files, images).
     - Zips into a standalone `.epub` file saved to `app_storage/books/{new_uuid}.epub`.
     - Automatically indexes the book in Room DB and opens it in the reader!

---

### 3.4 TypeSafe AI & Reading Intelligence
Whisper provides intelligent reading aids without selling user data. On Android, this uses the **Google AI Client SDK for Kotlin** (`com.google.ai.client.generativeai`) with Gemini 1.5 Flash (or on-device Gemini Nano via AICore where supported).

1. **Smart Find (Semantic Search)**:
   - User types a concept, emotion, or event (e.g. *"When did the protagonist meet the detective at the train station?"*).
   - The engine breaks book content into text windows, computes relevance ranking, and returns exact passage excerpts with direct jump links to the page/chapter.
2. **AI Reader Insights Modal**:
   - **Executive Summary**: 3-sentence high-level synopsis.
   - **Key Takeaways & Themes**: Bulleted thematic insights.
   - **Dramatis Personae**: Structured character profiles (Name, role, description, and key relationships).
   - **Chapter Breakdown**: Concise breakdown of the active chapter.
3. **Bookstore Neural Reranking**:
   - Analyzes user's currently stored books and preferences to rerank store recommendations dynamically.

---

### 3.5 Bookstore & Whisper+ Membership
- **Store Catalog**:
  - Curated collection of royalty-free, classic, and preview books across genres (Sci-Fi, Philosophy, Mystery, Manga, Non-Fiction).
  - Search and genre filtering capsules.
- **Book Details Sheet**:
  - High-res cover, title, author, star rating, genre tag, format badge, and summary description.
  - **"Add to Library"** button: Automatically downloads or unpacks the book asset directly into the user's Library and indexes it.
- **Whisper+ Subscription Model**:
  - Premium membership banner ("Read 50,000+ books and comics without limits").
  - Toggleable subscription state (supports Google Play Billing integration in production).

---

## 4. UI/UX Design System Specification (Parity with iOS `DS`)

Whisper uses a disciplined, dark-first, high-contrast design language.

### 4.1 Spacing Scale (4dp Grid)
| Token | Android Value | Usage |
|:---|:---|:---|
| `DS.Spacing.xxs` | 4dp | Tight micro-spacings, icon padding |
| `DS.Spacing.xs` | 6dp | Capsule vertical padding, badge gaps |
| `DS.Spacing.sm` | 8dp | Standard internal component margins |
| `DS.Spacing.md` | 12dp | Spacing between list items and cards |
| `DS.Spacing.lg` | 16dp | Screen edge horizontal padding |
| `DS.Spacing.xl` | 20dp | Section title spacing |
| `DS.Spacing.xxl` | 24dp | Grid vertical spacing |
| `DS.Spacing.xxxl` | 32dp | Bottom screen inset spacing |

### 4.2 Corner Radii
| Token | Android Value | Usage |
|:---|:---|:---|
| `DS.Radius.sm` | 8dp | Filter chips, small badges |
| `DS.Radius.md` | 12dp | Buttons, store cards, book cover corners |
| `DS.Radius.lg` | 16dp | Floating HUD overlays, dialogs |
| `DS.Radius.xl` | 24dp | Bottom sheets, modal containers |
| `DS.Radius.full` | 9999dp | Circular buttons, pills/capsules |

### 4.3 Color Tokens & Eye Comfort Themes
```kotlin
object WhisperColors {
    // Dark Theme Core
    val Background = Color(0xFF000000)        // Pure AMOLED Black
    val CardBackground = Color(0xFF141416)    // Subtle dark surface
    val Border = Color(0xFF2A2A2E)            // 1dp crisp boundary
    val Selection = Color(0xFFFFFFFF)         // High contrast active state
    val OnSelection = Color(0xFF000000)
    val UnselectedFill = Color(0xFF1C1C1E)
    val TextPrimary = Color(0xFFFFFFFF)
    val TextSecondary = Color(0xFF8E8E93)
    val Accent = Color(0xFF0A84FF)            // System blue highlight
}

enum class EyeComfortTheme(
    val title: String,
    val backgroundColor: Color,
    val textColor: Color
) {
    AMOLED_BLACK("Pure Black", Color(0xFF000000), Color(0xFFE5E5E7)),
    DARK_GRAY("Charcoal", Color(0xFF1C1C1E), Color(0xFFFFFFFF)),
    WARM_SEPIA("Sepia", Color(0xFFFBF0D9), Color(0xFF5F4B32)),
    SOFT_CREAM("Cream", Color(0xFFF8F5EE), Color(0xFF333333)),
    PAPER_WHITE("Paper", Color(0xFFFFFFFF), Color(0xFF111111)),
    MIDNIGHT("Midnight", Color(0xFF0B132B), Color(0xFFE0E6ED))
}
```

### 4.4 Accessibility & Human Interface Guidelines
- **Touch Target**: Every clickable icon/button **must** have a minimum interactive touch area of **48 × 48dp**.
- **Reduce Motion**: Check `LocalReducedMotion.current` or `Settings.Global.TRANSITION_ANIMATION_SCALE`. When reduced motion is enabled:
  - Eliminate continuous pulsing loaders and 3D rotations.
  - Use simple opacity crossfades (150ms).
- **Semantics**: Provide explicit `contentDescription`, `role = Role.Button`, and `stateDescription` (e.g. `"Page 14 of 120"`) on all interactive controls.

---

## 5. Recommended Android Technical Architecture

```
com.whisper.app/
├── data/
│   ├── local/
│   │   ├── WhisperDatabase.kt       # Room Database
│   │   ├── dao/
│   │   │   ├── BookDao.kt
│   │   │   └── BookmarkDao.kt
│   │   └── entities/
│   │       ├── BookEntity.kt
│   │       └── BookmarkEntity.kt
│   ├── remote/
│   │   ├── GoogleDriveClient.kt     # Google Drive REST API AppData Sync
│   │   └── GeminiApiClient.kt       # TypeSafe AI / Gemini SDK
│   ├── parsers/
│   │   ├── EpubParser.kt            # OPF, Spine, TOC parsing
│   │   ├── ComicParser.kt           # CBZ/CBR zip unpacker & sort
│   │   ├── EpubGenerator.kt         # Physical scan to EPUB compiler
│   │   └── MiniZipUtil.kt           # Streaming zip extraction
│   └── repositories/
│       ├── BookRepository.kt
│       ├── CloudSyncRepository.kt
│       └── StoreRepository.kt
├── domain/
│   ├── models/
│   │   ├── Book.kt
│   │   ├── Bookmark.kt
│   │   ├── StoreBook.kt
│   │   └── ReadingTheme.kt
│   └── usecases/
│       ├── ImportBookUseCase.kt
│       ├── SyncWithDriveUseCase.kt
│       ├── ScanAndCreateEpubUseCase.kt
│       └── GenerateAIInsightsUseCase.kt
├── ui/
│   ├── theme/
│   │   ├── Color.kt
│   │   ├── Type.kt
│   │   └── DesignSystem.kt
│   ├── components/
│   │   ├── BookCoverView.kt
│   │   ├── CloudSyncStatusBadge.kt
│   │   ├── SmartFindSheet.kt
│   │   ├── AIInsightsDialog.kt
│   │   └── WhisperBottomBar.kt
│   ├── screens/
│   │   ├── library/
│   │   │   ├── LibraryScreen.kt
│   │   │   └── LibraryViewModel.kt
│   │   ├── reader/
│   │   │   ├── ReaderContainerScreen.kt
│   │   │   ├── ReaderViewModel.kt
│   │   │   ├── ComicReaderView.kt       # Paged & Webtoon Continuous
│   │   │   ├── EpubReaderView.kt
│   │   │   └── PdfReaderView.kt
│   │   ├── scanner/
│   │   │   ├── ScannerScreen.kt
│   │   │   └── ScannerViewModel.kt
│   │   └── store/
│   │       ├── StoreScreen.kt
│   │       └── StoreViewModel.kt
│   └── navigation/
│       └── WhisperNavGraph.kt
└── di/
    └── AppModule.kt                 # Hilt Dependency Injection Modules
```

### 5.1 Tech Stack Summary
- **Language**: Kotlin 2.0+
- **UI Toolkit**: Jetpack Compose (100% Declarative UI)
- **Architecture**: MVI / MVVM + Clean Architecture + Repository Pattern
- **Persistence**: AndroidX Room (SQLite) with Coroutines Flow
- **Asynchronous Execution**: Kotlin Coroutines + Structured Concurrency (`viewModelScope`)
- **Image Pipeline**: Coil 3 (Configured with 64 MB memory cache limit and disk caching)
- **Dependency Injection**: Dagger Hilt
- **AI & ML**:
  - `com.google.ai.client.generativeai` (Gemini SDK)
  - `com.google.android.gms:play-services-mlkit-text-recognition` (On-device OCR)
- **Camera**: AndroidX CameraX (`camera-camera2`, `camera-lifecycle`, `camera-view`)
- **PDF Engine**: AndroidX PDF Viewer or `PdfRenderer`

---

## 6. Room Database Schema (1:1 with SwiftData)

### 6.1 `BookEntity`
```kotlin
@Entity(tableName = "books")
data class BookEntity(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val title: String,
    val author: String = "",
    val coverImagePath: String? = null,
    val format: String, // "epub", "pdf", "comic", "text"
    val localFilePath: String,
    val readingProgress: Double = 0.0,
    val lastReadDate: Long = System.currentTimeMillis(),
    val totalPages: Int = 0,
    val lastPageOrLocation: Int = 0,
    val currentChapterTitle: String? = null,
    val category: String = "General",
    val isFavorite: Boolean = false,
    val isFinished: Boolean = false,
    val isCloudSynced: Boolean = false,
    val rawTextContent: String? = null
)
```

### 6.2 `BookmarkEntity`
```kotlin
@Entity(
    tableName = "bookmarks",
    foreignKeys = [
        ForeignKey(
            entity = BookEntity::class,
            parentColumns = ["id"],
            childColumns = ["bookId"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index("bookId")]
)
data class BookmarkEntity(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val bookId: String,
    val pageOrLocation: Int,
    val title: String,
    val excerpt: String? = null,
    val note: String? = null,
    val createdAt: Long = System.currentTimeMillis()
)
```

---

## 7. Implementation Roadmap & Milestones for Android Developer / Antigravity

### Milestone 1: Foundation & Design System (Sprint 1)
- Setup Gradle build files with Jetpack Compose, Material 3, Hilt, Room, and Coil.
- Implement the centralized `DesignSystem` tokens (`DS.Spacing`, `DS.Radius`, `WhisperColors`).
- Implement bottom navigation bar (`Library`, `Bookstore`, `Import`).
- Setup Room database and repository layer for books and bookmarks.

### Milestone 2: Multi-Format Readers (Sprint 2 & 3)
- **CBZ/CBR Reader**:
  - Implement zip extractor and image list parser.
  - Build `ComicPagerView` (horizontal) and `ComicContinuousScrollView` (vertical Webtoon mode with Smart Focal Highlighting).
- **EPUB Reader**:
  - Build `EpubParser` reading container.xml, OPF, Spine, and TOC.
  - Implement WebView/Compose reader with eye-comfort themes.
- **PDF & TXT Readers**:
  - Integrate `PdfRenderer` and text reader.
- Build reader HUD overlay (top bar metadata, dismiss button, font & theme settings sheet).

### Milestone 3: Google Drive Cross-Platform Cloud Sync (Sprint 4)
- Integrate Android Credential Manager for Google Sign-In with `drive.appdata` scope.
- Implement `GoogleDriveSyncService` reading and writing `whisper_cloud_sync.json`.
- Implement Last-Write-Wins conflict resolution algorithm.
- Verify sync compatibility between Android and iOS/macOS builds.

### Milestone 4: Camera Scanner & Instant EPUB Digitizer (Sprint 5)
- Integrate CameraX with custom document crop viewfinder.
- Hook into ML Kit Text Recognition for fast, on-device OCR.
- Implement `EpubGenerator` packaging scanned text into an EPUB file container.
- Save generated EPUB directly into Room library.

### Milestone 5: TypeSafe AI Insights & Smart Find (Sprint 6)
- Integrate Google AI Client SDK with Gemini 1.5 Flash.
- Implement Smart Find semantic search dialog.
- Implement AI Insights sheet (Executive Summary, Key Takeaways, Dramatis Personae).
- Implement Store neural taste reranking.

### Milestone 6: Polish, Performance & Testing (Sprint 7)
- Memory profiling with Android Studio Profiler (verify comic scroll memory footprint stays < 128 MB).
- Verify dark mode contrast and accessibility semantics across all views.
- Write unit tests for parsers, sync conflict resolution, and Room DAOs.
- Prepare release APK / Android App Bundle (`.aab`).

---

## 8. Summary Checklist for Android Team
- [x] Full UI design token alignment (4dp grid, high-contrast dark aesthetic, 12dp card radius).
- [x] Shared Google Drive AppData sync format (`whisper_cloud_sync.json`) matching iOS exactly.
- [x] Dual-mode comic reader (Paged vs Continuous Webtoon with focal highlight).
- [x] Offline on-device ML Kit OCR for Physical Book Scanner.
- [x] Gemini 1.5 Flash integration for AI Insights & Smart Find.
- [x] Strict $\ge 48\times 48\text{dp}$ touch target adherence.
- [x] Jetpack Compose + Clean Architecture implementation roadmap.
