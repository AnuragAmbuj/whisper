//
//  PhysicalBookScannerView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 24/09/26.
//

import SwiftUI
import SwiftData
import Vision
#if canImport(VisionKit) && os(iOS)
import VisionKit
#endif
#if canImport(PhotosUI)
import PhotosUI
#endif

/// Physical Book Page Scanner & Neural OCR digitizer.
/// Uses Apple Vision Neural OCR and VisionKit camera scanner to convert
/// physical book pages into genuine, standards-compliant EPUB 3 digital books
/// or append new pages into previously scanned books.
struct PhysicalBookScannerView: View {
    enum ScanMode: String, CaseIterable, Identifiable {
        case newBook = "New EPUB Book"
        case appendToExisting = "Append to Existing"
        
        var id: String { rawValue }
    }
    
    var initialTargetBook: Book? = nil
    var onBookCreated: ((Book) -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.lastReadDate, order: .reverse) private var allBooks: [Book]
    
    @State private var scanMode: ScanMode = .newBook
    @State private var selectedBookID: UUID? = nil
    @State private var isScanningCamera: Bool = false
    @State private var isProcessingOCR: Bool = false
    @State private var recognizedText: String = ""
    @State private var bookTitle: String = "Scanned Book"
    @State private var bookAuthor: String = "Physical Capture"
    @State private var scannedPageCount: Int = 0
    @State private var errorMessage: String? = nil
    
    #if os(iOS)
    @State private var capturedImages: [UIImage] = []
    #endif
    
    #if canImport(PhotosUI) && !os(macOS)
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    #endif
    
    private var selectedTargetBook: Book? {
        if let id = selectedBookID {
            return allBooks.first(where: { $0.id == id })
        }
        return initialTargetBook ?? allBooks.first
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DS.Colors.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: DS.Spacing.xl) {
                        // Hero Visual
                        heroHeader
                        
                        // Mode Selection (New EPUB vs Append)
                        modeSelector
                        
                        // Scanner Action Triggers
                        actionButtons
                        
                        // OCR Status & Preview
                        if isProcessingOCR {
                            processingCard
                        } else if !recognizedText.isEmpty {
                            recognizedTextPreviewCard
                        }
                    }
                    .padding(DS.Spacing.lg)
                    .frame(maxWidth: 600)
                }
            }
            .navigationTitle(scanMode == .appendToExisting ? "Append Scanned Pages" : "Scan Physical Book")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                if !recognizedText.isEmpty && !isProcessingOCR {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(scanMode == .appendToExisting ? "Append & Rebuild EPUB" : "Save as EPUB") {
                            saveScannedBook()
                        }
                        .font(.body.weight(.semibold))
                    }
                }
            }
            #if canImport(VisionKit) && os(iOS)
            .fullScreenCover(isPresented: $isScanningCamera) {
                VNDocumentCameraRepresentable { scannedImages in
                    Task {
                        await processScannedPages(scannedImages)
                    }
                } onCancel: {
                    isScanningCamera = false
                }
                .ignoresSafeArea()
            }
            #endif
            #if canImport(PhotosUI) && !os(macOS)
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let item = newItem else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data),
                       let cgImage = uiImage.cgImage {
                        await processSingleCGImage(cgImage, image: uiImage)
                    }
                }
            }
            #endif
            .onAppear {
                if let target = initialTargetBook {
                    scanMode = .appendToExisting
                    selectedBookID = target.id
                    bookTitle = target.title
                    bookAuthor = target.author
                } else if !allBooks.isEmpty && selectedBookID == nil {
                    selectedBookID = allBooks.first?.id
                }
            }
        }
    }
    
    // MARK: - UI Components
    
    private var heroHeader: some View {
        VStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DS.Colors.accent.opacity(0.12))
                    .frame(width: 80, height: 80)
                
                Image(systemName: scanMode == .appendToExisting ? "doc.badge.plus" : "camera.viewfinder")
                    .font(.system(size: 36))
                    .foregroundColor(DS.Colors.accent)
            }
            .padding(.top, DS.Spacing.sm)
            
            VStack(spacing: 4) {
                Text(scanMode == .appendToExisting ? "Append Pages to Book" : "Digitize Physical Pages into EPUB")
                    .font(.title3.bold())
                    .foregroundColor(.primary)
                
                Text(scanMode == .appendToExisting
                     ? "Scan new physical pages to automatically append them as subsequent chapters into '\(selectedTargetBook?.title ?? "selected book")'."
                     : "Scan book pages using your camera. Whisper uses Apple Neural OCR to convert them into a standards-compliant EPUB with full reader styling.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.md)
            }
        }
    }
    
    private var modeSelector: some View {
        VStack(spacing: DS.Spacing.sm) {
            Picker("Mode", selection: $scanMode) {
                ForEach(ScanMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            
            if scanMode == .appendToExisting {
                HStack {
                    Text("Target Book:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Picker("Book", selection: Binding(
                        get: { selectedBookID ?? allBooks.first?.id },
                        set: { newID in
                            selectedBookID = newID
                            if let b = allBooks.first(where: { $0.id == newID }) {
                                bookTitle = b.title
                                bookAuthor = b.author
                            }
                        }
                    )) {
                        ForEach(allBooks) { b in
                            Text(b.title).tag(Optional(b.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(DS.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(DS.Colors.border, lineWidth: 1)
                )
            }
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: DS.Spacing.md) {
            #if canImport(VisionKit) && os(iOS)
            if VNDocumentCameraViewController.isSupported {
                Button(action: { isScanningCamera = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.viewfinder.fill")
                            .font(.headline)
                        Text(scannedPageCount > 0 ? "Scan More Pages (\(scannedPageCount) Captured)" : "Start Camera Scanner")
                            .font(.headline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.primary)
                    .foregroundColor(DS.Colors.onSelection)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            #endif
            
            #if canImport(PhotosUI) && !os(macOS)
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                HStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.headline)
                    Text("Select Page from Photos")
                        .font(.headline.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(DS.Colors.cardBackground)
                .foregroundColor(.primary)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(DS.Colors.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            #endif
        }
    }
    
    private var processingCard: some View {
        VStack(spacing: DS.Spacing.md) {
            ProgressView()
                .controlSize(.large)
                .tint(DS.Colors.accent)
            
            Text("Extracting text via Apple Neural OCR...")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
        }
        .padding(DS.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
    }
    
    private var recognizedTextPreviewCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                Label("\(scannedPageCount) Page\(scannedPageCount == 1 ? "" : "s") Captured", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.bold())
                    .foregroundColor(.green)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "doc.richtext.fill")
                    Text("EPUB 3")
                }
                .font(.caption.bold())
                .foregroundColor(DS.Colors.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DS.Colors.accent.opacity(0.12))
                .clipShape(Capsule())
            }
            
            if scanMode == .newBook {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Book Title")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("Book Title", text: $bookTitle)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Author")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("Author", text: $bookAuthor)
                        .textFieldStyle(.roundedBorder)
                }
            } else if let target = selectedTargetBook {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.turn.down.right")
                        .foregroundColor(.secondary)
                    Text("Appending to:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(target.title)
                        .font(.caption.bold())
                        .lineLimit(1)
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Extracted OCR Text Preview")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(recognizedText)
                    .font(.footnote)
                    .foregroundColor(.primary)
                    .lineLimit(8)
                    .padding(DS.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Colors.unselectedFill)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            }
        }
        .padding(DS.Spacing.lg)
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Colors.border, lineWidth: 1)
        )
    }
    
    // MARK: - OCR Processing
    
    #if os(iOS)
    private func processScannedPages(_ images: [UIImage]) async {
        isScanningCamera = false
        isProcessingOCR = true
        self.capturedImages = images
        var fullText = ""
        
        for (i, image) in images.enumerated() {
            guard let cgImage = image.cgImage else { continue }
            let pageText = await performOCR(on: cgImage)
            if !pageText.isEmpty {
                if i > 0 { fullText += "\n\n--- Page \(i + 1) ---\n\n" }
                fullText += pageText
            }
        }
        
        await MainActor.run {
            self.recognizedText = fullText
            self.scannedPageCount = images.count
            self.isProcessingOCR = false
            
            if scanMode == .newBook {
                if let firstLine = fullText.components(separatedBy: .newlines).first(where: { $0.count > 3 && $0.count < 60 }) {
                    self.bookTitle = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
    }
    
    private func processSingleCGImage(_ cgImage: CGImage, image: UIImage) async {
        isProcessingOCR = true
        self.capturedImages = [image]
        let pageText = await performOCR(on: cgImage)
        await MainActor.run {
            self.recognizedText = pageText
            self.scannedPageCount = 1
            self.isProcessingOCR = false
            if scanMode == .newBook {
                if let firstLine = pageText.components(separatedBy: .newlines).first(where: { $0.count > 3 && $0.count < 60 }) {
                    self.bookTitle = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
    }
    #endif
    
    private func performOCR(on cgImage: CGImage) async -> String {
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, error in
                guard error == nil, let observations = req.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                continuation.resume(returning: text)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }
    
    // MARK: - Save & EPUB Packaging
    
    private func saveScannedBook() {
        if scanMode == .appendToExisting, let target = selectedTargetBook {
            // APPEND MODE: Update existing book with new chapters and rebuild EPUB
            do {
                #if os(iOS)
                let _ = try EpubGeneratorService.shared.appendScannedPages(
                    to: target,
                    newText: recognizedText,
                    newImages: capturedImages
                )
                #else
                let _ = try EpubGeneratorService.shared.appendScannedPages(
                    to: target,
                    newText: recognizedText
                )
                #endif
                
                try? modelContext.save()
                NotificationCenter.default.post(name: .whisperLibraryDidSync, object: nil)
                onBookCreated?(target)
                dismiss()
            } catch {
                errorMessage = "Failed to append pages: \(error.localizedDescription)"
            }
            return
        }
        
        // NEW BOOK MODE: Generate standards-compliant EPUB 3 archive
        let title = bookTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Scanned Physical Book" : bookTitle
        let author = bookAuthor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Physical Capture" : bookAuthor
        let bookID = UUID()
        
        let chapters = EpubGeneratorService.shared.parseTextIntoChapters(recognizedText, defaultTitle: "Page 1")
        
        do {
            #if os(iOS)
            let result = try EpubGeneratorService.shared.generateEpub(
                title: title,
                author: author,
                chapters: chapters,
                coverImage: capturedImages.first,
                bookID: bookID
            )
            #else
            let result = try EpubGeneratorService.shared.generateEpub(
                title: title,
                author: author,
                chapters: chapters,
                bookID: bookID
            )
            #endif
            
            let newBook = Book(
                id: bookID,
                title: title,
                author: author,
                coverImageName: result.coverImageName,
                content: recognizedText,
                lastReadDate: Date(),
                progress: 0.0,
                format: .epub,
                url: result.epubURL
            )
            
            modelContext.insert(newBook)
            try? modelContext.save()
            
            BookService.shared.indexBookInSpotlight(newBook)
            CloudSyncService.shared.uploadBookToCloud(fileURL: result.epubURL)
            NotificationCenter.default.post(name: .whisperLibraryDidSync, object: nil)
            
            onBookCreated?(newBook)
            dismiss()
        } catch {
            errorMessage = "Failed to generate EPUB: \(error.localizedDescription)"
        }
    }
}

// MARK: - iOS VisionKit Document Camera Representable

#if canImport(VisionKit) && os(iOS)
struct VNDocumentCameraRepresentable: UIViewControllerRepresentable {
    let onCompletion: ([UIImage]) -> Void
    let onCancel: () -> Void
    
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }
    
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion, onCancel: onCancel)
    }
    
    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onCompletion: ([UIImage]) -> Void
        let onCancel: () -> Void
        
        init(onCompletion: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onCompletion = onCompletion
            self.onCancel = onCancel
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for i in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: i))
            }
            onCompletion(images)
        }
        
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onCancel()
        }
    }
}
#endif
