// P0-FFI-CONTRACT checks (docs/implementation/P0-closeout.md).
// Consumer side of the contract: independent expected values are computed here,
// never taken from the Rust producer (except C06/C07, which compare copies against the
// producer checksum after C01/C02 validated full-frame content). Writes JSON without local paths.
import Darwin
import Foundation
import Metal
import P0ContractCopy

// MARK: - Helpers

let clock = ContinuousClock()

func ms(_ d: Duration) -> Double {
    let c = d.components
    return Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
}

func pct(_ xs: [Double], _ p: Double) -> Double {
    guard !xs.isEmpty else { return -1 }
    let s = xs.sorted()
    let i = Int((p / 100 * Double(s.count - 1)).rounded())
    return s[min(max(i, 0), s.count - 1)]
}

func round3(_ x: Double) -> Double { (x * 1000).rounded() / 1000 }

func footprintMiB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
}

func sysctlString(_ name: String) -> String {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "unavailable" }
    var buf = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return "unavailable" }
    return String(cString: buf)
}

func checksum(_ bytes: [UInt8]) -> UInt64 {
    bytes.withUnsafeBytes { raw -> UInt64 in
        var sum: UInt64 = 0
        let words = raw.count / 8
        for i in 0..<words {
            sum &+= UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: i * 8, as: UInt64.self))
        }
        var i = words * 8
        while i < raw.count { sum &+= UInt64(raw[i]); i += 1 }
        return sum
    }
}

// Independent expectations (same literal formulas as the Rust doc comment, recomputed here).
func expectedGray(_ x: Int, _ y: Int) -> Float { Float(x) - 0.5 * Float(y) - 1024.0 }
func isPadding(_ x: Int, _ y: Int) -> Bool { (3 * x + y) % 11 == 0 }

/// Returns the number of mismatching elements (0 = exact).
func verifyGray(_ px: [UInt8], _ mask: [UInt8]?, width: Int, height: Int, padding: Bool) -> Int {
    guard px.count == width * height * 4 else { return -1 }
    if padding { guard let m = mask, m.count == width * height else { return -2 } } else if mask != nil { return -3 }
    var bad = 0
    px.withUnsafeBytes { raw in
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let bits = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self))
                let value = Float(bitPattern: bits)
                let invalid = padding && isPadding(x, y)
                let want: Float = invalid ? 0.0 : expectedGray(x, y)
                if bits != want.bitPattern || !value.isFinite { bad += 1 }
                if let m = mask, m[i] != (invalid ? 0 : 1) { bad += 1 }
            }
        }
    }
    return bad
}

func verifyRGBA(_ px: [UInt8], width: Int, height: Int) -> Int {
    guard px.count == width * height * 4 else { return -1 }
    var bad = 0
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            if px[i] != UInt8(x & 0xFF) || px[i + 1] != UInt8(y & 0xFF) || px[i + 2] != UInt8((x ^ y) & 0xFF) || px[i + 3] != 255 {
                bad += 1
            }
        }
    }
    return bad
}

func statusOf(_ body: () throws -> Void) -> String {
    do { try body(); return "ok" } catch let e as CopyFailure { return "copy-status-\(e.status)" } catch { return "\(error)" }
}

// MARK: - Report

/// Reference box shared with worker threads (guarded by `lock` or by a semaphore hand-off).
final class SharedBox: @unchecked Sendable {
    let lock = NSLock()
    var sums: [UInt64] = []
    var mismatches = 0
    var statuses: [(Int32, UInt64)] = []
}

var checks: [[String: Any]] = []
var failures = 0
func record(_ id: String, _ status: String, _ title: String, _ detail: [String: Any] = [:]) {
    // Details are nested so they can never overwrite id/status/title.
    var entry: [String: Any] = ["id": id, "status": status, "title": title]
    if !detail.isEmpty { entry["detail"] = detail }
    checks.append(entry)
    if status == "fail" { failures += 1 }
    print("[\(status.uppercased())] \(id) \(title) \(detail.isEmpty ? "" : String(describing: detail))")
}
func passFail(_ ok: Bool) -> String { ok ? "pass" : "fail" }

// MARK: - C01..C03 content, stride, domain

do {
    let f = try PreparedFrame.prepare(width: 512, height: 512, format: .grayF32Le, maskMode: .allValid)
    let px = try f.copyPixels()
    let mask = try f.copyMask()
    let bad = verifyGray(px, mask, width: 512, height: 512, padding: false)
    let meta = f.rowStrideBytes() == 2048 && f.byteLen() == 1_048_576 && f.maskLen() == 0
        && f.valueDomain() == .modalityApplied && f.pixelFormat() == .grayF32Le && f.payloadRevision() == 1
    record("C01", passFail(bad == 0 && meta && checksum(px) == f.checksum()), "GrayF32LE 512x512 all-valid: every value bit-exact vs Swift formula, stride/len/domain",
           ["mismatches": bad, "metadata_ok": meta])
} catch { record("C01", "fail", "GrayF32LE all-valid", ["error": "\(error)"]) }

do {
    let f = try PreparedFrame.prepare(width: 511, height: 257, format: .grayF32Le, maskMode: .padding)
    let px = try f.copyPixels()
    let mask = try f.copyMask()
    let bad = verifyGray(px, mask, width: 511, height: 257, padding: true)
    let invalid = mask?.filter { $0 == 0 }.count ?? -1
    var expectedInvalid = 0
    for y in 0..<257 { for x in 0..<511 where isPadding(x, y) { expectedInvalid += 1 } }
    record("C02", passFail(bad == 0 && invalid == expectedInvalid && f.rowStrideBytes() == 2044),
           "GrayF32LE 511x257 with valid_mask: masked pixels are finite +0.0, mask 0/1 exact",
           ["mismatches": bad, "invalid_pixels": invalid, "expected_invalid": expectedInvalid])
} catch { record("C02", "fail", "GrayF32LE masked", ["error": "\(error)"]) }

do {
    let f = try PreparedFrame.prepare(width: 300, height: 200, format: .rgba8, maskMode: .allValid)
    let px = try f.copyPixels()
    let bad = verifyRGBA(px, width: 300, height: 200)
    var probe = [UInt8](repeating: 0x5A, count: 16)
    let maskStatus = probe.withUnsafeMutableBufferPointer { p0_contract_copy_mask(f.copyTicket(), $0.baseAddress, 16) }
    let ok = bad == 0 && f.valueDomain() == .displayColor && f.maskLen() == 0 && maskStatus == 5 && probe.allSatisfy { $0 == 0x5A }
    withExtendedLifetime(f) {}
    record("C03", passFail(ok), "RGBA8 300x200: R,G,B,A order exact, DisplayColor, mask copy -> NO_MASK without write",
           ["mismatches": bad, "mask_status": Int(maskStatus)])
} catch { record("C03", "fail", "RGBA8", ["error": "\(error)"]) }

// MARK: - C04 errors never write

do {
    let f = try PreparedFrame.prepare(width: 64, height: 64, format: .grayF32Le, maskMode: .padding)
    let t = f.copyTicket()
    let n = Int(f.byteLen())
    var results: [String: Int] = [:]
    var untouched = true
    for (name, len) in [("short", n - 1), ("long", n + 1), ("zero", 0)] {
        var buf = [UInt8](repeating: 0x5A, count: n + 1)
        let s = buf.withUnsafeMutableBufferPointer { p0_contract_copy_pixels(t, $0.baseAddress, len) }
        results[name] = Int(s)
        untouched = untouched && buf.allSatisfy { $0 == 0x5A }
    }
    results["null"] = Int(p0_contract_copy_pixels(t, nil, n))
    var buf = [UInt8](repeating: 0x5A, count: n)
    results["ticket0"] = Int(buf.withUnsafeMutableBufferPointer { p0_contract_copy_pixels(0, $0.baseAddress, n) })
    results["ticket_unknown"] = Int(buf.withUnsafeMutableBufferPointer { p0_contract_copy_pixels(t &+ 1_000_000_000, $0.baseAddress, n) })
    results["mask_short"] = Int(buf.withUnsafeMutableBufferPointer { p0_contract_copy_mask(t, $0.baseAddress, 64 * 64 - 1) })
    untouched = untouched && buf.allSatisfy { $0 == 0x5A }
    var wrong = [UInt8](repeating: 0, count: n - 4)
    let wrapper = statusOf { try f.copyPixels(into: &wrong) }
    withExtendedLifetime(f) {}
    let zero = statusOf { _ = try PreparedFrame.prepare(width: 0, height: 4, format: .rgba8, maskMode: .allValid) }
    let huge = statusOf { _ = try PreparedFrame.prepare(width: 70_000, height: 70_000, format: .rgba8, maskMode: .allValid) } // > 512 MiB limit
    let overflow = statusOf { _ = try PreparedFrame.prepare(width: UInt32.max, height: UInt32.max, format: .rgba8, maskMode: .allValid) } // u64 multiply overflow
    let rgbaMask = statusOf { _ = try PreparedFrame.prepare(width: 4, height: 4, format: .rgba8, maskMode: .padding) }
    let ok = results == ["short": 3, "long": 3, "zero": 3, "null": 2, "ticket0": 1, "ticket_unknown": 1, "mask_short": 3]
        && untouched && wrapper == "copy-status-3"
        && zero.contains("InvalidArgument") && huge.contains("ResourceLimit") && overflow.contains("ResourceLimit") && rgbaMask.contains("InvalidArgument")
    record("C04", passFail(ok), "Errors: exact-length/null/unknown ticket statuses, destination unchanged, invalid prepare rejected",
           ["statuses": results, "destination_untouched": untouched, "wrapper_wrong_length": wrapper,
            "prepare_zero": zero.contains("InvalidArgument"), "prepare_over_limit": huge.contains("ResourceLimit"), "prepare_size_overflow": overflow.contains("ResourceLimit"), "prepare_rgba_mask": rgbaMask.contains("InvalidArgument")])
} catch { record("C04", "fail", "errors", ["error": "\(error)"]) }

// MARK: - C05 lifetime: eviction/close vs owners

do {
    let session = ContractSession()
    var n = 0
    var ticket: UInt64 = 0
    var afterEvict = "", afterClose = "", prepareAfterClose = "", afterRelease: Int32 = -1
    var evicted = false
    do {
        let f = try session.prepare(key: "a", width: 128, height: 128, format: .grayF32Le, maskMode: .allValid)
        ticket = f.copyTicket()
        n = Int(f.byteLen())
        evicted = session.evict(key: "a") && session.cachedCount() == 0
        afterEvict = statusOf { let px = try f.copyPixels(); if verifyGray(px, nil, width: 128, height: 128, padding: false) != 0 { throw CopyFailure(status: -9) } }
        session.close()
        afterClose = statusOf { let px = try f.copyPixels(); if verifyGray(px, nil, width: 128, height: 128, padding: false) != 0 { throw CopyFailure(status: -9) } }
        prepareAfterClose = statusOf { _ = try session.prepare(key: "b", width: 8, height: 8, format: .rgba8, maskMode: .allValid) }
    }
    // The only owner (f) is out of scope now.
    var buf = [UInt8](repeating: 0x5A, count: n)
    afterRelease = buf.withUnsafeMutableBufferPointer { p0_contract_copy_pixels(ticket, $0.baseAddress, n) }

    // Cache-only owner keeps the ticket valid until eviction.
    let s2 = ContractSession()
    var t2: UInt64 = 0
    var n2 = 0
    do {
        let g = try s2.prepare(key: "c", width: 32, height: 32, format: .rgba8, maskMode: .allValid)
        t2 = g.copyTicket()
        n2 = Int(g.byteLen())
    }
    var buf2 = [UInt8](repeating: 0, count: n2)
    let cacheOnly = buf2.withUnsafeMutableBufferPointer { p0_contract_copy_pixels(t2, $0.baseAddress, n2) }
    let cacheOnlyContent = verifyRGBA(buf2, width: 32, height: 32)
    _ = s2.evict(key: "c")
    let afterCacheEvict = buf2.withUnsafeMutableBufferPointer { p0_contract_copy_pixels(t2, $0.baseAddress, n2) }
    let ok = evicted && afterEvict == "ok" && afterClose == "ok" && prepareAfterClose.contains("SessionClosed") && afterRelease == 1
        && buf.allSatisfy { $0 == 0x5A } && cacheOnly == 0 && cacheOnlyContent == 0 && afterCacheEvict == 1 && t2 != ticket
    record("C05", passFail(ok), "Lifetime: payload valid after eviction/close while owned; SessionClosed for new work; ticket expires with last owner",
           ["evicted_and_cache_empty": evicted, "after_evict": afterEvict, "after_close": afterClose, "prepare_after_close_session_closed": prepareAfterClose.contains("SessionClosed"),
            "after_last_release_status": Int(afterRelease), "cache_only_owner_status": Int(cacheOnly), "after_cache_evict_status": Int(afterCacheEvict)])
} catch { record("C05", "fail", "lifetime", ["error": "\(error)"]) }

// MARK: - C06 concurrent copies of one frame

do {
    let f = try PreparedFrame.prepare(width: 1024, height: 1024, format: .grayF32Le, maskMode: .padding)
    let expected = f.checksum()
    let box = SharedBox()
    DispatchQueue.concurrentPerform(iterations: 8) { _ in
        do {
            let px = try f.copyPixels()
            let mask = try f.copyMask()
            let bad = verifyGray(px, mask, width: 1024, height: 1024, padding: true)
            box.lock.lock(); box.sums.append(checksum(px)); box.mismatches += bad; box.lock.unlock()
        } catch {
            box.lock.lock(); box.mismatches += 1_000_000; box.lock.unlock()
        }
    }
    withExtendedLifetime(f) {}
    record("C06", passFail(box.sums.count == 8 && box.sums.allSatisfy { $0 == expected } && box.mismatches == 0),
           "8 concurrent copies of one ticket into separate Swift buffers", ["copies": box.sums.count, "mismatches": box.mismatches])
} catch { record("C06", "fail", "concurrency", ["error": "\(error)"]) }

// MARK: - C07 copy vs release race (raw ticket, owner released on another thread)

do {
    var okCopies = 0, expired = 0, revived = 0, corrupt = 0, other = 0
    for _ in 0..<200 {
        var frame: PreparedFrame? = try PreparedFrame.prepare(width: 256, height: 256, format: .grayF32Le, maskMode: .allValid)
        let t = frame!.copyTicket()
        let n = Int(frame!.byteLen())
        let expected = frame!.checksum()
        let done = DispatchSemaphore(value: 0)
        let box = SharedBox()
        Thread.detachNewThread {
            var buf = [UInt8](repeating: 0, count: n)
            for _ in 0..<40 {
                // Refill with a sentinel so a partial copy cannot hide behind a previous good copy.
                buf.withUnsafeMutableBufferPointer { $0.update(repeating: 0xA5) }
                let s = buf.withUnsafeMutableBufferPointer { p0_contract_copy_pixels(t, $0.baseAddress, n) }
                box.statuses.append((s, s == 0 ? checksum(buf) : 0))
            }
            done.signal()
        }
        usleep(UInt32.random(in: 0...300))
        frame = nil
        done.wait()
        var sawExpired = false
        for (s, sum) in box.statuses {
            switch s {
            case 0:
                if sawExpired { revived += 1 }
                if sum == expected { okCopies += 1 } else { corrupt += 1 }
            case 1: expired += 1; sawExpired = true
            default: other += 1
            }
        }
        if !sawExpired {
            // Copier finished before release; the ticket must be expired now.
            var b = [UInt8](repeating: 0, count: n)
            if b.withUnsafeMutableBufferPointer({ p0_contract_copy_pixels(t, $0.baseAddress, n) }) != 1 { other += 1 }
        }
    }
    record("C07", passFail(corrupt == 0 && revived == 0 && other == 0 && expired > 0 && okCopies > 0),
           "Copy racing the last release: each copy is complete or INVALID_TICKET, never partial/revived",
           ["rounds": 200, "ok_copies": okCopies, "expired": expired, "corrupt": corrupt, "revived": revived, "other": other])
} catch { record("C07", "fail", "race", ["error": "\(error)"]) }

// MARK: - C08 panic containment

let panicStatus = p0_contract_selftest_panic()
record("C08", passFail(panicStatus == 4), "Panic inside the C bridge returns PANIC status; process continues", ["returned_status": Int(panicStatus)])

// MARK: - C09 Rust allocations during copy

do {
    let f = try PreparedFrame.prepare(width: 2048, height: 2048, format: .grayF32Le, maskMode: .padding)
    let t = f.copyTicket()
    let n = Int(f.byteLen())
    var buf = [UInt8](repeating: 0, count: n)
    var mask = [UInt8](repeating: 0, count: Int(f.maskLen()))
    let c0 = allocStats(); let c1 = allocStats()
    let probeCost = c1.allocs - c0.allocs
    let a = allocStats()
    var statuses = Set<Int32>()
    for _ in 0..<20 {
        statuses.insert(buf.withUnsafeMutableBufferPointer { p0_contract_copy_pixels(t, $0.baseAddress, n) })
        statuses.insert(mask.withUnsafeMutableBufferPointer { p0_contract_copy_mask(t, $0.baseAddress, $0.count) })
    }
    let b = allocStats()
    withExtendedLifetime(f) {}
    let copyAllocs = Int64(b.allocs - a.allocs) - Int64(probeCost)
    record("C09", passFail(statuses == [0] && copyAllocs == 0 && b.liveBytes == a.liveBytes),
           "40 copies (16 MiB pixels + 4 MiB mask) allocate nothing in Rust",
           ["rust_allocs_during_copies": copyAllocs, "rust_live_delta_bytes": Int64(b.liveBytes) - Int64(a.liveBytes)])
} catch { record("C09", "fail", "allocations", ["error": "\(error)"]) }

// MARK: - C10 footprint with 64 MiB frames

do {
    let base = footprintMiB()
    let rustBase = allocStats().liveBytes
    var reuseSamples: [Double] = []
    var freshSamples: [Double] = []
    var verified = true
    do {
        let f = try PreparedFrame.prepare(width: 4096, height: 4096, format: .grayF32Le, maskMode: .padding)
        var buf = [UInt8](repeating: 0, count: Int(f.byteLen()))
        for i in 0..<20 {
            try f.copyPixels(into: &buf)
            if i == 0 {
                let mask = try f.copyMask()
                verified = verified && verifyGray(buf, mask, width: 4096, height: 4096, padding: true) == 0
            }
            reuseSamples.append(footprintMiB())
        }
        for _ in 0..<20 {
            try autoreleasepool {
                let px = try f.copyPixels()
                if px.count != 64 << 20 { verified = false }
            }
            freshSamples.append(footprintMiB())
        }
    }
    let afterRelease = footprintMiB()
    let rustAfter = allocStats().liveBytes
    let reuseGrowth = reuseSamples.last! - reuseSamples.first!
    let freshGrowth = freshSamples.last! - freshSamples.first!
    record("C10", passFail(verified && reuseGrowth < 8 && freshGrowth < 8 && rustAfter <= rustBase + 1_048_576),
           "64 MiB GrayF32 (+16 MiB mask): footprint flat over 20 reused and 20 fresh-buffer copies; Rust bytes returned after release",
           ["base_MiB": round3(base), "reuse_first_MiB": round3(reuseSamples.first!), "reuse_last_MiB": round3(reuseSamples.last!),
            "fresh_first_MiB": round3(freshSamples.first!), "fresh_last_MiB": round3(freshSamples.last!),
            "after_release_MiB": round3(afterRelease), "rust_live_delta_bytes": Int64(rustAfter) - Int64(rustBase), "verified": verified])
} catch { record("C10", "fail", "footprint", ["error": "\(error)"]) }

// MARK: - C11 copy timing (informational)

var timing: [[String: Any]] = []
do {
    for (label, side, reps) in [("1MiB", 512, 60), ("16MiB", 2048, 30), ("64MiB", 4096, 15)] {
        let f = try PreparedFrame.prepare(width: UInt32(side), height: UInt32(side), format: .grayF32Le, maskMode: .allValid)
        var buf = [UInt8](repeating: 0, count: Int(f.byteLen()))
        try f.copyPixels(into: &buf) // warm-up, page in destination
        var reuse: [Double] = [], fresh: [Double] = []
        for _ in 0..<reps {
            let t0 = clock.now
            try f.copyPixels(into: &buf)
            reuse.append(ms(clock.now - t0))
        }
        for _ in 0..<reps {
            let t0 = clock.now
            let px = try f.copyPixels()
            fresh.append(ms(clock.now - t0))
            withExtendedLifetime(px) {}
        }
        timing.append(["size": label, "reps": reps, "reuse_p50_ms": round3(pct(reuse, 50)), "reuse_p95_ms": round3(pct(reuse, 95)),
                       "fresh_alloc_p50_ms": round3(pct(fresh, 50)), "fresh_alloc_p95_ms": round3(pct(fresh, 95))])
    }
    record("C11", "info", "Copy timing into Swift-owned buffers (not an app display latency)", ["timing": timing])
} catch { record("C11", "fail", "timing", ["error": "\(error)"]) }

// MARK: - C12 Metal shared buffer destination

if let device = MTLCreateSystemDefaultDevice() {
    do {
        let f = try PreparedFrame.prepare(width: 2048, height: 2048, format: .grayF32Le, maskMode: .allValid)
        guard let mtl = device.makeBuffer(length: Int(f.byteLen()), options: .storageModeShared) else { throw CopyFailure(status: -8) }
        try f.copyPixels(into: mtl)
        let view = [UInt8](UnsafeBufferPointer(start: mtl.contents().assumingMemoryBound(to: UInt8.self), count: mtl.length))
        let bad = verifyGray(view, nil, width: 2048, height: 2048, padding: false)
        let wrongLen = statusOf {
            guard let small = device.makeBuffer(length: Int(f.byteLen()) - 4, options: .storageModeShared) else { throw CopyFailure(status: -8) }
            try f.copyPixels(into: small)
        }
        record("C12", passFail(bad == 0 && wrongLen == "copy-status-3"),
               "Copy into MTLBuffer (shared storage) matches; wrong-size Metal buffer rejected (CPU copy only, no GPU pass)",
               ["device": device.name, "mismatches": bad, "wrong_length": wrongLen])
    } catch { record("C12", "fail", "Metal destination", ["error": "\(error)"]) }
} else {
    record("C12", "not-run", "Metal destination", ["reason": "MTLCreateSystemDefaultDevice returned nil"])
}

// MARK: - Output

let env: [String: Any] = [
    "core_info": coreInfo(),
    "os": ProcessInfo.processInfo.operatingSystemVersionString,
    "hw_model": sysctlString("hw.model"),
    "cpu": sysctlString("machdep.cpu.brand_string"),
    "memory_GiB": Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824,
]
let summary: [String: Any] = [
    "pass": checks.filter { ($0["status"] as? String) == "pass" }.count,
    "fail": failures,
    "not_run": checks.filter { ($0["status"] as? String) == "not-run" }.count,
    "info": checks.filter { ($0["status"] as? String) == "info" }.count,
]
let reportObj: [String: Any] = [
    "schema_version": 1, "task_id": "P0-FFI-CONTRACT", "timestamp": ISO8601DateFormatter().string(from: Date()),
    "environment": env, "checks": checks, "summary": summary,
    "scope": "P0 contract experiment with synthetic frames; not decode_frame, not GPU rendering, not product T-11..T-13 acceptance",
]
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "contract-results.json"
do {
    let data = try JSONSerialization.data(withJSONObject: reportObj, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: URL(fileURLWithPath: outPath))
} catch {
    print("could not write report: \(error)")
    exit(2)
}
print("summary: \(summary)")
exit(failures == 0 ? 0 : 1)
