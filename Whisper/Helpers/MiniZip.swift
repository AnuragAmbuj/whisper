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

class MiniZip {
    static let shared = MiniZip()
    
    private init() {}
    
    func unzip(sourceURL: URL, destinationURL: URL) throws {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw MiniZipError.fileNotFound
        }
        
        guard let fileAttributes = try? fileManager.attributesOfItem(atPath: sourceURL.path),
              let fileSize = fileAttributes[.size] as? UInt64,
              fileSize > 0 else {
            throw MiniZipError.invalidZipFile
        }
        
        print("MiniZip: Unzipping '\(sourceURL.lastPathComponent)' (\(fileSize) bytes)")
        
        guard let fileHandle = try? FileHandle(forReadingFrom: sourceURL) else {
            throw MiniZipError.fileNotFound
        }
        defer { try? fileHandle.close() }
        
        try validateZipSignature(fileHandle: fileHandle)
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        try unzipStreaming(fileHandle: fileHandle, fileSize: fileSize, destinationURL: destinationURL)
        
        print("MiniZip: Successfully unzipped to \(destinationURL.path)")
    }
    
    func listFiles(in sourceURL: URL) throws -> [String] {
        guard let fileHandle = try? FileHandle(forReadingFrom: sourceURL) else {
            throw MiniZipError.fileNotFound
        }
        defer { try? fileHandle.close() }
        
        let fileSize = try fileHandle.seekToEnd()
        guard let eocdInfo = findEOCDStreaming(fileHandle: fileHandle, fileSize: fileSize) else {
            throw MiniZipError.invalidZipFile
        }
        
        var files: [String] = []
        var currentOffset = UInt64(eocdInfo.cdOffset)
        
        for _ in 0..<eocdInfo.cdCount {
            try fileHandle.seek(toOffset: currentOffset)
            guard let headerData = try? fileHandle.read(upToCount: 46), headerData.count >= 46 else { break }
            
            let signature = readUInt32(from: headerData, at: 0)
            guard signature == 0x02014b50 else { break }
            
            let fileNameLength = Int(readUInt16(from: headerData, at: 28))
            let extraFieldLength = Int(readUInt16(from: headerData, at: 30))
            let fileCommentLength = Int(readUInt16(from: headerData, at: 32))
            
            if let fileNameData = try? fileHandle.read(upToCount: fileNameLength),
               let fileName = String(data: fileNameData, encoding: .utf8) {
                files.append(fileName)
            }
            
            currentOffset += UInt64(46 + fileNameLength + extraFieldLength + fileCommentLength)
        }
        
        return files
    }
    
    private func validateZipSignature(fileHandle: FileHandle) throws {
        try fileHandle.seek(toOffset: 0)
        guard let headerData = try? fileHandle.read(upToCount: 4),
              headerData.count >= 2,
              headerData[0] == 0x50,
              headerData[1] == 0x4B else {
            throw MiniZipError.invalidZipFile
        }
        print("MiniZip: Valid ZIP signature detected")
    }
    
    private struct EOCDInfo {
        let cdOffset: UInt32
        let cdCount: UInt16
    }
    
    private func findEOCDStreaming(fileHandle: FileHandle, fileSize: UInt64) -> EOCDInfo? {
        let searchSize = min(fileSize, 65557)
        let searchStart = fileSize - searchSize
        
        try? fileHandle.seek(toOffset: searchStart)
        guard let searchData = try? fileHandle.read(upToCount: Int(searchSize)) else { return nil }
        
        for i in stride(from: searchData.count - 22, through: 0, by: -1) {
            if readUInt32(from: searchData, at: i) == 0x06054b50 {
                let cdCount = readUInt16(from: searchData, at: i + 10)
                let cdOffset = readUInt32(from: searchData, at: i + 16)
                print("MiniZip: Found EOCD, \(cdCount) entries")
                return EOCDInfo(cdOffset: cdOffset, cdCount: cdCount)
            }
        }
        return nil
    }
    
    private func unzipStreaming(fileHandle: FileHandle, fileSize: UInt64, destinationURL: URL) throws {
        guard let eocdInfo = findEOCDStreaming(fileHandle: fileHandle, fileSize: fileSize) else {
            throw MiniZipError.invalidZipFile
        }
        
        let fileManager = FileManager.default
        var currentOffset = UInt64(eocdInfo.cdOffset)
        
        for _ in 0..<eocdInfo.cdCount {
            try fileHandle.seek(toOffset: currentOffset)
            guard let headerData = try? fileHandle.read(upToCount: 46), headerData.count >= 46 else { break }
            
            let signature = readUInt32(from: headerData, at: 0)
            guard signature == 0x02014b50 else { break }
            
            let compressionMethod = Int(readUInt16(from: headerData, at: 10))
            let compressedSize = Int(readUInt32(from: headerData, at: 20))
            let uncompressedSize = Int(readUInt32(from: headerData, at: 24))
            let fileNameLength = Int(readUInt16(from: headerData, at: 28))
            let extraFieldLength = Int(readUInt16(from: headerData, at: 30))
            let fileCommentLength = Int(readUInt16(from: headerData, at: 32))
            let localHeaderOffset = UInt64(readUInt32(from: headerData, at: 42))
            
            guard let fileNameData = try? fileHandle.read(upToCount: fileNameLength),
                  let fileName = String(data: fileNameData, encoding: .utf8) else {
                currentOffset += UInt64(46 + fileNameLength + extraFieldLength + fileCommentLength)
                continue
            }
            
            currentOffset += UInt64(46 + fileNameLength + extraFieldLength + fileCommentLength)
            
            try extractFileStreaming(
                fileHandle: fileHandle,
                fileName: fileName,
                localHeaderOffset: localHeaderOffset,
                compressionMethod: compressionMethod,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                destinationURL: destinationURL,
                fileManager: fileManager
            )
        }
    }
    
    private func extractFileStreaming(
        fileHandle: FileHandle,
        fileName: String,
        localHeaderOffset: UInt64,
        compressionMethod: Int,
        compressedSize: Int,
        uncompressedSize: Int,
        destinationURL: URL,
        fileManager: FileManager
    ) throws {
        if fileName.hasSuffix("/") {
            let dirURL = destinationURL.appendingPathComponent(fileName)
            try? fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
            return
        }
        
        let lastComponent = (fileName as NSString).lastPathComponent
        if lastComponent.hasPrefix(".") || lastComponent == "__MACOSX" || fileName.contains("__MACOSX/") {
            return
        }
        
        try fileHandle.seek(toOffset: localHeaderOffset + 26)
        guard let localLengths = try? fileHandle.read(upToCount: 4), localLengths.count >= 4 else { return }
        
        let localFileNameLength = Int(readUInt16(from: localLengths, at: 0))
        let localExtraFieldLength = Int(readUInt16(from: localLengths, at: 2))
        
        let dataOffset = localHeaderOffset + 30 + UInt64(localFileNameLength) + UInt64(localExtraFieldLength)
        try fileHandle.seek(toOffset: dataOffset)
        
        guard let compressedData = try? fileHandle.read(upToCount: compressedSize) else { return }
        
        let fileData: Data
        if compressionMethod == 0 {
            fileData = compressedData
        } else if compressionMethod == 8 {
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
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileData.write(to: fileURL)
    }
    
    private func decompressDeflate(_ compressedData: Data, expectedSize: Int) -> Data? {
        guard expectedSize > 0 else { return Data() }
        
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
            if let decompressed = try? (compressedData as NSData).decompressed(using: .zlib) as Data {
                return decompressed
            }
            return nil
        }
        
        return Data(bytes: destinationBuffer, count: decompressedSize)
    }
    
    private func readUInt16(from data: Data, at offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }
    
    private func readUInt32(from data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) |
               (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }
}
