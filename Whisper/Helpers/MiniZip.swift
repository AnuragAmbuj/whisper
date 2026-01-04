//
//  MiniZip.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import Foundation
import Compression

enum MiniZipError: Error, LocalizedError {
    case fileNotFound
    case invalidZipFile
    case decompressionFailed
    case unsupportedCompression
    case extractionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "The specified file could not be found or read."
        case .invalidZipFile:
            return "The file is not a valid ZIP archive."
        case .decompressionFailed:
            return "Failed to decompress the file contents."
        case .unsupportedCompression:
            return "The file uses an unsupported compression method."
        case .extractionFailed(let message):
            return "Extraction failed: \(message)"
        }
    }
}

/// Cross-platform ZIP extraction utility for iOS, iPadOS, and macOS
class MiniZip {
    static let shared = MiniZip()
    
    private init() {}
    
    /// Unzips a ZIP archive to the specified destination
    /// - Parameters:
    ///   - sourceURL: URL of the ZIP file
    ///   - destinationURL: Directory to extract contents to
    func unzip(sourceURL: URL, destinationURL: URL) throws {
        let fileManager = FileManager.default
        
        // Validate source file exists
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            print("MiniZip Error: File does not exist at \(sourceURL.path)")
            throw MiniZipError.fileNotFound
        }
        
        // Validate file size
        guard let fileAttributes = try? fileManager.attributesOfItem(atPath: sourceURL.path),
              let fileSize = fileAttributes[.size] as? Int64,
              fileSize > 0 else {
            print("MiniZip Error: Invalid file size")
            throw MiniZipError.invalidZipFile
        }
        
        print("MiniZip: Unzipping '\(sourceURL.lastPathComponent)' (\(fileSize) bytes)")
        
        // Validate ZIP signature
        try validateZipSignature(at: sourceURL)
        
        // Create destination directory
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        
        // Use manual extraction for all platforms (no Process dependency)
        try unzipManually(sourceURL: sourceURL, destinationURL: destinationURL)
        
        print("MiniZip: Successfully unzipped to \(destinationURL.path)")
    }
    
    /// Lists files in a ZIP archive without extracting
    /// - Parameter sourceURL: URL of the ZIP file
    /// - Returns: Array of file paths in the archive
    func listFiles(in sourceURL: URL) throws -> [String] {
        let data = try Data(contentsOf: sourceURL)
        
        guard let eocdOffset = findEOCD(in: data) else {
            throw MiniZipError.invalidZipFile
        }
        
        let cdOffset = readUInt32(from: data, at: eocdOffset + 16)
        let cdCount = readUInt16(from: data, at: eocdOffset + 10)
        
        var files: [String] = []
        var currentOffset = Int(cdOffset)
        
        for _ in 0..<cdCount {
            guard currentOffset + 46 <= data.count else { break }
            
            let signature = readUInt32(from: data, at: currentOffset)
            guard signature == 0x02014b50 else { break }
            
            let fileNameLength = readUInt16(from: data, at: currentOffset + 28)
            let extraFieldLength = readUInt16(from: data, at: currentOffset + 30)
            let fileCommentLength = readUInt16(from: data, at: currentOffset + 32)
            
            let fileNameData = data.subdata(
                in: currentOffset + 46 ..< currentOffset + 46 + Int(fileNameLength)
            )
            
            if let fileName = String(data: fileNameData, encoding: .utf8) {
                files.append(fileName)
            }
            
            currentOffset += 46 + Int(fileNameLength) + Int(extraFieldLength) + Int(fileCommentLength)
        }
        
        return files
    }
    
    // MARK: - Private Methods
    
    private func validateZipSignature(at url: URL) throws {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            throw MiniZipError.fileNotFound
        }
        defer { try? fileHandle.close() }
        
        let headerData = fileHandle.readData(ofLength: 4)
        
        guard headerData.count >= 2,
              headerData[0] == 0x50,
              headerData[1] == 0x4B else {
            print("MiniZip Error: Invalid ZIP signature")
            throw MiniZipError.invalidZipFile
        }
        
        print("MiniZip: Valid ZIP signature detected")
    }
    
    private func unzipManually(sourceURL: URL, destinationURL: URL) throws {
        let data = try Data(contentsOf: sourceURL)
        
        guard let eocdOffset = findEOCD(in: data) else {
            throw MiniZipError.invalidZipFile
        }
        
        let cdOffset = readUInt32(from: data, at: eocdOffset + 16)
        let cdCount = readUInt16(from: data, at: eocdOffset + 10)
        
        print("MiniZip: Found \(cdCount) entries in archive")
        
        var currentOffset = Int(cdOffset)
        let fileManager = FileManager.default
        
        for _ in 0..<cdCount {
            guard currentOffset + 46 <= data.count else { break }
            
            let signature = readUInt32(from: data, at: currentOffset)
            guard signature == 0x02014b50 else {
                print("MiniZip Warning: Invalid CD signature at offset \(currentOffset)")
                break
            }
            
            let compressionMethod = readUInt16(from: data, at: currentOffset + 10)
            let compressedSize = readUInt32(from: data, at: currentOffset + 20)
            let uncompressedSize = readUInt32(from: data, at: currentOffset + 24)
            let fileNameLength = readUInt16(from: data, at: currentOffset + 28)
            let extraFieldLength = readUInt16(from: data, at: currentOffset + 30)
            let fileCommentLength = readUInt16(from: data, at: currentOffset + 32)
            let localHeaderOffset = readUInt32(from: data, at: currentOffset + 42)
            
            let fileNameData = data.subdata(
                in: currentOffset + 46 ..< currentOffset + 46 + Int(fileNameLength)
            )
            guard let fileName = String(data: fileNameData, encoding: .utf8) else {
                currentOffset += 46 + Int(fileNameLength) + Int(extraFieldLength) + Int(fileCommentLength)
                continue
            }
            
            currentOffset += 46 + Int(fileNameLength) + Int(extraFieldLength) + Int(fileCommentLength)
            
            try extractFile(
                from: data,
                fileName: fileName,
                localHeaderOffset: Int(localHeaderOffset),
                compressionMethod: Int(compressionMethod),
                compressedSize: Int(compressedSize),
                uncompressedSize: Int(uncompressedSize),
                to: destinationURL,
                fileManager: fileManager
            )
        }
    }
    
    private func extractFile(
        from data: Data,
        fileName: String,
        localHeaderOffset: Int,
        compressionMethod: Int,
        compressedSize: Int,
        uncompressedSize: Int,
        to destinationURL: URL,
        fileManager: FileManager
    ) throws {
        // Skip directories
        if fileName.hasSuffix("/") {
            let dirURL = destinationURL.appendingPathComponent(fileName)
            try? fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
            return
        }
        
        // Skip hidden/system files
        let lastComponent = (fileName as NSString).lastPathComponent
        if lastComponent.hasPrefix(".") || lastComponent == "__MACOSX" || fileName.contains("__MACOSX/") {
            return
        }
        
        guard localHeaderOffset + 30 <= data.count else { return }
        
        let localFileNameLength = readUInt16(from: data, at: localHeaderOffset + 26)
        let localExtraFieldLength = readUInt16(from: data, at: localHeaderOffset + 28)
        
        let dataOffset = localHeaderOffset + 30 + Int(localFileNameLength) + Int(localExtraFieldLength)
        
        guard dataOffset + compressedSize <= data.count else {
            print("MiniZip Warning: File data extends beyond archive for \(fileName)")
            return
        }
        
        let compressedData = data.subdata(in: dataOffset ..< dataOffset + compressedSize)
        
        let fileData: Data
        if compressionMethod == 0 {
            // Stored (no compression)
            fileData = compressedData
        } else if compressionMethod == 8 {
            // Deflate compression
            guard let decompressed = decompressDeflate(compressedData, expectedSize: uncompressedSize) else {
                print("MiniZip Warning: Failed to decompress \(fileName)")
                return
            }
            fileData = decompressed
        } else {
            print("MiniZip Warning: Unsupported compression method \(compressionMethod) for \(fileName)")
            return
        }
        
        let fileURL = destinationURL.appendingPathComponent(fileName)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileData.write(to: fileURL)
    }
    
    private func decompressDeflate(_ compressedData: Data, expectedSize: Int) -> Data? {
        // Use Apple's Compression framework for raw deflate
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: expectedSize)
        defer { destinationBuffer.deallocate() }
        
        let decompressedSize = compressedData.withUnsafeBytes { (sourceBuffer: UnsafeRawBufferPointer) -> Int in
            guard let sourcePointer = sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return 0
            }
            return compression_decode_buffer(
                destinationBuffer,
                expectedSize,
                sourcePointer,
                compressedData.count,
                nil,
                COMPRESSION_ZLIB
            )
        }
        
        guard decompressedSize > 0 else {
            // Fallback: try NSData zlib decompression
            if let decompressed = try? (compressedData as NSData).decompressed(using: .zlib) as Data {
                return decompressed
            }
            return nil
        }
        
        return Data(bytes: destinationBuffer, count: decompressedSize)
    }
    
    private func findEOCD(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        
        let searchStart = max(0, data.count - 65557)
        let searchEnd = data.count - 22
        
        for i in stride(from: searchEnd, through: searchStart, by: -1) {
            if readUInt32(from: data, at: i) == 0x06054b50 {
                print("MiniZip: Found EOCD at offset \(i)")
                return i
            }
        }
        
        print("MiniZip Error: EOCD not found")
        return nil
    }
    
    private func readUInt16(from data: Data, at offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return data.withUnsafeBytes { bytes in
            bytes.load(fromByteOffset: offset, as: UInt16.self)
        }
    }
    
    private func readUInt32(from data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return data.withUnsafeBytes { bytes in
            bytes.load(fromByteOffset: offset, as: UInt32.self)
        }
    }
}
