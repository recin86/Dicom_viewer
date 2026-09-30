// P0-FFI-CONTRACT safe Swift wrapper around the typed C copy bridge.
// This is the only place that touches p0_contract_copy_*; callers never see
// a pointer or a ticket. P0 experiment code, not product API.
import Foundation
import Metal
import P0ContractCopy

struct CopyFailure: Error, Equatable {
    let status: Int32
}

extension PreparedFrame {
    /// Allocates an exactly-sized Swift-owned buffer and copies the pixels once.
    func copyPixels() throws -> [UInt8] {
        try withExtendedLifetime(self) {
            let n = Int(byteLen())
            let ticket = copyTicket()
            var status: Int32 = -1
            let out = [UInt8](unsafeUninitializedCapacity: n) { buf, count in
                status = p0_contract_copy_pixels(ticket, buf.baseAddress, n)
                count = status == 0 ? n : 0
            }
            guard status == 0 else { throw CopyFailure(status: status) }
            return out
        }
    }

    /// Reuses a caller-owned buffer. `inout` gives exclusive access for the call.
    func copyPixels(into buffer: inout [UInt8]) throws {
        try withExtendedLifetime(self) {
            let n = Int(byteLen())
            guard buffer.count == n else { throw CopyFailure(status: 3) }
            let ticket = copyTicket()
            let status = buffer.withUnsafeMutableBufferPointer { p0_contract_copy_pixels(ticket, $0.baseAddress, n) }
            guard status == 0 else { throw CopyFailure(status: status) }
        }
    }

    /// nil when the frame declares no mask (all pixels valid).
    func copyMask() throws -> [UInt8]? {
        try withExtendedLifetime(self) {
            let n = Int(maskLen())
            guard n > 0 else { return nil }
            let ticket = copyTicket()
            var status: Int32 = -1
            let out = [UInt8](unsafeUninitializedCapacity: n) { buf, count in
                status = p0_contract_copy_mask(ticket, buf.baseAddress, n)
                count = status == 0 ? n : 0
            }
            guard status == 0 else { throw CopyFailure(status: status) }
            return out
        }
    }

    /// Copies into a CPU-visible Metal buffer (shared storage on Apple Silicon).
    /// Caller obligation: no GPU command buffer may be reading or writing this
    /// range until the call returns (P1 must order this against command completion).
    func copyPixels(into metal: MTLBuffer, offset: Int = 0) throws {
        try withExtendedLifetime(self) {
            let n = Int(byteLen())
            guard metal.storageMode == .shared, offset >= 0, offset <= metal.length, metal.length - offset == n else {
                throw CopyFailure(status: 3)
            }
            let dst = metal.contents().advanced(by: offset).assumingMemoryBound(to: UInt8.self)
            let status = p0_contract_copy_pixels(copyTicket(), dst, n)
            guard status == 0 else { throw CopyFailure(status: status) }
        }
    }
}
