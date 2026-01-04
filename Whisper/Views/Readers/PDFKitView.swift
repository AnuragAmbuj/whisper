import PDFKit
import SwiftUI

#if os(iOS)
  struct PDFKitView: UIViewRepresentable {
    let url: URL
    @Binding var currentPageIndex: Int

    func makeUIView(context: Context) -> PDFView {
      let pdfView = PDFView()
      pdfView.autoScales = true
      pdfView.displayMode = .singlePageContinuous
      pdfView.displayDirection = .vertical

      // Load document
      if let document = PDFDocument(url: url) {
        pdfView.document = document
      }

      return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
      // Update logic if needed
      if let document = uiView.document,
        currentPageIndex < document.pageCount,
        let page = document.page(at: currentPageIndex),
        uiView.currentPage != page
      {
        uiView.go(to: page)
      }
    }
  }
#elseif os(macOS)
  struct PDFKitView: NSViewRepresentable {
    let url: URL
    @Binding var currentPageIndex: Int

    func makeNSView(context: Context) -> PDFView {
      let pdfView = PDFView()
      pdfView.autoScales = true
      pdfView.displayMode = .singlePageContinuous
      pdfView.displayDirection = .vertical

      if let document = PDFDocument(url: url) {
        pdfView.document = document
      }

      return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
      // Update logic if needed
      if let document = nsView.document,
        currentPageIndex < document.pageCount,
        let page = document.page(at: currentPageIndex),
        nsView.currentPage != page
      {
        nsView.go(to: page)
      }
    }
  }
#endif
