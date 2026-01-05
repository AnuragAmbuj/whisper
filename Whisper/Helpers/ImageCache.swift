//
//  ImageCache.swift
//  Whisper
//
//  Created by Anurag Ambuj on 05/01/26.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

actor ImageCache {
    static let shared = ImageCache()
    
    private var cache = NSCache<NSString, PlatformImage>()
    private var loadingTasks: [String: Task<PlatformImage?, Never>] = [:]
    
    private init() {
        cache.countLimit = 50
        cache.totalCostLimit = 50 * 1024 * 1024
    }
    
    func image(for key: String) -> PlatformImage? {
        cache.object(forKey: key as NSString)
    }
    
    func setImage(_ image: PlatformImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
    
    func loadImage(named name: String, from documentsDir: URL) async -> PlatformImage? {
        guard !name.isEmpty else { return nil }
        
        if let cached = cache.object(forKey: name as NSString) {
            return cached
        }
        
        if let existingTask = loadingTasks[name] {
            return await existingTask.value
        }
        
        let task = Task<PlatformImage?, Never> {
            let imageURL = documentsDir.appendingPathComponent(name)
            
            guard let data = try? Data(contentsOf: imageURL) else { return nil }
            
            #if canImport(UIKit)
            guard let image = UIImage(data: data) else { return nil }
            #elseif canImport(AppKit)
            guard let image = NSImage(data: data) else { return nil }
            #endif
            
            cache.setObject(image, forKey: name as NSString)
            return image
        }
        
        loadingTasks[name] = task
        let result = await task.value
        loadingTasks[name] = nil
        return result
    }
    
    func clearCache() {
        cache.removeAllObjects()
    }
}

struct CachedAsyncImage: View {
    let imageName: String
    let placeholder: AnyView
    
    @State private var loadedImage: PlatformImage?
    @State private var isLoading = true
    
    init(imageName: String, @ViewBuilder placeholder: () -> some View) {
        self.imageName = imageName
        self.placeholder = AnyView(placeholder())
    }
    
    var body: some View {
        Group {
            if let image = loadedImage {
                #if canImport(UIKit)
                Image(uiImage: image)
                    .resizable()
                #elseif canImport(AppKit)
                Image(nsImage: image)
                    .resizable()
                #endif
            } else if isLoading {
                placeholder
            } else {
                placeholder
            }
        }
        .task(id: imageName) {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        guard !imageName.isEmpty else {
            isLoading = false
            return
        }
        
        let fileManager = FileManager.default
        guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            isLoading = false
            return
        }
        
        if let image = await ImageCache.shared.loadImage(named: imageName, from: documentsDir) {
            loadedImage = image
        }
        isLoading = false
    }
}
