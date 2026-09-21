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
            // 1. Try Documents directory
            let imageURL = documentsDir.appendingPathComponent(name)
            if let data = try? Data(contentsOf: imageURL) {
                #if canImport(UIKit)
                if let image = UIImage(data: data) {
                    cache.setObject(image, forKey: name as NSString)
                    return image
                }
                #elseif canImport(AppKit)
                if let image = NSImage(data: data) {
                    cache.setObject(image, forKey: name as NSString)
                    return image
                }
                #endif
            }
            
            // 2. Try asset bundle
            #if canImport(UIKit)
            if let assetImage = UIImage(named: name) {
                cache.setObject(assetImage, forKey: name as NSString)
                return assetImage
            }
            #elseif canImport(AppKit)
            if let assetImage = NSImage(named: NSImage.Name(name)) {
                cache.setObject(assetImage, forKey: name as NSString)
                return assetImage
            }
            #endif
            
            // 3. Try direct file path if name is absolute
            if name.hasPrefix("/") {
                let fileURL = URL(fileURLWithPath: name)
                if let data = try? Data(contentsOf: fileURL) {
                    #if canImport(UIKit)
                    if let image = UIImage(data: data) {
                        cache.setObject(image, forKey: name as NSString)
                        return image
                    }
                    #elseif canImport(AppKit)
                    if let image = NSImage(data: data) {
                        cache.setObject(image, forKey: name as NSString)
                        return image
                    }
                    #endif
                }
            }
            
            return nil
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

struct CachedAsyncImage<Placeholder: View, Fallback: View>: View {
    let imageName: String
    let placeholder: Placeholder
    let fallback: Fallback
    
    @State private var loadedImage: PlatformImage?
    @State private var isLoading = true
    
    init(
        imageName: String,
        @ViewBuilder placeholder: () -> Placeholder,
        @ViewBuilder fallback: () -> Fallback
    ) {
        self.imageName = imageName
        self.placeholder = placeholder()
        self.fallback = fallback()
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
                fallback
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

extension CachedAsyncImage where Fallback == Placeholder {
    init(imageName: String, @ViewBuilder placeholder: () -> Placeholder) {
        let p = placeholder()
        self.init(imageName: imageName, placeholder: { p }, fallback: { p })
    }
}
