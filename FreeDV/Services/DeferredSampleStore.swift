import Foundation

/// Stores raw 8kHz Int16 samples to disk while app is in background.
/// Supports multiple capture batches so a new background session doesn't
/// corrupt an in-progress deferred decode of a previous batch.
final class DeferredSampleStore {
    private let fileManager = FileManager.default
    private var writeHandle: FileHandle?
    private var writeBatchIndex = 0

    private var docsDir: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func batchURL(_ index: Int) -> URL {
        docsDir.appendingPathComponent("deferred_samples_\(index).pcm")
    }

    // MARK: - Writing

    private func ensureWriter() -> FileHandle? {
        if writeHandle == nil {
            let url = batchURL(writeBatchIndex)
            if !fileManager.fileExists(atPath: url.path) {
                fileManager.createFile(atPath: url.path, contents: nil)
            }
            writeHandle = try? FileHandle(forWritingTo: url)
            writeHandle?.seekToEndOfFile()
        }
        return writeHandle
    }

    func appendRawInt16(_ samples: UnsafePointer<Int16>, count: Int) {
        guard count > 0 else { return }
        guard let handle = ensureWriter() else { return }
        let data = Data(bytes: samples, count: count * MemoryLayout<Int16>.size)
        try? handle.write(contentsOf: data)
    }

    /// Close the current writer and start a new batch file.
    /// Call this before enabling background capture when a previous batch
    /// is still being drained by a paused decode.
    func advanceBatch() {
        writeHandle?.closeFile()
        writeHandle = nil
        writeBatchIndex += 1
    }

    // MARK: - Reading

    /// Returns sorted list of batch indices that have files on disk.
    func pendingBatchIndices() -> [Int] {
        let files = (try? fileManager.contentsOfDirectory(atPath: docsDir.path)) ?? []
        return files.compactMap { name -> Int? in
            guard name.hasPrefix("deferred_samples_"), name.hasSuffix(".pcm") else { return nil }
            let s = String(name.dropFirst("deferred_samples_".count).dropLast(".pcm".count))
            return Int(s)
        }.sorted()
    }

    var hasPendingBatches: Bool {
        !pendingBatchIndices().isEmpty
    }

    /// Sample count of the most recently written batch file.
    func latestBatchSampleCount() -> Int {
        guard let latest = pendingBatchIndices().last else { return 0 }
        let url = batchURL(latest)
        if latest == writeBatchIndex {
            let bytes = writeHandle?.seekToEndOfFile() ?? 0
            if bytes > 0 {
                return Int(bytes / UInt64(MemoryLayout<Int16>.size))
            }
        }
        guard let attr = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attr[.size] as? NSNumber else {
            return 0
        }
        return Int(size.uint64Value / UInt64(MemoryLayout<Int16>.size))
    }

    /// Remove the most recently written batch file (e.g. too short to decode).
    func removeLatestBatch() {
        guard let latest = pendingBatchIndices().last else { return }
        removeBatch(at: latest)
    }

    /// Remove a specific batch file by index.
    func removeBatch(at index: Int) {
        if index == writeBatchIndex {
            writeHandle?.closeFile()
            writeHandle = nil
        }
        try? fileManager.removeItem(at: batchURL(index))
    }

    /// Sample count of the oldest pending batch file.
    func totalSampleCount() -> Int {
        guard let oldest = pendingBatchIndices().first else { return 0 }
        let url = batchURL(oldest)
        // Close writer if it's the same batch we're about to read
        if oldest == writeBatchIndex {
            let bytes = writeHandle?.seekToEndOfFile() ?? 0
            if bytes > 0 {
                return Int(bytes / UInt64(MemoryLayout<Int16>.size))
            }
        }
        guard let attr = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attr[.size] as? NSNumber else {
            return 0
        }
        return Int(size.uint64Value / UInt64(MemoryLayout<Int16>.size))
    }

    /// Drain the oldest pending batch. The batch file is removed when done.
    func drain(
        chunkSamples: Int,
        process: ([Int16]) -> Void,
        onProgress: ((Int) -> Void)? = nil,
        shouldContinue: (() -> Bool)? = nil
    ) {
        guard chunkSamples > 0 else { return }
        guard let oldest = pendingBatchIndices().first else { return }
        let url = batchURL(oldest)

        // Close writer if it's the same batch
        if oldest == writeBatchIndex {
            writeHandle?.closeFile()
            writeHandle = nil
        }

        guard let reader = try? FileHandle(forReadingFrom: url) else { return }
        defer {
            try? reader.close()
            try? fileManager.removeItem(at: url)
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

    func reset() {
        writeHandle?.closeFile()
        writeHandle = nil
        for index in pendingBatchIndices() {
            try? fileManager.removeItem(at: batchURL(index))
        }
        writeBatchIndex = 0
    }
}
