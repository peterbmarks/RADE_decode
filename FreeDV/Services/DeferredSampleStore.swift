import Foundation

/// Stores raw 8kHz Int16 samples to disk while app is in background.
/// Samples are written as little-endian Int16 PCM stream.
final class DeferredSampleStore {
    private let fileManager = FileManager.default
    private var fileHandle: FileHandle?

    private var fileURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("deferred_samples.pcm")
    }

    private func ensureWriter() -> FileHandle? {
        if fileHandle == nil {
            if !fileManager.fileExists(atPath: fileURL.path) {
                fileManager.createFile(atPath: fileURL.path, contents: nil)
            }
            fileHandle = try? FileHandle(forWritingTo: fileURL)
            fileHandle?.seekToEndOfFile()
        }
        return fileHandle
    }

    func reset() {
        fileHandle?.closeFile()
        fileHandle = nil
        try? fileManager.removeItem(at: fileURL)
    }

    func appendRawInt16(_ samples: UnsafePointer<Int16>, count: Int) {
        guard count > 0 else { return }
        guard let handle = ensureWriter() else { return }
        let data = Data(bytes: samples, count: count * MemoryLayout<Int16>.size)
        handle.write(data)
    }

    func totalSampleCount() -> Int {
        let bytes: UInt64
        if let handle = fileHandle {
            bytes = handle.seekToEndOfFile()
        } else {
            guard let attr = try? fileManager.attributesOfItem(atPath: fileURL.path),
                  let size = attr[.size] as? NSNumber else {
                return 0
            }
            bytes = size.uint64Value
        }
        return Int(bytes / UInt64(MemoryLayout<Int16>.size))
    }

    func drain(
        chunkSamples: Int,
        process: ([Int16]) -> Void,
        onProgress: ((Int) -> Void)? = nil,
        shouldContinue: (() -> Bool)? = nil,
        removeFileWhenDone: Bool = true
    ) {
        guard chunkSamples > 0 else { return }
        guard fileManager.fileExists(atPath: fileURL.path) else { return }

        fileHandle?.closeFile()
        fileHandle = nil

        guard let reader = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer {
            try? reader.close()
            if removeFileWhenDone {
                try? fileManager.removeItem(at: fileURL)
            }
        }

        let chunkBytes = chunkSamples * MemoryLayout<Int16>.size
        var processedSamples = 0

        while true {
            if let shouldContinue = shouldContinue, !shouldContinue() {
                break
            }
            guard let chunk = try? reader.read(upToCount: chunkBytes), !chunk.isEmpty else {
                break
            }

            let usableBytes = (chunk.count / MemoryLayout<Int16>.size) * MemoryLayout<Int16>.size
            if usableBytes == 0 { break }

            var values = [Int16](repeating: 0, count: usableBytes / MemoryLayout<Int16>.size)
            _ = values.withUnsafeMutableBytes { dst in
                chunk.prefix(usableBytes).copyBytes(to: dst)
            }
            process(values)
            processedSamples += values.count
            onProgress?(processedSamples)

            if let shouldContinue = shouldContinue, !shouldContinue() {
                break
            }

            if usableBytes < chunkBytes {
                break
            }
        }
    }
}
