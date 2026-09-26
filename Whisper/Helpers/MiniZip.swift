//
//  MiniZip.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import Foundation
import Compression
import zlib

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
            
            if let fileNameData = try? fileHandle.read(upToCount: fileNameLength) {
                let name = decodeFileName(data: fileNameData)
                if !name.isEmpty {
                    files.append(name)
                }
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
    
    private func decodeFileName(data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let latin1 = String(data: data, encoding: .isoLatin1) {
            return latin1
        }
        if let cp1252 = String(data: data, encoding: .windowsCP1252) {
            return cp1252
        }
        return String(decoding: data, as: UTF8.self)
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
            
            guard let fileNameData = try? fileHandle.read(upToCount: fileNameLength) else {
                currentOffset += UInt64(46 + fileNameLength + extraFieldLength + fileCommentLength)
                continue
            }
            
            let fileName = decodeFileName(data: fileNameData)
            guard !fileName.isEmpty else {
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
        // Normalize path separators (handle Windows backslashes)
        let normalizedPath = fileName.replacingOccurrences(of: "\\", with: "/")
        
        if normalizedPath.hasSuffix("/") {
            let dirURL = destinationURL.appendingPathComponent(normalizedPath, isDirectory: true)
            try? fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
            return
        }
        
        let lastComponent = (normalizedPath as NSString).lastPathComponent
        if lastComponent.hasPrefix(".") || lastComponent == "__MACOSX" || normalizedPath.contains("__MACOSX/") {
            return
        }
        
        try fileHandle.seek(toOffset: localHeaderOffset + 26)
        guard let localLengths = try? fileHandle.read(upToCount: 4), localLengths.count >= 4 else { return }
        
        let localFileNameLength = Int(readUInt16(from: localLengths, at: 0))
        let localExtraFieldLength = Int(readUInt16(from: localLengths, at: 2))
        
        let dataOffset = localHeaderOffset + 30 + UInt64(localFileNameLength) + UInt64(localExtraFieldLength)
        try fileHandle.seek(toOffset: dataOffset)
        
        guard compressedSize > 0 else { return }
        guard let compressedData = try? fileHandle.read(upToCount: compressedSize) else { return }
        
        let fileData: Data
        if compressionMethod == 0 {
            fileData = compressedData
        } else if compressionMethod == 8 {
            guard let decompressed = decompressDeflate(compressedData, expectedSize: uncompressedSize) else {
                print("MiniZip Warning: Failed to decompress \(normalizedPath)")
                return
            }
            fileData = decompressed
        } else {
            print("MiniZip Warning: Unsupported compression method \(compressionMethod) for \(normalizedPath)")
            return
        }
        
        let fileURL = destinationURL.appendingPathComponent(normalizedPath)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileData.write(to: fileURL)
    }
    
    private func decompressDeflate(_ compressedData: Data, expectedSize: Int) -> Data? {
        guard expectedSize > 0 else { return Data() }
        
        // 1. Try raw DEFLATE using zlib inflateInit2 (ZIP standard RFC 1951, windowBits = -15)
        var stream = z_stream()
        var status = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        if status == Z_OK {
            var decompressedData = Data(count: expectedSize)
            let result = decompressedData.withUnsafeMutableBytes { (destBuffer: UnsafeMutableRawBufferPointer) -> Int in
                compressedData.withUnsafeBytes { (srcBuffer: UnsafeRawBufferPointer) -> Int in
                    stream.next_in = UnsafeMutablePointer<Bytef>(mutating: srcBuffer.bindMemory(to: Bytef.self).baseAddress)
                    stream.avail_in = uInt(compressedData.count)
                    stream.next_out = destBuffer.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(expectedSize)
                    
                    let ret = inflate(&stream, Z_FINISH)
                    if ret == Z_STREAM_END || ret == Z_OK {
                        return expectedSize - Int(stream.avail_out)
                    }
                    return 0
                }
            }
            inflateEnd(&stream)
            if result > 0 {
                decompressedData.count = result
                return decompressedData
            }
        }
        
        // 2. Try with zlib header (windowBits = 15) in case archive used zlib stream
        var streamZlib = z_stream()
        status = inflateInit2_(&streamZlib, MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        if status == Z_OK {
            var decompressedData = Data(count: expectedSize)
            let result = decompressedData.withUnsafeMutableBytes { (destBuffer: UnsafeMutableRawBufferPointer) -> Int in
                compressedData.withUnsafeBytes { (srcBuffer: UnsafeRawBufferPointer) -> Int in
                    streamZlib.next_in = UnsafeMutablePointer<Bytef>(mutating: srcBuffer.bindMemory(to: Bytef.self).baseAddress)
                    streamZlib.avail_in = uInt(compressedData.count)
                    streamZlib.next_out = destBuffer.bindMemory(to: Bytef.self).baseAddress
                    streamZlib.avail_out = uInt(expectedSize)
                    
                    let ret = inflate(&streamZlib, Z_FINISH)
                    if ret == Z_STREAM_END || ret == Z_OK {
                        return expectedSize - Int(streamZlib.avail_out)
                    }
                    return 0
                }
            }
            inflateEnd(&streamZlib)
            if result > 0 {
                decompressedData.count = result
                return decompressedData
            }
        }
        
        // 3. Fallback to Apple Compression framework
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
        
        if decompressedSize > 0 {
            return Data(bytes: destinationBuffer, count: decompressedSize)
        }
        
        if let decompressed = try? (compressedData as NSData).decompressed(using: .zlib) as Data {
            return decompressed
        }
        
        return nil
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
    // MARK: - Zip Compression API
    
    struct ZipEntry {
        let path: String
        let data: Data
        let uncompressed: Bool
        
        init(path: String, data: Data, uncompressed: Bool = false) {
            self.path = path
            self.data = data
            self.uncompressed = uncompressed
        }
    }
    
    func createZip(entries: [ZipEntry], destination: URL) throws {
        var zipData = Data()
        
        struct CDRecord {
            let path: String
            let uncompressedSize: UInt32
            let compressedSize: UInt32
            let crc: UInt32
            let method: UInt16
            let localHeaderOffset: UInt32
        }
        
        var cdRecords: [CDRecord] = []
        
        for entry in entries {
            guard let pathBytes = entry.path.data(using: .utf8) else { continue }
            let crc = crc32Checksum(entry.data)
            let uncompressedSize = UInt32(entry.data.count)
            let method: UInt16 = entry.uncompressed ? 0 : 8
            let finalData: Data
            if entry.uncompressed {
                finalData = entry.data
            } else {
                finalData = compressDeflate(entry.data) ?? entry.data
            }
            let compressedSize = UInt32(finalData.count)
            let localHeaderOffset = UInt32(zipData.count)
            
            // Local file header (30 bytes + path length)
            var lh = Data()
            var sig: UInt32 = 0x04034b50; lh.append(contentsOf: withUnsafeBytes(of: &sig) { Array($0) })
            var ver: UInt16 = 20; lh.append(contentsOf: withUnsafeBytes(of: &ver) { Array($0) })
            var flag: UInt16 = 0x0800; lh.append(contentsOf: withUnsafeBytes(of: &flag) { Array($0) })
            var meth = method; lh.append(contentsOf: withUnsafeBytes(of: &meth) { Array($0) })
            var time: UInt16 = 0; lh.append(contentsOf: withUnsafeBytes(of: &time) { Array($0) })
            var date: UInt16 = 0x5800; lh.append(contentsOf: withUnsafeBytes(of: &date) { Array($0) })
            var c = crc; lh.append(contentsOf: withUnsafeBytes(of: &c) { Array($0) })
            var cSize = compressedSize; lh.append(contentsOf: withUnsafeBytes(of: &cSize) { Array($0) })
            var uSize = uncompressedSize; lh.append(contentsOf: withUnsafeBytes(of: &uSize) { Array($0) })
            var nLen = UInt16(pathBytes.count); lh.append(contentsOf: withUnsafeBytes(of: &nLen) { Array($0) })
            var eLen: UInt16 = 0; lh.append(contentsOf: withUnsafeBytes(of: &eLen) { Array($0) })
            lh.append(pathBytes)
            lh.append(finalData)
            
            zipData.append(lh)
            
            cdRecords.append(CDRecord(
                path: entry.path,
                uncompressedSize: uncompressedSize,
                compressedSize: compressedSize,
                crc: crc,
                method: method,
                localHeaderOffset: localHeaderOffset
            ))
        }
        
        let cdOffset = UInt32(zipData.count)
        var cdData = Data()
        
        for rec in cdRecords {
            guard let pathBytes = rec.path.data(using: .utf8) else { continue }
            var sig: UInt32 = 0x02014b50; cdData.append(contentsOf: withUnsafeBytes(of: &sig) { Array($0) })
            var verMade: UInt16 = 0x031e; cdData.append(contentsOf: withUnsafeBytes(of: &verMade) { Array($0) })
            var verNeed: UInt16 = 20; cdData.append(contentsOf: withUnsafeBytes(of: &verNeed) { Array($0) })
            var flag: UInt16 = 0x0800; cdData.append(contentsOf: withUnsafeBytes(of: &flag) { Array($0) })
            var meth = rec.method; cdData.append(contentsOf: withUnsafeBytes(of: &meth) { Array($0) })
            var time: UInt16 = 0; cdData.append(contentsOf: withUnsafeBytes(of: &time) { Array($0) })
            var date: UInt16 = 0x5800; cdData.append(contentsOf: withUnsafeBytes(of: &date) { Array($0) })
            var c = rec.crc; cdData.append(contentsOf: withUnsafeBytes(of: &c) { Array($0) })
            var cSize = rec.compressedSize; cdData.append(contentsOf: withUnsafeBytes(of: &cSize) { Array($0) })
            var uSize = rec.uncompressedSize; cdData.append(contentsOf: withUnsafeBytes(of: &uSize) { Array($0) })
            var nLen = UInt16(pathBytes.count); cdData.append(contentsOf: withUnsafeBytes(of: &nLen) { Array($0) })
            var eLen: UInt16 = 0; cdData.append(contentsOf: withUnsafeBytes(of: &eLen) { Array($0) })
            var commLen: UInt16 = 0; cdData.append(contentsOf: withUnsafeBytes(of: &commLen) { Array($0) })
            var diskStart: UInt16 = 0; cdData.append(contentsOf: withUnsafeBytes(of: &diskStart) { Array($0) })
            var intAttr: UInt16 = 0; cdData.append(contentsOf: withUnsafeBytes(of: &intAttr) { Array($0) })
            var extAttr: UInt32 = 0x81a40000; cdData.append(contentsOf: withUnsafeBytes(of: &extAttr) { Array($0) })
            var off = rec.localHeaderOffset; cdData.append(contentsOf: withUnsafeBytes(of: &off) { Array($0) })
            cdData.append(pathBytes)
        }
        
        let cdSize = UInt32(cdData.count)
        zipData.append(cdData)
        
        // End of central directory record
        var eocd = Data()
        var eSig: UInt32 = 0x06054b50; eocd.append(contentsOf: withUnsafeBytes(of: &eSig) { Array($0) })
        var diskNo: UInt16 = 0; eocd.append(contentsOf: withUnsafeBytes(of: &diskNo) { Array($0) })
        var diskCD: UInt16 = 0; eocd.append(contentsOf: withUnsafeBytes(of: &diskCD) { Array($0) })
        var numEntries = UInt16(cdRecords.count); eocd.append(contentsOf: withUnsafeBytes(of: &numEntries) { Array($0) })
        var totalEntries = UInt16(cdRecords.count); eocd.append(contentsOf: withUnsafeBytes(of: &totalEntries) { Array($0) })
        var sCD = cdSize; eocd.append(contentsOf: withUnsafeBytes(of: &sCD) { Array($0) })
        var oCD = cdOffset; eocd.append(contentsOf: withUnsafeBytes(of: &oCD) { Array($0) })
        var cLen: UInt16 = 0; eocd.append(contentsOf: withUnsafeBytes(of: &cLen) { Array($0) })
        zipData.append(eocd)
        
        try zipData.write(to: destination, options: .atomic)
    }
    
    private func crc32Checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { ptr in
            UInt32(zlib.crc32(0, ptr.bindMemory(to: Bytef.self).baseAddress, uInt(data.count)))
        }
    }
    
    private func compressDeflate(_ data: Data) -> Data? {
        var stream = z_stream()
        guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return nil
        }
        defer { deflateEnd(&stream) }
        let bound = Int(deflateBound(&stream, uLong(data.count)))
        let bufferSize = max(bound, 64)
        var output = Data(count: bufferSize)
        return data.withUnsafeBytes { inPtr in
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inPtr.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(data.count)
            return output.withUnsafeMutableBytes { outPtr in
                stream.next_out = outPtr.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(bufferSize)
                guard deflate(&stream, Z_FINISH) == Z_STREAM_END else { return nil }
                let bytesWritten = bufferSize - Int(stream.avail_out)
                return Data(bytes: outPtr.baseAddress!, count: bytesWritten)
            }
        }
    }

}
