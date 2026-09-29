import PDFKit
import SwiftUI

#if os(iOS)
  struct PDFKitView: UIViewRepresentable {
    let url: URL
    @Binding var currentPageIndex: Int
    var totalPages: Binding<Int>? = nil
    var theme: AppTheme? = nil
    var targetSearchSnippet: Binding<String?>? = nil

    func makeCoordinator() -> Coordinator {
      Coordinator(self)
    }

    func makeUIView(context: Context) -> PDFView {
      let pdfView = PDFView()
      pdfView.autoScales = true
      pdfView.minScaleFactor = 0.5
      pdfView.maxScaleFactor = 5.0
      pdfView.displayMode = .singlePageContinuous
      pdfView.displayDirection = .vertical
      if let theme = theme {
        pdfView.backgroundColor = UIColor(theme.backgroundColor)
      } else {
        pdfView.backgroundColor = UIColor.clear
      }

      if let document = PDFDocument(url: url) {
        pdfView.document = document
        DispatchQueue.main.async {
          self.totalPages?.wrappedValue = document.pageCount
        }
        if currentPageIndex < document.pageCount, let page = document.page(at: currentPageIndex) {
          pdfView.go(to: page)
        }
      }

      context.coordinator.setupObserver(for: pdfView)
      return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
      if let theme = theme {
        uiView.backgroundColor = UIColor(theme.backgroundColor)
      }
      if let document = uiView.document,
        currentPageIndex < document.pageCount,
        let page = document.page(at: currentPageIndex),
        uiView.currentPage != page
      {
        uiView.go(to: page)
      }

      // Handle Smart Find passage localization & highlighting
      if let snippet = targetSearchSnippet?.wrappedValue,
         !snippet.isEmpty,
         snippet != context.coordinator.lastHandledSnippet,
         let doc = uiView.document {
        context.coordinator.lastHandledSnippet = snippet
        let clean = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = [clean, String(clean.prefix(40)), String(clean.prefix(25))]
        for term in terms where term.count >= 4 {
          let selections = doc.findString(term, withOptions: .caseInsensitive)
          if let firstSel = selections.first, let page = firstSel.pages.first {
            uiView.go(to: page)
            uiView.setCurrentSelection(firstSel, animate: true)
            uiView.scrollSelectionToVisible(nil)
            let pageIdx = doc.index(for: page)
            if self.currentPageIndex != pageIdx {
              DispatchQueue.main.async {
                self.currentPageIndex = pageIdx
              }
            }
            break
          }
        }
      }
    }

    class Coordinator: NSObject {
      var parent: PDFKitView
      private var observer: NSObjectProtocol?
      var lastHandledSnippet: String? = nil

      init(_ parent: PDFKitView) {
        self.parent = parent
      }

      func setupObserver(for pdfView: PDFView) {
        observer = NotificationCenter.default.addObserver(
          forName: .PDFViewPageChanged,
          object: pdfView,
          queue: .main
        ) { [weak self, weak pdfView] _ in
          guard let self = self, let pdfView = pdfView, let page = pdfView.currentPage else { return }
          if let index = pdfView.document?.index(for: page) {
            if self.parent.currentPageIndex != index {
              self.parent.currentPageIndex = index
            }
          }
        }
      }

      deinit {
        if let observer = observer {
          NotificationCenter.default.removeObserver(observer)
        }
      }
    }
  }
#elseif os(macOS)
  struct PDFKitView: NSViewRepresentable {
    let url: URL
    @Binding var currentPageIndex: Int
    var totalPages: Binding<Int>? = nil
    var theme: AppTheme? = nil
    var targetSearchSnippet: Binding<String?>? = nil

    func makeCoordinator() -> Coordinator {
      Coordinator(self)
    }

    func makeNSView(context: Context) -> PDFView {
      let pdfView = PDFView()
      pdfView.autoScales = true
      pdfView.minScaleFactor = 0.5
      pdfView.maxScaleFactor = 5.0
      pdfView.displayMode = .singlePageContinuous
      pdfView.displayDirection = .vertical
      if let theme = theme {
        pdfView.backgroundColor = NSColor(theme.backgroundColor)
      } else {
        pdfView.backgroundColor = NSColor.clear
      }

      if let document = PDFDocument(url: url) {
        pdfView.document = document
        DispatchQueue.main.async {
          self.totalPages?.wrappedValue = document.pageCount
        }
        if currentPageIndex < document.pageCount, let page = document.page(at: currentPageIndex) {
          pdfView.go(to: page)
        }
      }

      context.coordinator.setupObserver(for: pdfView)
      return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
      if let theme = theme {
        nsView.backgroundColor = NSColor(theme.backgroundColor)
      }
      if let document = nsView.document,
        currentPageIndex < document.pageCount,
        let page = document.page(at: currentPageIndex),
        nsView.currentPage != page
      {
        nsView.go(to: page)
      }

      // Handle Smart Find passage localization & highlighting
      if let snippet = targetSearchSnippet?.wrappedValue,
         !snippet.isEmpty,
         snippet != context.coordinator.lastHandledSnippet,
         let doc = nsView.document {
        context.coordinator.lastHandledSnippet = snippet
        let clean = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = [clean, String(clean.prefix(40)), String(clean.prefix(25))]
        for term in terms where term.count >= 4 {
          let selections = doc.findString(term, withOptions: .caseInsensitive)
          if let firstSel = selections.first, let page = firstSel.pages.first {
            nsView.go(to: page)
            nsView.setCurrentSelection(firstSel, animate: true)
            nsView.scrollSelectionToVisible(nil)
            let pageIdx = doc.index(for: page)
            if self.currentPageIndex != pageIdx {
              DispatchQueue.main.async {
                self.currentPageIndex = pageIdx
              }
            }
            break
          }
        }
      }
    }

    class Coordinator: NSObject {
      var parent: PDFKitView
      private var observer: NSObjectProtocol?
      var lastHandledSnippet: String? = nil

      init(_ parent: PDFKitView) {
        self.parent = parent
      }

      func setupObserver(for pdfView: PDFView) {
        observer = NotificationCenter.default.addObserver(
          forName: .PDFViewPageChanged,
          object: pdfView,
          queue: .main
        ) { [weak self, weak pdfView] _ in
          guard let self = self, let pdfView = pdfView, let page = pdfView.currentPage else { return }
          if let index = pdfView.document?.index(for: page) {
            if self.parent.currentPageIndex != index {
              self.parent.currentPageIndex = index
            }
          }
        }
      }

      deinit {
        if let observer = observer {
          NotificationCenter.default.removeObserver(observer)
        }
      }
    }
  }
#endif
