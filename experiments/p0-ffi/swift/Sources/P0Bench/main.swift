// P0-FFI benchmark and behavior checks (docs/implementation/P0-tech-data.md).
// Throwaway experiment code; the generated p0ffi.swift sits next to this file.
import Foundation
import Darwin

// MARK: - Helpers

let clock = ContinuousClock()

func ms(_ d: Duration) -> Double {
    let c = d.components
    return Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
}

func pct(_ xs: [Double], _ p: Double) -> Double {
    guard !xs.isEmpty else { return .nan }
    let s = xs.sorted()
    let i = Int((p / 100 * Double(s.count - 1)).rounded())
    return s[min(max(i, 0), s.count - 1)]
}

func f2(_ x: Double) -> String { String(format: "%.2f", x) }

func swiftChecksum(_ d: Data) -> UInt64 {
    d.withUnsafeBytes { raw -> UInt64 in
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

func maxRssMiB() -> Double {
    var u = rusage()
    getrusage(RUSAGE_SELF, &u)
    return Double(u.ru_maxrss) / 1_048_576 // bytes on macOS
}

final class Report {
    var failures: [String] = []
    func check(_ ok: Bool, _ name: String, _ detail: String = "") {
        print("[\(ok ? "PASS" : "FAIL")] \(name)\(detail.isEmpty ? "" : " | \(detail)")")
        if !ok { failures.append(name) }
    }
    func info(_ name: String, _ detail: String) { print("[INFO] \(name) | \(detail)") }
    func section(_ title: String) { print("\n== \(title)") }
}
let report = Report()

// MARK: - Memory follow-up mode:  P0Bench mem <variant>
// Each variant runs in its own process (see run.sh mem) so results do not contaminate each other.

func peakFootprintMiB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? Double(info.ledger_phys_footprint_peak) / 1_048_576 : -1
}

func runMemVariant(_ variant: String) -> Int32 {
    let w: UInt32 = 4096, h: UInt32 = 4096          // 64 MiB GrayF32
    let frameMiB = Double(w) * Double(h) * 4 / 1_048_576
    let n = variant.hasPrefix("single") ? 1 : 20
    let base = footprintMiB()
    var sink = 0
    var afterEach: [Double] = []
    do {
        for _ in 0..<n {
            switch variant {
            case "rust-only":
                _ = try fillOnlyNs(width: w, height: h, format: .grayF32Le)
            case "record", "single":
                let f = try makeFrame(width: w, height: h, format: .grayF32Le); sink &+= f.bytes.count
            case "record-pool":
                try autoreleasepool {
                    let f = try makeFrame(width: w, height: h, format: .grayF32Le); sink &+= f.bytes.count
                }
            case "bytes", "single-bytes":
                let d = try makeFrameBytes(width: w, height: h, format: .grayF32Le); sink &+= d.count
            case "bytes-pool":
                try autoreleasepool {
                    let d = try makeFrameBytes(width: w, height: h, format: .grayF32Le); sink &+= d.count
                }
            default:
                print("unknown variant \(variant)"); return 2
            }
            afterEach.append(footprintMiB())
        }
    } catch {
        print("variant=\(variant) error=\(error)"); return 1
    }
    let afterLoop = footprintMiB()
    Thread.sleep(forTimeInterval: 1.0)
    let afterSleep = footprintMiB()
    let relieved = malloc_zone_pressure_relief(nil, 0)
    let afterRelief = footprintMiB()
    let peak = peakFootprintMiB()
    print("variant=\(variant) n=\(n) frameMiB=\(f2(frameMiB)) base=\(f2(base)) peak=\(f2(peak)) peakOverBase=\(f2(peak - base)) peakFrames=\(f2((peak - base) / frameMiB)) maxEach=\(f2(afterEach.max() ?? -1)) afterLoop=\(f2(afterLoop)) afterSleep1s=\(f2(afterSleep)) afterPressureRelief=\(f2(afterRelief)) relievedMiB=\(f2(Double(relieved) / 1_048_576)) retainedFrames=\(f2((afterRelief - base) / frameMiB)) sink=\(sink)")
    return 0
}

if CommandLine.arguments.count >= 3 && CommandLine.arguments[1] == "mem" {
    exit(runMemVariant(CommandLine.arguments[2]))
}

// MARK: - 0. Environment

print("P0-FFI report \(Date())")
print("core: \(coreInfo())")
print("footprint at start: \(f2(footprintMiB())) MiB")

// MARK: - 1. Errors and panic

report.section("1. Structured errors and panic")
do {
    _ = try makeFrame(width: 0, height: 10, format: .grayF32Le)
    report.check(false, "E1 zero width -> InvalidArgument", "no error thrown")
} catch let e as P0Error {
    report.check("\(e)".contains("InvalidArgument"), "E1 zero width -> InvalidArgument", "\(e)")
} catch {
    report.check(false, "E1 zero width -> InvalidArgument", "\(type(of: error)): \(error)")
}
do {
    _ = try makeFrame(width: 100_000, height: 100_000, format: .rgba8)
    report.check(false, "E2 huge frame -> ResourceLimit (before allocation)", "no error thrown")
} catch let e as P0Error {
    report.check("\(e)".contains("ResourceLimit"), "E2 huge frame -> ResourceLimit (before allocation)", "\(e)")
} catch {
    report.check(false, "E2 huge frame -> ResourceLimit (before allocation)", "\(type(of: error)): \(error)")
}
do {
    try failWith(kind: 3)
    report.check(false, "E3 failWith(3) -> Cancelled", "no error thrown")
} catch let e as P0Error {
    report.check(e == .Cancelled, "E3 failWith(3) -> Cancelled", "\(e)")
} catch {
    report.check(false, "E3 failWith(3) -> Cancelled", "\(type(of: error)): \(error)")
}
do {
    _ = try panicInResult()
    report.check(false, "E4 Rust panic -> thrown Swift error, no crash", "no error thrown")
} catch let e as P0Error {
    report.check(false, "E4 Rust panic -> thrown Swift error, no crash", "unexpected P0Error \(e)")
} catch {
    report.check(true, "E4 Rust panic -> thrown Swift error, no crash", "\(type(of: error)): \(error)")
}
report.check(!coreInfo().isEmpty, "E5 library still usable after panic")

// MARK: - 2. Rust -> Swift frame transfer

report.section("2. Rust -> Swift owned frame (Vec<u8> in record -> Data), 3 warmup + 30 runs, release")
struct BenchCase { let label: String; let w: UInt32; let h: UInt32; let fmt: PixelFormat }
let cases = [
    BenchCase(label: "512x512 GrayF32 (1 MiB)", w: 512, h: 512, fmt: .grayF32Le),
    BenchCase(label: "2048x2048 RGBA8 (16 MiB)", w: 2048, h: 2048, fmt: .rgba8),
    BenchCase(label: "4096x4096 GrayF32 (64 MiB)", w: 4096, h: 4096, fmt: .grayF32Le),
]
print("columns: total = Swift-measured makeFrame call; fill = Rust pattern fill; ffi = total - fill - rust checksum (lower + lift + copies)")
for c in cases {
    do {
        let before = footprintMiB()
        for _ in 0..<3 { _ = try makeFrame(width: c.w, height: c.h, format: c.fmt) }
        var total: [Double] = [], fill: [Double] = [], ffi: [Double] = []
        var verified = false
        for i in 0..<30 {
            let t0 = clock.now
            let f = try makeFrame(width: c.w, height: c.h, format: c.fmt)
            let tt = ms(clock.now - t0)
            let fl = Double(f.rustFillNs) / 1e6
            let ck = Double(f.rustChecksumNs) / 1e6
            total.append(tt); fill.append(fl); ffi.append(tt - fl - ck)
            if i == 0 {
                let expected = Int(c.w) * Int(c.h) * 4
                let sumOK = swiftChecksum(f.bytes) == f.checksum
                let off = (2 * Int(c.w) + 3) * 4 // pixel (x=3, y=2)
                var sampleOK = false
                f.bytes.withUnsafeBytes { raw in
                    if c.fmt == .grayF32Le {
                        let bits = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: off, as: UInt32.self))
                        sampleOK = Float(bitPattern: bits) == -1022.0
                    } else {
                        sampleOK = raw[off] == 3 && raw[off + 1] == 2 && raw[off + 2] == 1 && raw[off + 3] == 255
                    }
                }
                verified = f.bytes.count == expected && Int(f.rowStrideBytes) == Int(c.w) * 4 && sumOK && sampleOK
                report.check(verified, "T2 \(c.label) length/stride/checksum/sample",
                             "bytes \(f.bytes.count), checksum \(sumOK ? "match" : "MISMATCH"), sample \(sampleOK ? "ok" : "BAD")")
            }
        }
        let after = footprintMiB()
        report.info("B \(c.label)",
                    "total p50 \(f2(pct(total, 50))) / p95 \(f2(pct(total, 95))) ms; fill p50 \(f2(pct(fill, 50))) ms; ffi p50 \(f2(pct(ffi, 50))) / p95 \(f2(pct(ffi, 95))) ms; footprint \(f2(before))->\(f2(after)) MiB; maxRSS \(f2(maxRssMiB())) MiB")
    } catch {
        report.check(false, "T2 \(c.label)", "\(type(of: error)): \(error)")
    }
}

// MARK: - 3. Swift -> Rust

report.section("3. Swift -> Rust 64 MiB Data: owned (copy) vs borrowed (&[u8]), 10 runs")
do {
    var d = Data(count: 64 << 20)
    d.withUnsafeMutableBytes { raw in
        for i in stride(from: 0, to: raw.count, by: 4096) { raw[i] = UInt8(truncatingIfNeeded: i >> 12) }
    }
    let expected = swiftChecksum(d)
    var owned: [Double] = [], borrowed: [Double] = []
    var okOwned = true, okBorrowed = true
    for _ in 0..<10 {
        var t0 = clock.now
        okOwned = okOwned && checksumOwned(bytes: d) == expected
        owned.append(ms(clock.now - t0))
        t0 = clock.now
        okBorrowed = okBorrowed && checksumBorrowed(bytes: d) == expected
        borrowed.append(ms(clock.now - t0))
    }
    report.check(okOwned && okBorrowed, "T3 checksums match (owned and borrowed)")
    report.info("B Swift->Rust 64 MiB", "owned p50 \(f2(pct(owned, 50))) ms, borrowed p50 \(f2(pct(borrowed, 50))) ms")
}

// MARK: - 4. Payload lifetime after Rust-side eviction

report.section("4. Returned payload outlives Rust cache eviction and object release")
do {
    var cache: FrameCache? = FrameCache()
    try cache!.put(key: "a", width: 512, height: 512, format: .grayF32Le)
    let p = try cache!.get(key: "a")
    cache!.clear()
    report.check(cache!.len() == 0, "L1 cache cleared")
    var threw = false
    do { _ = try cache!.get(key: "a") } catch { threw = true }
    report.check(threw, "L2 get after clear -> error")
    cache = nil
    report.check(swiftChecksum(p.bytes) == p.checksum, "L3 payload still valid after clear and release")
} catch {
    report.check(false, "L lifetime", "\(type(of: error)): \(error)")
}

// MARK: - 5. Repeated allocation (leak smoke test)

report.section("5. 200 x 16 MiB frames, footprint drift")
do {
    let fp0 = footprintMiB()
    for _ in 0..<200 {
        try autoreleasepool {
            let f = try makeFrame(width: 2048, height: 2048, format: .rgba8)
            _ = f.bytes.count
        }
    }
    let fp1 = footprintMiB()
    report.check(fp1 - fp0 < 64, "M1 footprint drift < 64 MiB", "\(f2(fp0)) -> \(f2(fp1)) MiB")
} catch {
    report.check(false, "M1", "\(type(of: error)): \(error)")
}

// MARK: - 6. MainActor responsiveness

@MainActor final class Ticker {
    private(set) var maxGapMs = 0.0
    private(set) var ticks = 0
    private var task: Task<Void, Never>?
    func start() {
        stop()
        maxGapMs = 0
        ticks = 0
        task = Task { @MainActor [weak self] in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(2))
                let now = ContinuousClock.now
                guard let self else { return }
                self.maxGapMs = max(self.maxGapMs, ms(now - last))
                self.ticks += 1
                last = now
            }
        }
    }
    func stop() { task?.cancel(); task = nil }
}

@MainActor func mainActorTests() async {
    report.section("6. MainActor responsiveness during a 300 ms Rust call (ticker every 2 ms)")
    let ticker = Ticker()

    ticker.start(); try? await Task.sleep(for: .milliseconds(30))
    let a = await asyncSleepMs(ms: 300)
    try? await Task.sleep(for: .milliseconds(10))
    ticker.stop()
    report.check(ticker.maxGapMs < 100, "A1 async Rust fn keeps MainActor responsive",
                 "rust slept \(a) ms, max MainActor gap \(f2(ticker.maxGapMs)) ms, ticks \(ticker.ticks)")

    ticker.start(); try? await Task.sleep(for: .milliseconds(30))
    let b = blockingSleepMs(ms: 300)
    try? await Task.sleep(for: .milliseconds(30))
    ticker.stop()
    report.check(ticker.maxGapMs >= 250, "A2 sync Rust fn called on MainActor blocks it (expected, confirms rule)",
                 "rust slept \(b) ms, max MainActor gap \(f2(ticker.maxGapMs)) ms")

    ticker.start(); try? await Task.sleep(for: .milliseconds(30))
    let c = await Task.detached { blockingSleepMs(ms: 300) }.value
    try? await Task.sleep(for: .milliseconds(10))
    ticker.stop()
    report.check(ticker.maxGapMs < 100, "A3 sync Rust fn inside Task.detached keeps MainActor responsive",
                 "rust slept \(c) ms, max MainActor gap \(f2(ticker.maxGapMs)) ms")
}

// MARK: - 7. Cancellation

@MainActor func cancellationTests() async {
    report.section("7. Cancellation of a long Rust task (200 steps x 10 ms)")
    let token = CancelToken()
    async let r = longTask(token: token, steps: 200, stepMs: 10)
    try? await Task.sleep(for: .milliseconds(50))
    token.cancel()
    let tc = clock.now
    do {
        let v = try await r
        report.check(false, "C1 explicit token cancels Rust work", "completed \(v) steps")
    } catch let e as P0Error {
        let lat = ms(clock.now - tc)
        report.check(e == .Cancelled && lat < 100, "C1 explicit token cancels Rust work", "\(e), latency \(f2(lat)) ms")
    } catch {
        report.check(false, "C1 explicit token cancels Rust work", "\(type(of: error)): \(error)")
    }

    let token2 = CancelToken()
    let t = Task { try await longTask(token: token2, steps: 50, stepMs: 10) }
    try? await Task.sleep(for: .milliseconds(50))
    let tc2 = clock.now
    t.cancel()
    let res = await t.result
    report.info("C2 Swift Task.cancel() without token",
                "result \(res), returned \(f2(ms(clock.now - tc2))) ms after cancel (about 450 ms means the cancel did not reach the Rust work)")
}

await mainActorTests()
await cancellationTests()

// MARK: - Summary

print("\n== Summary")
print("failures: \(report.failures.count)\(report.failures.isEmpty ? "" : " -> " + report.failures.joined(separator: ", "))")
print("footprint at end: \(f2(footprintMiB())) MiB, maxRSS \(f2(maxRssMiB())) MiB")
exit(report.failures.isEmpty ? 0 : 1)
