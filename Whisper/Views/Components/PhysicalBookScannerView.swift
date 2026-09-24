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
/// physical book pages into digital, readable books with liquid glass styling.
struct PhysicalBookScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var isScanningCamera: Bool = false
    @State private var isProcessingOCR: Bool = false
    @State private var recognizedText: String = ""
    @State private var bookTitle: String = "Scanned Book"
    @State private var bookAuthor: String = "Physical Capture"
    @State private var scannedPageCount: Int = 0
    @State private var errorMessage: String? = nil
    @State private var didCompleteImport: Bool = false
    
    #if canImport(PhotosUI) && !os(macOS)
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    #endif
    
    var onBookCreated: ((Book) -> Void)? = nil
    
    var body: some View {
        NavigationStack {
            ZStack {
                DS.Colors.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: DS.Spacing.xl) {
                        // Hero Visual
                        heroHeader
                        
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
            .navigationTitle("Scan Physical Book")
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
                        Button("Save to Library") {
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
                        await processSingleCGImage(cgImage)
                    }
                }
            }
            #endif
        }
    }
    
    private var heroHeader: some View {
        VStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DS.Colors.accent.opacity(0.12))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 36))
                    .foregroundColor(DS.Colors.accent)
            }
            .padding(.top, DS.Spacing.sm)
            
            VStack(spacing: 4) {
                Text("Digitize Physical Pages")
                    .font(.title3.bold())
                    .foregroundColor(.primary)
                
                Text("Point your camera at a physical book page to scan, extract text with Apple Neural OCR, and continue reading in Whisper.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.md)
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
                        Text("Start Camera Scanner")
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
            }
            
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
            
            VStack(alignment: .leading, spacing: 6) {
                Text("OCR Text Preview")
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
            
            // Auto-guess title from first non-empty line
            if let firstLine = fullText.components(separatedBy: .newlines).first(where: { $0.count > 3 && $0.count < 60 }) {
                self.bookTitle = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
    #endif
    
    private func processSingleCGImage(_ cgImage: CGImage) async {
        isProcessingOCR = true
        let pageText = await performOCR(on: cgImage)
        await MainActor.run {
            self.recognizedText = pageText
            self.scannedPageCount = 1
            self.isProcessingOCR = false
            if let firstLine = pageText.components(separatedBy: .newlines).first(where: { $0.count > 3 && $0.count < 60 }) {
                self.bookTitle = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
    
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
    
    private func saveScannedBook() {
        let title = bookTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Scanned Physical Book" : bookTitle
        let author = bookAuthor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Physical Capture" : bookAuthor
        
        let newBook = Book(
            title: title,
            author: author,
            coverImageName: "",
            content: recognizedText,
            lastReadDate: Date(),
            progress: 0.0,
            format: .text
        )
        
        // Save book content to local Documents/Books file
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let booksDir = docs.appendingPathComponent("Books", isDirectory: true)
            try? FileManager.default.createDirectory(at: booksDir, withIntermediateDirectories: true)
            let safeName = title.replacingOccurrences(of: "/", with: "-") + ".txt"
            let fileURL = booksDir.appendingPathComponent(safeName)
            if let data = recognizedText.data(using: .utf8) {
                try? data.write(to: fileURL)
                newBook.url = fileURL
                CloudSyncService.shared.uploadBookToCloud(fileURL: fileURL)
            }
        }
        
        modelContext.insert(newBook)
        try? modelContext.save()
        BookService.shared.indexBookInSpotlight(newBook)
        
        onBookCreated?(newBook)
        dismiss()
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
    
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
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
