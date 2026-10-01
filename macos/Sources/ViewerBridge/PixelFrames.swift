import Darwin
import Foundation
internal import ViewerBindings
internal import ViewerPixelCopy

/// Errors exposed by the safe pixel wrapper; no generated type crosses its API.
public enum ViewerPixelError: Error, Sendable, Equatable {
    case resourceLimit(reason: String)
    case invalidArgument(reason: String)
    case unsupported(reason: String)
    case decodeFailed(reason: String)
    case sessionClosed
    case busy
    case invalidContract(reason: String)
    case copyFailed(status: Int32)
}

public enum PixelBufferFormat: String, Sendable {
    case grayF32LE
    case rgba8
}

public enum PixelValueDomain: String, Sendable {
    case modalityApplied
    case displayColor
}

/// Immutable metadata supplied by Rust. Swift does not interpret DICOM tags.
public struct PixelFrameMetadata: Sendable {
    public let width: UInt32
    public let height: UInt32
    public let rowStrideBytes: UInt64
    public let byteLen: UInt64
    public let maskLen: UInt64
    public let pixelFormat: PixelBufferFormat
    public let valueDomain: PixelValueDomain
    public let contractRevision: UInt32
    public let payloadRevision: UInt64

    fileprivate init(raw: PixelBufferInfo) {
        width = raw.width
        height = raw.height
        rowStrideBytes = raw.rowStrideBytes
        byteLen = raw.byteLen
        maskLen = raw.maskLen
        switch raw.pixelFormat {
        case .grayF32Le: pixelFormat = .grayF32LE
        case .rgba8: pixelFormat = .rgba8
        }
        switch raw.valueDomain {
        case .modalityApplied: valueDomain = .modalityApplied
        case .displayColor: valueDomain = .displayColor
        }
        contractRevision = raw.contractRevision
        payloadRevision = raw.payloadRevision
    }

    /// Validate every size and domain before reserving or allocating Swift bytes.
    fileprivate func validatedSizes() throws -> (pixels: Int, mask: Int, total: UInt64) {
        guard contractRevision == 1, payloadRevision == 1 else {
            throw ViewerPixelError.invalidContract(reason: "unexpected pixel revision")
        }
        guard width > 0, height > 0 else {
            throw ViewerPixelError.invalidContract(reason: "empty pixel dimensions")
        }
        let (stride, strideOverflow) = UInt64(width).multipliedReportingOverflow(by: 4)
        let (length, lengthOverflow) = stride.multipliedReportingOverflow(by: UInt64(height))
        let (pixelCount, countOverflow) = UInt64(width).multipliedReportingOverflow(by: UInt64(height))
        guard !strideOverflow, !lengthOverflow, !countOverflow,
              rowStrideBytes == stride, byteLen == length else {
            throw ViewerPixelError.invalidContract(reason: "invalid pixel stride or length")
        }
        switch pixelFormat {
        case .grayF32LE:
            guard valueDomain == .modalityApplied, maskLen == 0 || maskLen == pixelCount else {
                throw ViewerPixelError.invalidContract(reason: "invalid gray domain or mask length")
            }
        case .rgba8:
            guard valueDomain == .displayColor, maskLen == 0 else {
                throw ViewerPixelError.invalidContract(reason: "invalid color domain or mask length")
            }
        }
        let (total, totalOverflow) = byteLen.addingReportingOverflow(maskLen)
        guard !totalOverflow, let pixelBytes = Int(exactly: byteLen),
              let maskBytes = Int(exactly: maskLen), Int(exactly: total) != nil else {
            throw ViewerPixelError.invalidContract(reason: "pixel size cannot be represented")
        }
        return (pixelBytes, maskBytes, total)
    }
}

public struct ViewerPixelMemorySnapshot: Sendable {
    public let liveBytes: UInt64
    public let peakBytes: UInt64
    public let maxLiveBytes: UInt64
    public let maxFrameBytes: UInt64
    public let cachedFrames: UInt32
    public let activePreparations: UInt32
}

/// A Rust session. Retained frames remain valid after eviction and close.
/// File preparation has no cancellation/generation contract yet.
public final class ViewerPixelSession: @unchecked Sendable {
    private let raw: PixelSession

    public init(
        maxLiveBytes: UInt64 = 512 * 1024 * 1024,
        maxFrameBytes: UInt64 = 128 * 1024 * 1024
    ) throws {
        do {
            raw = try PixelSession(maxLiveBytes: maxLiveBytes, maxFrameBytes: maxFrameBytes)
        } catch {
            throw translatedPixelError(error)
        }
    }

    /// Forward the original path and zero-based frame index to Rust off the UI executor.
    public func prepareNativeFrame(path: String, frameIndex: UInt32 = 0) async throws -> PreparedPixelFrame {
        let raw = raw
        return try await Task.detached {
            try requireBackgroundThread()
            do {
                let handle = try raw.prepareNativeFrame(path: path, frameIndex: frameIndex)
                let frame = try PreparedPixelFrame(raw: handle)
                _ = try frame.info.validatedSizes()
                return frame
            } catch {
                throw translatedPixelError(error)
            }
        }.value
    }

    /// Eviction can release large payloads, so run it away from MainActor too.
    public func evictAll() async -> UInt32 {
        let raw = raw
        return await Task.detached { raw.evictAll() }.value
    }

    public func close() async {
        let raw = raw
        await Task.detached { raw.close() }.value
    }

    /// A short lock-protected metadata read; this does not access source files.
    public func memorySnapshot() -> ViewerPixelMemorySnapshot {
        let value = raw.memorySnapshot()
        return ViewerPixelMemorySnapshot(
            liveBytes: value.liveBytes, peakBytes: value.peakBytes,
            maxLiveBytes: value.maxLiveBytes, maxFrameBytes: value.maxFrameBytes,
            cachedFrames: value.cachedFrames, activePreparations: value.activePreparations
        )
    }
}

/// An immutable Rust payload owner. Its ticket and generated handle stay private.
public final class PreparedPixelFrame: @unchecked Sendable {
    public let info: PixelFrameMetadata
    public let display: FrameDisplayInfo
    private let raw: PixelHandle

    fileprivate init(raw: PixelHandle) throws {
        self.raw = raw
        info = PixelFrameMetadata(raw: raw.info())
        display = FrameDisplayInfo(try raw.displayInfo())
        try display.validate(format: info.pixelFormat)
    }

    /// Bounded CPU oracle for small display checks, never the app's display path.
    public func referenceRGBA(window: VoiWindow? = nil, userInvert: Bool = false) async throws -> [UInt8] {
        let raw = raw
        return try await Task.detached {
            try requireBackgroundThread()
            do { return Array(try raw.referenceRgba(window: window?.raw, userInvert: userInvert)) }
            catch { throw translatedPixelError(error) }
        }.value
    }

    /// Make one separately charged, immutable Swift copy. No caller-owned writable
    /// destination or GPU buffer can be passed into this operation.
    public func copy(using budget: PixelCopyBudget) async throws -> OwnedPixelFrame {
        let raw = raw
        let info = info
        let display = display
        return try await Task.detached {
            try requireBackgroundThread()
            let sizes = try info.validatedSizes()
            let lease = try budget.reserve(bytes: sizes.total)
            guard let pixels = malloc(sizes.pixels) else {
                throw ViewerPixelError.resourceLimit(reason: "Swift pixel allocation failed")
            }
            var mask: UnsafeMutableRawPointer?
            var transferred = false
            defer {
                withExtendedLifetime(lease) {
                    if !transferred {
                        free(pixels)
                        free(mask)
                    }
                }
            }
            if sizes.mask > 0 {
                guard let allocation = malloc(sizes.mask) else {
                    throw ViewerPixelError.resourceLimit(reason: "Swift mask allocation failed")
                }
                mask = allocation
            }
            let pixelPointer = pixels.bindMemory(to: UInt8.self, capacity: sizes.pixels)
            let maskPointer = mask?.bindMemory(to: UInt8.self, capacity: sizes.mask)
            try withExtendedLifetime(raw) {
                let ticket = raw.copyTicket()
                let pixelStatus = viewer_copy_pixels(ticket, pixelPointer, sizes.pixels)
                guard pixelStatus == 0 else { throw ViewerPixelError.copyFailed(status: pixelStatus) }
                if sizes.mask > 0 {
                    let maskStatus = viewer_copy_mask(ticket, maskPointer, sizes.mask)
                    guard maskStatus == 0 else { throw ViewerPixelError.copyFailed(status: maskStatus) }
                }
            }
            let result = OwnedPixelFrame(
                info: info, display: display, pixels: pixels, mask: mask,
                pixelBytes: sizes.pixels, maskBytes: sizes.mask, lease: lease
            )
            transferred = true
            return result
        }.value
    }
}

/// Swift-owned bytes, frozen after the exact C copy. Aliases share one reservation.
/// Storage is inaccessible except through synchronous read-only borrowed closures.
public final class OwnedPixelFrame: @unchecked Sendable {
    public let info: PixelFrameMetadata
    public let display: FrameDisplayInfo
    private let pixels: UnsafeMutableRawPointer
    private let mask: UnsafeMutableRawPointer?
    private let pixelBytes: Int
    private let maskBytes: Int
    private let lease: PixelCopyLease

    fileprivate init(
        info: PixelFrameMetadata, display: FrameDisplayInfo, pixels: UnsafeMutableRawPointer,
        mask: UnsafeMutableRawPointer?, pixelBytes: Int, maskBytes: Int,
        lease: PixelCopyLease
    ) {
        self.info = info
        self.display = display
        self.pixels = pixels
        self.mask = mask
        self.pixelBytes = pixelBytes
        self.maskBytes = maskBytes
        self.lease = lease
    }

    deinit {
        withExtendedLifetime(lease) {
            free(pixels)
            free(mask)
        }
        // The lease property is released once after these allocations are freed.
    }

    /// The pointer is borrowed only for this closure. It must not escape, be cast
    /// to mutable storage, or be used by asynchronous work after the closure ends.
    /// Copies explicitly made by a caller need that caller's separate accounting.
    public func withUnsafePixelBytes<Result>(
        _ body: (UnsafeRawBufferPointer) throws -> Result
    ) rethrows -> Result {
        try withExtendedLifetime(self) {
            try body(UnsafeRawBufferPointer(start: pixels, count: pixelBytes))
        }
    }

    /// Nil means no validity mask. The same borrowed-pointer obligations apply.
    public func withUnsafeMaskBytes<Result>(
        _ body: (UnsafeRawBufferPointer?) throws -> Result
    ) rethrows -> Result {
        try withExtendedLifetime(self) {
            let bytes = mask.map { UnsafeRawBufferPointer(start: $0, count: maskBytes) }
            return try body(bytes)
        }
    }
}

public struct PixelCopyBudgetSnapshot: Sendable {
    public let liveBytes: UInt64
    public let peakBytes: UInt64
    public let maxLiveBytes: UInt64
    public let liveCopies: UInt64
}

/// Charges Swift destination pixels plus mask, independently of Rust's payload
/// budget. NSLock protects all mutable counters; immutable copies are Sendable.
public final class PixelCopyBudget: @unchecked Sendable {
    private let lock = NSLock()
    private let maxLiveBytes: UInt64
    private var liveBytes: UInt64 = 0
    private var peakBytes: UInt64 = 0
    private var liveCopies: UInt64 = 0

    public init(maxLiveBytes: UInt64 = 512 * 1024 * 1024) {
        self.maxLiveBytes = maxLiveBytes
    }

    public func snapshot() -> PixelCopyBudgetSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return PixelCopyBudgetSnapshot(
            liveBytes: liveBytes, peakBytes: peakBytes,
            maxLiveBytes: maxLiveBytes, liveCopies: liveCopies
        )
    }

    fileprivate func reserve(bytes: UInt64) throws -> PixelCopyLease {
        lock.lock()
        defer { lock.unlock() }
        let (next, overflow) = liveBytes.addingReportingOverflow(bytes)
        let (nextCount, countOverflow) = liveCopies.addingReportingOverflow(1)
        guard bytes > 0, !overflow, !countOverflow, next <= maxLiveBytes else {
            throw ViewerPixelError.resourceLimit(reason: "Swift copy budget exceeded")
        }
        liveBytes = next
        liveCopies = nextCount
        peakBytes = max(peakBytes, next)
        return PixelCopyLease(budget: self, bytes: bytes)
    }

    fileprivate func release(bytes: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        precondition(liveBytes >= bytes && liveCopies > 0, "unbalanced pixel lease")
        liveBytes -= bytes
        liveCopies -= 1
    }
}

fileprivate final class PixelCopyLease: @unchecked Sendable {
    private let budget: PixelCopyBudget
    private let bytes: UInt64

    init(budget: PixelCopyBudget, bytes: UInt64) {
        self.budget = budget
        self.bytes = bytes
    }

    deinit { budget.release(bytes: bytes) }
}

private func requireBackgroundThread() throws {
    guard !Thread.isMainThread else {
        throw ViewerPixelError.invalidContract(reason: "heavy pixel operation reached main thread")
    }
}

private func translatedPixelError(_ error: any Error) -> ViewerPixelError {
    if let error = error as? ViewerPixelError { return error }
    guard let error = error as? PixelError else {
        return .decodeFailed(reason: "unexpected core error")
    }
    switch error {
    case .ResourceLimit(let reason): return .resourceLimit(reason: reason)
    case .InvalidArgument(let reason): return .invalidArgument(reason: reason)
    case .Unsupported(let reason): return .unsupported(reason: reason)
    case .DecodeFailed(let reason): return .decodeFailed(reason: reason)
    case .SessionClosed: return .sessionClosed
    case .Busy: return .busy
    }
}
