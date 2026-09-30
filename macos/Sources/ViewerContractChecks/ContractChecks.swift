import Darwin
import Foundation
import ViewerBridge

private struct CheckRecord: Encodable {
    let id: String
    let status: String
    let detail: String
}

private struct ContractReport: Encodable {
    let schemaRevision = 1
    let suite = "P1-PIXEL-SWIFT"
    let status: String
    let passed: Bool
    let passedCount: Int
    let failedCount: Int
    let apiRevision: UInt32
    let coreVersion: String
    let dicomRSVersion: String
    let osVersion: String
    let architecture: String
    let mainActorCallerOnMainThread: Bool
    let checks: [CheckRecord]
    let notRun = ["Metal presentation and GPU lifetime", "Full DICOM codec support", "Request generation and cancellation"]
}

private enum CheckFailure: Error {
    case assertion(String)
}

private enum ExpectedError: String {
    case resourceLimit, invalidArgument, unsupported, decodeFailed, sessionClosed
}

@main
@MainActor
struct ViewerContractChecks {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 1 || arguments.count == 2 else {
            FileHandle.standardError.write(Data("Usage: ViewerContractChecks FIXTURE_DIR [OUTPUT_JSON]\n".utf8))
            exit(2)
        }
        let fixtureDirectory = arguments[0]
        let outputPath = arguments.count == 2 ? arguments[1] : nil
        let runner = ContractRunner(fixtureDirectory: fixtureDirectory)
        await runner.run()
        let readiness = ViewerBridge.readiness()
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "other"
        #endif
        let report = ContractReport(
            status: runner.records.allSatisfy { $0.status == "pass" } ? "pass" : "fail",
            passed: runner.records.allSatisfy { $0.status == "pass" },
            passedCount: runner.records.filter { $0.status == "pass" }.count,
            failedCount: runner.records.filter { $0.status == "fail" }.count,
            apiRevision: readiness.apiRevision, coreVersion: readiness.coreVersion,
            dicomRSVersion: readiness.dicomRSVersion,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: architecture, mainActorCallerOnMainThread: runner.mainThreadCaller,
            checks: runner.records
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(report)
            if let outputPath {
                try await Task.detached {
                    try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
                }.value
            }
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([0x0A]))
        } catch {
            FileHandle.standardError.write(Data("Could not write contract report.\n".utf8))
            exit(2)
        }
        if report.status != "pass" { exit(1) }
    }
}

@MainActor
private final class ContractRunner {
    private let fixtureDirectory: String
    private(set) var records: [CheckRecord] = []
    let mainThreadCaller: Bool

    init(fixtureDirectory: String) {
        self.fixtureDirectory = fixtureDirectory
        mainThreadCaller = Thread.isMainThread
    }

    func run() async {
        await check("main_actor_background_boundary") {
            try self.require(self.mainThreadCaller, "CLI did not call from MainActor's main thread")
            let session = try ViewerPixelSession()
            let prepared = try await session.prepareNativeFrame(path: self.path("gray-le.dcm"))
            let copy = try await prepared.copy(using: PixelCopyBudget(maxLiveBytes: 30))
            try self.require(self.grayMatches(copy), "background preparation/copy returned wrong values")
            await session.close()
        }
        for fixture in ["gray-le.dcm", "gray-be.dcm", "gray-implicit.dcm"] {
            await check("golden_" + fixture) { try await self.grayGolden(fixture) }
        }
        await check("golden_rgb.dcm") { try await self.colorGolden() }
        await check("rust_handle_and_swift_copy_survive_close") { try await self.retainedLifetime() }
        await check("swift_budget_alias_and_readmission") { try await self.swiftBudget() }
        await check("rust_live_budget_includes_evicted_handles") { try await self.rustBudget() }
        await check("rust_per_frame_limit_before_payload") { try await self.rustPerFrameLimit() }
        await check("concurrent_separate_immutable_copies") { try await self.concurrentCopies() }
        await check("invalid_frame_index") {
            let session = try ViewerPixelSession()
            let fixturePath = self.path("gray-le.dcm")
            try await self.expectError(.invalidArgument, path: fixturePath) {
                _ = try await session.prepareNativeFrame(path: fixturePath, frameIndex: 1)
            }
            try self.requireClean(session)
            await session.close()
        }
        let rejected: [(String, ExpectedError)] = [
            ("unsupported-multiframe.dcm", .unsupported),
            ("unsupported-compressed.dcm", .unsupported),
            ("unsupported-enhanced.dcm", .unsupported),
            ("unsupported-overflow.dcm", .unsupported),
            ("malformed.dcm", .decodeFailed),
            ("missing.dcm", .decodeFailed),
            ("oversized.dcm", .resourceLimit),
        ]
        for (fixture, expected) in rejected {
            await check("reject_" + fixture) {
                let session = try ViewerPixelSession()
                let fixturePath = self.path(fixture)
                try await self.expectError(expected, path: fixturePath) {
                    _ = try await session.prepareNativeFrame(path: fixturePath)
                }
                try self.requireClean(session)
                await session.close()
            }
        }
    }

    private func check(_ id: String, operation: @MainActor () async throws -> Void) async {
        do {
            try await operation()
            records.append(CheckRecord(id: id, status: "pass", detail: "expected values and lifetime/budget conditions matched"))
        } catch CheckFailure.assertion(let detail) {
            records.append(CheckRecord(id: id, status: "fail", detail: detail))
        } catch {
            // Error reasons and input paths are never included in the report.
            records.append(CheckRecord(id: id, status: "fail", detail: "unexpected error category: " + errorCategory(error)))
        }
    }

    private func path(_ name: String) -> String {
        URL(fileURLWithPath: fixtureDirectory, isDirectory: true).appendingPathComponent(name).path
    }

    private func require(_ condition: Bool, _ detail: String) throws {
        if !condition { throw CheckFailure.assertion(detail) }
    }

    private func waitUntil(_ detail: String, condition: @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CheckFailure.assertion(detail)
    }

    private func requireClean(_ session: ViewerPixelSession) throws {
        let snapshot = session.memorySnapshot()
        try require(snapshot.liveBytes == 0 && snapshot.cachedFrames == 0 && snapshot.activePreparations == 0,
                    "failed preparation retained payload or active work")
    }

    private func expectError(
        _ expected: ExpectedError, path: String,
        operation: @MainActor () async throws -> Void
    ) async throws {
        do {
            try await operation()
        } catch let error as ViewerPixelError {
            try require(errorCategory(error) == expected.rawValue, "incorrect error category for rejected input")
            if let reason = errorReason(error) {
                try require(!reason.contains(path) && !reason.contains(fixtureDirectory)
                            && !reason.contains("file://"), "error reason exposed input path")
            }
            return
        }
        throw CheckFailure.assertion("operation succeeded although rejection was expected")
    }

    private func errorCategory(_ error: any Error) -> String {
        guard let error = error as? ViewerPixelError else { return "other" }
        switch error {
        case .resourceLimit: return "resourceLimit"
        case .invalidArgument: return "invalidArgument"
        case .unsupported: return "unsupported"
        case .decodeFailed: return "decodeFailed"
        case .sessionClosed: return "sessionClosed"
        case .busy: return "busy"
        case .invalidContract: return "invalidContract"
        case .copyFailed: return "copyFailed"
        }
    }

    private func errorReason(_ error: ViewerPixelError) -> String? {
        switch error {
        case .resourceLimit(let reason), .invalidArgument(let reason), .unsupported(let reason),
             .decodeFailed(let reason), .invalidContract(let reason): return reason
        case .sessionClosed, .busy, .copyFailed: return nil
        }
    }

    private func grayMatches(_ frame: OwnedPixelFrame) -> Bool {
        let info = frame.info
        guard info.width == 3, info.height == 2, info.rowStrideBytes == 12,
              info.byteLen == 24, info.maskLen == 6, info.pixelFormat == .grayF32LE,
              info.valueDomain == .modalityApplied, info.contractRevision == 1,
              info.payloadRevision == 1 else { return false }
        // Independent literals for [-2048,-1,0,1,1024,2047], slope 2,
        // intercept -10, with the first source value excluded as padding.
        let expected: [Float] = [0, -12, -10, -8, 2038, 4084]
        let pixelsMatch = frame.withUnsafePixelBytes { bytes in
            guard bytes.count == 24 else { return false }
            for index in 0..<expected.count {
                let offset = index * 4
                let bits = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
                    | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
                if bits != expected[index].bitPattern { return false }
            }
            return true
        }
        let maskMatches = frame.withUnsafeMaskBytes { bytes in
            bytes?.elementsEqual([UInt8(0), 1, 1, 1, 1, 1]) == true
        }
        return pixelsMatch && maskMatches
    }

    private func grayGolden(_ fixture: String) async throws {
        let session = try ViewerPixelSession()
        let prepared = try await session.prepareNativeFrame(path: path(fixture))
        let budget = PixelCopyBudget(maxLiveBytes: 30)
        let copy = try await prepared.copy(using: budget)
        try require(grayMatches(copy), "gray metadata, little-endian float bytes, or mask differed from literals")
        let rust = session.memorySnapshot()
        let swift = budget.snapshot()
        try require(rust.liveBytes == 30 && rust.peakBytes == 30 && rust.cachedFrames == 1,
                    "Rust did not charge exactly 24 pixel plus 6 mask bytes")
        try require(swift.liveBytes == 30 && swift.peakBytes == 30 && swift.liveCopies == 1,
                    "Swift did not charge exactly one 30-byte destination")
        await session.close()
    }

    private func colorGolden() async throws {
        let session = try ViewerPixelSession(maxLiveBytes: 16, maxFrameBytes: 16)
        let prepared = try await session.prepareNativeFrame(path: path("rgb.dcm"))
        let budget = PixelCopyBudget(maxLiveBytes: 16)
        let copy = try await prepared.copy(using: budget)
        let info = copy.info
        let expected: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 17, 34, 51, 255]
        try require(info.width == 2 && info.height == 2 && info.rowStrideBytes == 8
                    && info.byteLen == 16 && info.maskLen == 0 && info.pixelFormat == .rgba8
                    && info.valueDomain == .displayColor, "RGBA metadata differed")
        try require(copy.withUnsafePixelBytes { $0.elementsEqual(expected) }, "RGBA bytes differed from literal color patches")
        try require(copy.withUnsafeMaskBytes { $0 == nil }, "color unexpectedly included a mask")
        try require(session.memorySnapshot().liveBytes == 16 && budget.snapshot().liveBytes == 16,
                    "RGB payload or destination charge differed")
        await session.close()
    }

    private func retainedLifetime() async throws {
        let session = try ViewerPixelSession(maxLiveBytes: 30, maxFrameBytes: 30)
        var prepared: PreparedPixelFrame? = try await session.prepareNativeFrame(path: path("gray-le.dcm"))
        weak let weakPrepared = prepared
        let evicted = await session.evictAll()
        try require(evicted == 1 && session.memorySnapshot().cachedFrames == 0,
                    "cache eviction did not remove the cached frame")
        try require(session.memorySnapshot().liveBytes == 30, "eviction lost the retained Rust payload charge")
        await session.close()
        try require(session.memorySnapshot().liveBytes == 30, "close invalidated a retained payload")
        let budget = PixelCopyBudget(maxLiveBytes: 30)
        var owned: OwnedPixelFrame? = try await prepared!.copy(using: budget)
        try require(grayMatches(owned!), "copy after close was invalid")
        let fixturePath = path("gray-le.dcm")
        try await expectError(.sessionClosed, path: fixturePath) {
            _ = try await session.prepareNativeFrame(path: fixturePath)
        }
        prepared = nil
        try await waitUntil("last prepared owner did not release Rust bytes") {
            weakPrepared == nil && session.memorySnapshot().liveBytes == 0
        }
        try require(grayMatches(owned!) && budget.snapshot().liveBytes == 30,
                    "Swift copy did not survive the last Rust owner")
        weak let weakOwned = owned
        var alias = owned
        owned = nil
        try require(alias != nil && budget.snapshot().liveBytes == 30 && budget.snapshot().liveCopies == 1,
                    "strong alias duplicated or prematurely released the Swift charge")
        alias = nil
        try await waitUntil("last Swift owner did not release its reservation") {
            weakOwned == nil && budget.snapshot().liveBytes == 0 && budget.snapshot().liveCopies == 0
        }
    }

    private func swiftBudget() async throws {
        let session = try ViewerPixelSession()
        let prepared = try await session.prepareNativeFrame(path: path("gray-le.dcm"))
        let tooSmall = PixelCopyBudget(maxLiveBytes: 29)
        try await expectError(.resourceLimit, path: path("gray-le.dcm")) {
            _ = try await prepared.copy(using: tooSmall)
        }
        try require(tooSmall.snapshot().liveBytes == 0 && tooSmall.snapshot().peakBytes == 0,
                    "failed reservation allocated or retained destination bytes")
        let budget = PixelCopyBudget(maxLiveBytes: 60)
        var first: OwnedPixelFrame? = try await prepared.copy(using: budget)
        var second: OwnedPixelFrame? = try await prepared.copy(using: budget)
        try require(grayMatches(first!) && grayMatches(second!), "duplicate copies differed")
        try require(budget.snapshot().liveBytes == 60 && budget.snapshot().liveCopies == 2,
                    "two distinct destinations were not charged independently")
        try await expectError(.resourceLimit, path: path("gray-le.dcm")) {
            _ = try await prepared.copy(using: budget)
        }
        weak let weakFirst = first
        var alias = first
        first = nil
        try require(alias != nil && budget.snapshot().liveBytes == 60, "alias released or added a charge")
        alias = nil
        try await waitUntil("released destination did not restore admission") {
            weakFirst == nil && budget.snapshot().liveBytes == 30
        }
        var replacement: OwnedPixelFrame? = try await prepared.copy(using: budget)
        try require(grayMatches(replacement!) && budget.snapshot().liveBytes == 60
                    && budget.snapshot().peakBytes == 60, "replacement exceeded or failed restored admission")
        second = nil
        replacement = nil
        try await waitUntil("Swift copy budget did not return to zero") {
            budget.snapshot().liveBytes == 0 && budget.snapshot().liveCopies == 0
        }
        await session.close()
    }

    private func rustBudget() async throws {
        let session = try ViewerPixelSession(maxLiveBytes: 30, maxFrameBytes: 30)
        var held: PreparedPixelFrame? = try await session.prepareNativeFrame(path: path("gray-le.dcm"))
        weak let weakHeld = held
        let fixturePath = path("gray-le.dcm")
        try await expectError(.resourceLimit, path: fixturePath) {
            _ = try await session.prepareNativeFrame(path: fixturePath)
        }
        _ = await session.evictAll()
        try require(session.memorySnapshot().cachedFrames == 0 && session.memorySnapshot().liveBytes == 30,
                    "evicted handle escaped Rust live budget")
        try await expectError(.resourceLimit, path: fixturePath) {
            _ = try await session.prepareNativeFrame(path: fixturePath)
        }
        held = nil
        try await waitUntil("Rust budget remained charged after cache and owner release") {
            weakHeld == nil && session.memorySnapshot().liveBytes == 0
        }
        var replacement: PreparedPixelFrame? = try await session.prepareNativeFrame(path: fixturePath)
        try require(replacement?.info.byteLen == 24 && session.memorySnapshot().liveBytes == 30
                    && session.memorySnapshot().peakBytes == 30, "Rust admission did not recover within limit")
        await session.close()
        replacement = nil
        try await waitUntil("Rust replacement did not release") { session.memorySnapshot().liveBytes == 0 }
        try requireClean(session)
    }

    private func rustPerFrameLimit() async throws {
        let session = try ViewerPixelSession(maxLiveBytes: 60, maxFrameBytes: 29)
        let fixturePath = path("gray-le.dcm")
        try await expectError(.resourceLimit, path: fixturePath) {
            _ = try await session.prepareNativeFrame(path: fixturePath)
        }
        try requireClean(session)
        try require(session.memorySnapshot().peakBytes == 0, "per-frame rejection reserved a payload")
        await session.close()
    }

    private func concurrentCopies() async throws {
        let session = try ViewerPixelSession()
        let prepared = try await session.prepareNativeFrame(path: path("gray-le.dcm"))
        let budget = PixelCopyBudget(maxLiveBytes: 60)
        try await copyPair(prepared, budget: budget)
        try await waitUntil("concurrent copies did not release both destinations") {
            budget.snapshot().liveBytes == 0 && budget.snapshot().liveCopies == 0
        }
        await session.close()
    }

    private func copyPair(_ prepared: PreparedPixelFrame, budget: PixelCopyBudget) async throws {
        async let firstResult = prepared.copy(using: budget)
        async let secondResult = prepared.copy(using: budget)
        let (first, second) = try await (firstResult, secondResult)
        try require(first !== second && grayMatches(first) && grayMatches(second), "concurrent results aliased or differed")
        let differentAllocations = first.withUnsafePixelBytes { firstBytes in
            second.withUnsafePixelBytes { secondBytes in firstBytes.baseAddress != secondBytes.baseAddress }
        }
        try require(differentAllocations && budget.snapshot().liveBytes == 60
                    && budget.snapshot().peakBytes == 60 && budget.snapshot().liveCopies == 2,
                    "concurrent destinations shared storage or exceeded accounting")
    }
}
