import Foundation
import os

/// A fixed-size circular buffer designed for real-time audio use.
///
/// Uses `os_unfair_lock` (priority-inheriting) and a pre-allocated C buffer
/// so that neither the read nor write path performs heap allocation.
/// Safe to call `read(into:count:)` from the real-time audio render thread.
final class AudioRingBuffer {
    private let buffer: UnsafeMutablePointer<Float>
    private let capacity: Int
    private var writePos: Int = 0
    private var readPos: Int = 0
    private var count: Int = 0
    
    // Heap-allocated os_unfair_lock — address is stable (required by the API).
    private let lockPtr: UnsafeMutablePointer<os_unfair_lock_s>
    
    /// Create a ring buffer with the given capacity in samples.
    init(capacity: Int) {
        self.capacity = capacity
        buffer = .allocate(capacity: capacity)
        buffer.initialize(repeating: 0, count: capacity)
        lockPtr = .allocate(capacity: 1)
        lockPtr.initialize(to: os_unfair_lock())
    }
    
    deinit {
        buffer.deinitialize(count: capacity)
        buffer.deallocate()
        lockPtr.deinitialize(count: 1)
        lockPtr.deallocate()
    }
    
    /// Write `sampleCount` samples into the ring buffer (producer side).
    /// If the buffer is full, the oldest unread samples are overwritten.
    func write(_ samples: UnsafePointer<Float>, count sampleCount: Int) {
        os_unfair_lock_lock(lockPtr)
        let toWrite = min(sampleCount, capacity)
        for i in 0..<toWrite {
            buffer[writePos] = samples[i]
            writePos = (writePos + 1) % capacity
        }
        count = min(count + toWrite, capacity)
        // If we filled the buffer, advance readPos past overwritten data
        if count == capacity {
            readPos = writePos
        }
        os_unfair_lock_unlock(lockPtr)
    }
    
    /// Read up to `frameCount` samples into `output` (consumer side).
    /// Returns the number of samples actually read.  Unfilled portion
    /// of `output` is zeroed so the caller always gets `frameCount` usable samples.
    func read(into output: UnsafeMutablePointer<Float>, count frameCount: Int) -> Int {
        os_unfair_lock_lock(lockPtr)
        let toRead = min(frameCount, count)
        for i in 0..<toRead {
            output[i] = buffer[readPos]
            readPos = (readPos + 1) % capacity
        }
        count -= toRead
        os_unfair_lock_unlock(lockPtr)
        
        // Zero the rest so caller can use the full buffer
        if toRead < frameCount {
            memset(output.advanced(by: toRead), 0,
                   (frameCount - toRead) * MemoryLayout<Float>.size)
        }
        return toRead
    }
    
    /// Discard all unread data.
    func reset() {
        os_unfair_lock_lock(lockPtr)
        writePos = 0
        readPos = 0
        count = 0
        os_unfair_lock_unlock(lockPtr)
    }
}
