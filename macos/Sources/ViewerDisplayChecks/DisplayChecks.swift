import Darwin
import Foundation
import ViewerBridge
import ViewerRendering

private struct DisplayCheck: Encodable { let id: String; let passed: Bool; let detail: String }
private struct DisplayReport: Encodable {
    let suite = "P1-DISPLAY-APP"
    let passed: Bool
    let passedCount: Int
    let failedCount: Int
    let checks: [DisplayCheck]
    let notRun = ["Physical monitor calibration", "Compressed and Enhanced DICOM", "Rotation and annotation transforms"]
}
private enum CheckError: Error { case assertion(String) }

@main
@MainActor
struct ViewerDisplayChecks {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 1 || args.count == 2 else {
            FileHandle.standardError.write(Data("Usage: ViewerDisplayChecks FIXTURE_DIR [OUTPUT_JSON]\n".utf8)); exit(2)
        }
        let runner = DisplayRunner(directory: args[0]); await runner.run()
        let report = DisplayReport(passed: runner.results.allSatisfy(\.passed),
                                   passedCount: runner.results.filter(\.passed).count,
                                   failedCount: runner.results.filter { !$0.passed }.count, checks: runner.results)
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(report)
            if args.count == 2 { try await Task.detached { try data.write(to: URL(fileURLWithPath: args[1]), options: .atomic) }.value }
            FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
        } catch { FileHandle.standardError.write(Data("Could not write display report.\n".utf8)); exit(2) }
        if !report.passed { exit(1) }
    }
}

@MainActor
private final class DisplayRunner {
    let directory: String
    private(set) var results: [DisplayCheck] = []
    private var renderer: MetalFrameRenderer?
    private let mainThreadCaller: Bool
    init(directory: String) { self.directory = directory; mainThreadCaller = Thread.isMainThread }
    private func path(_ name: String) -> String { URL(fileURLWithPath: directory).appendingPathComponent(name).path }
    private func require(_ condition: Bool, _ detail: String) throws { if !condition { throw CheckError.assertion(detail) } }
    private func check(_ id: String, _ work: () async throws -> Void) async {
        do { try await work(); results.append(DisplayCheck(id: id, passed: true, detail: "expected descriptor, pixels, or ownership matched")) }
        catch CheckError.assertion(let detail) { results.append(DisplayCheck(id: id, passed: false, detail: detail)) }
        catch { results.append(DisplayCheck(id: id, passed: false, detail: "operation failed; input paths and error reasons withheld")) }
    }
    private func closeAfter<T>(_ name: String, _ work: (PreparedPixelFrame, OwnedPixelFrame, UploadedPixelFrame) async throws -> T) async throws -> T {
        let session = try ViewerPixelSession()
        do {
            let prepared = try await session.prepareNativeFrame(path: path(name))
            let owned = try await prepared.copy(using: PixelCopyBudget())
            guard let renderer else { throw RenderingError.unavailable }
            let uploaded = try await renderer.upload(owned)
            await session.close()
            return try await work(prepared, owned, uploaded)
        } catch { await session.close(); throw error }
    }
    private func rgba(_ gray: [UInt8]) -> [UInt8] { gray.flatMap { [$0, $0, $0, UInt8(255)] } }
    private func closeBytes(_ actual: [UInt8], _ expected: [UInt8], tolerance: Int = 1) throws {
        try require(actual.count == expected.count, "output byte length differed")
        for index in expected.indices {
            try require(abs(Int(actual[index]) - Int(expected[index])) <= tolerance, "RGBA channel differed beyond tolerance")
        }
    }
    func run() async {
        await check("main_actor_and_runtime_metal_compilation") {
            try require(mainThreadCaller, "test caller was not MainActor on the main thread")
            renderer = try await MetalFrameRenderer.make()
        }
        let fixtures: [(String, [UInt8])] = [
            ("gray-le.dcm", [0,0,0,0,128,255]), ("gray-be.dcm", [0,0,0,0,128,255]),
            ("gray-implicit.dcm", [0,0,0,0,128,255]), ("display-linear.dcm", [0,0,170,255,255,255]),
            ("display-exact.dcm", [0,0,128,255,255,255]), ("display-sigmoid.dcm", [0,30,128,225,255,255]),
            ("display-mono1.dcm", [0,255,128,0,0,0]), ("display-aspect.dcm", [0,0,0,0,128,255]),
            ("display-uniform.dcm", [128,128,128,128,128,128]), ("display-padding.dcm", [0,0,0,0,0,0]),
            ("display-large-sigmoid.dcm", [250,250,250,250,250,250]),
            ("display-opposite-sigmoid.dcm", [251,251,251,251,251,251])
        ]
        for (name, literal) in fixtures {
            await check("cpu_and_gpu_literal_" + name) {
                try await closeAfter(name) { prepared, owned, uploaded in
                    let descriptor = prepared.display
                    try require(descriptor.sourceRevision.count == 64 && descriptor.sourceRevision == owned.display.sourceRevision
                                && descriptor.descriptorRevision == 1 && descriptor.frameIndex == 0, "source/descriptor revision differed")
                    let cpu = try await prepared.referenceRGBA()
                    try closeBytes(cpu, rgba(literal), tolerance: 0)
                    for interpolation in [PixelInterpolation.nearest, .linear] {
                        let gpu = try await renderer!.renderOffscreen(uploaded, interpolation: interpolation)
                        try closeBytes(gpu, cpu)
                        let invertedCPU = try await prepared.referenceRGBA(userInvert: true)
                        let invertedGPU = try await renderer!.renderOffscreen(uploaded, userInvert: true, interpolation: interpolation)
                        try closeBytes(invertedGPU, invertedCPU)
                        if name != "display-uniform.dcm" && name != "display-large-sigmoid.dcm" && name != "display-opposite-sigmoid.dcm" {
                            try require(invertedCPU[0] == 0 && invertedGPU[0] == 0, "padding changed under inversion")
                        }
                    }
                    if name.hasPrefix("gray-") { try require(descriptor.automaticWindow, "missing VOI did not use explicit automatic policy") }
                    if name == "display-padding.dcm" { try require(!descriptor.canWindow && descriptor.defaultWindow == nil, "all-padding descriptor fabricated VOI") }
                    if name == "display-uniform.dcm" { try require(descriptor.automaticWindow && descriptor.defaultWindow?.center == -10 && descriptor.defaultWindow?.width == 1, "uniform automatic window differed") }
                    if name == "display-mono1.dcm" { try require(descriptor.inverted, "MONOCHROME1 final polarity missing") }
                    if ["display-linear.dcm", "display-exact.dcm", "display-sigmoid.dcm"].contains(name) {
                        try require(!descriptor.automaticWindow && descriptor.defaultWindow?.center == -10 && descriptor.defaultWindow?.width == 4, "file VOI was replaced or changed")
                    }
                }
            }
        }
        await check("rgb_identity_and_disabled_gray_capabilities") {
            try await closeAfter("rgb.dcm") { prepared, owned, uploaded in
                let expected: [UInt8] = [255,0,0,255,0,255,0,255,0,0,255,255,17,34,51,255]
                try require(!owned.display.canWindow && owned.display.defaultWindow == nil && !owned.display.inverted, "RGB exposed gray settings")
                for inverted in [false, true] {
                    try closeBytes(try await prepared.referenceRGBA(userInvert: inverted), expected, tolerance: 0)
                    try closeBytes(try await renderer!.renderOffscreen(uploaded, userInvert: inverted), expected, tolerance: 0)
                }
            }
        }
        await check("multiple_file_windows_and_changed_voi") {
            try await closeAfter("display-multiwindow.dcm") { prepared, _, uploaded in
                let windows = prepared.display.windows
                try require(windows.count == 2 && windows[0].center == -10 && windows[0].width == 4
                            && windows[1].center == 2036 && windows[1].width == 4096, "paired file windows were lost")
                for item in windows {
                    let cpu = try await prepared.referenceRGBA(window: item)
                    let gpu = try await renderer!.renderOffscreen(uploaded, window: item)
                    try closeBytes(gpu, cpu)
                }
            }
        }
        await check("linear_width_one_and_near_one") {
            try await closeAfter("gray-le.dcm") { prepared, _, uploaded in
                for (width, literal): (Double, [UInt8]) in [(1, [0,0,0,255,255,255]), (1.00000001, [0,0,128,255,255,255])] {
                    let window = VoiWindow(center: -9.5, width: width, function: .linear)
                    let cpu = try await prepared.referenceRGBA(window: window)
                    try closeBytes(cpu, rgba(literal), tolerance: 0)
                    try closeBytes(try await renderer!.renderOffscreen(uploaded, window: window), cpu)
                }
            }
        }
        await check("mask_nearest_and_weighted_linear_neighbors") {
            try await closeAfter("display-exact.dcm") { _, _, uploaded in
                let linear = try await renderer!.renderOffscreen(uploaded, outputWidth: 6, outputHeight: 4)
                let inverted = try await renderer!.renderOffscreen(uploaded, userInvert: true, outputWidth: 6, outputHeight: 4)
                let nearest = try await renderer!.renderOffscreen(uploaded, interpolation: .nearest, outputWidth: 6, outputHeight: 4)
                try closeBytes(Array(linear.prefix(24)), rgba([0,0,0,32,96,128]))
                try closeBytes(Array(inverted.prefix(24)), rgba([0,0,255,223,159,128]))
                try closeBytes(Array(nearest.prefix(24)), rgba([0,0,0,0,128,128]))
            }
        }
        await check("aspect_fit_pan_zoom_and_retina_roundtrip") { try await geometry() }
        await check("reject_invalid_file_voi") {
            let session = try ViewerPixelSession()
            do { _ = try await session.prepareNativeFrame(path: path("invalid-window.dcm")); await session.close(); throw CheckError.assertion("invalid file VOI accepted") }
            catch ViewerPixelError.unsupported { await session.close() }
            catch { await session.close(); throw error }
            try require(session.memorySnapshot().liveBytes == 0 && session.memorySnapshot().activePreparations == 0, "invalid VOI retained resources")
        }
        await check("reject_invalid_override_window") {
            try await closeAfter("gray-le.dcm") { prepared, _, uploaded in
                let invalid = VoiWindow(center: 0, width: 0, function: .linear)
                do { _ = try await prepared.referenceRGBA(window: invalid); throw CheckError.assertion("CPU accepted invalid override") }
                catch ViewerPixelError.invalidArgument {}
                do { _ = try await renderer!.renderOffscreen(uploaded, window: invalid); throw CheckError.assertion("GPU accepted invalid override") }
                catch RenderingError.invalidDisplay {}
            }
        }
        await check("shared_generation_rule_rejects_late_completion") {
            let gate = DisplayGenerationGate(); var imageID = "old"; var labelID = "old"
            let a = gate.begin(), b = gate.begin()
            try require(gate.installIfCurrent(b) { imageID = "new"; labelID = "new" }, "latest completion rejected")
            try require(!gate.installIfCurrent(a) { imageID = "stale"; labelID = "stale" }
                        && imageID == "new" && labelID == "new", "late completion replaced image or label")
            gate.begin(); try require(!gate.accepts(b), "close/invalidation accepted old generation")
        }
        await check("shared_full_state_restore_and_stale_failure") {
            let gate = DisplayGenerationGate()
            let actualHistory = PresentedStateHistory(gate: gate)
            let a = gate.begin()
            let original = PresentedViewState(window: VoiWindow(center: 17, width: 29, function: .sigmoid),
                                              inverted: true, zoom: 2.5, pan: PixelPoint2D(x: -3, y: 4), generation: a)
            try require(actualHistory.record(original, requestGeneration: a), "valid presentation not recorded")
            let b = gate.begin()
            let candidate = PresentedViewState(window: VoiWindow(center: -10, width: 4, function: .linear),
                                               inverted: false, zoom: 1, pan: .zero, generation: b)
            let restored = actualHistory.restoration(forFailedGeneration: b)
            try require(restored?.window?.center == 17 && restored?.window?.width == 29 && restored?.window?.function == .sigmoid
                        && restored?.inverted == true && restored?.zoom == 2.5 && restored?.pan == PixelPoint2D(x: -3, y: 4)
                        && restored?.generation == a, "failed candidate replaced a previous display setting")
            try require(actualHistory.restoration(forFailedGeneration: a) == nil, "stale failure restored over current request")
            try require(actualHistory.record(candidate, requestGeneration: b)
                        && !actualHistory.record(original, requestGeneration: a), "stale presentation overwrote accepted state")
        }
        await check("safe_display_limit_diagnostics") {
            try await closeAfter("display-diagnostics.dcm") { prepared, _, _ in
                try require(prepared.display.diagnostics.contains("overlay_not_applied")
                            && prepared.display.diagnostics.contains("shutter_not_applied"), "unsupported display effects were hidden")
            }
        }
        await check("finite_but_unrepresentable_metal_window_rejected") {
            try await closeAfter("display-unrenderable-window.dcm") { _, _, uploaded in
                do { _ = try await renderer!.renderOffscreen(uploaded); throw CheckError.assertion("unrepresentable window produced normal pixels") }
                catch RenderingError.invalidDisplay {}
            }
        }
        await check("native_frame_larger_than_metal_texture_limit_rejected") {
            let session = try ViewerPixelSession()
            do {
                let prepared = try await session.prepareNativeFrame(path: path("oversized-texture.dcm"))
                let owned = try await prepared.copy(using: PixelCopyBudget())
                try require(owned.info.width == 20_000 && owned.info.height == 1 && owned.info.byteLen == 80_000,
                            "native oversized-texture fixture did not prepare exactly")
                do { _ = try await renderer!.upload(owned); throw CheckError.assertion("texture dimensions reached device validation") }
                catch RenderingError.invalidDisplay {}
                await session.close()
            } catch { await session.close(); throw error }
        }
        await check("gpu_uploaded_owner_survives_copy_release") { try await ownership() }
    }

    private func geometry() async throws {
        try await closeAfter("display-aspect.dcm") { _, owned, _ in
            try require(owned.display.pixelHeightOverWidth == 2 && owned.display.aspectSource == "pixel_spacing", "Rust display aspect differed")
            let fit = try ViewportTransform(width: 3, height: 2, aspect: 2, viewWidth: 600, viewHeight: 400)
            let top = fit.sourceToScreen(PixelPoint2D(x: -0.5, y: -0.5))
            let bottom = fit.sourceToScreen(PixelPoint2D(x: 2.5, y: 1.5))
            try require(abs(top.x - 150) < 1e-6 && abs(top.y) < 1e-6 && abs(bottom.x - 450) < 1e-6
                        && abs(bottom.y - 400) < 1e-6, "fit did not preserve non-square pixel bounds")
            for mapping in [fit, try ViewportTransform(width: 3, height: 2, aspect: 2, viewWidth: 600, viewHeight: 400,
                                                      zoom: 150, pan: PixelPoint2D(x: 1, y: -2))] {
                for point in [PixelPoint2D(x: -0.5, y: -0.5), PixelPoint2D(x: 2.5, y: 1.5), PixelPoint2D(x: 1.2, y: 0.6)] {
                    let screen = mapping.sourceToScreen(point)
                    let source = try mapping.backingPixelToSource(PixelPoint2D(x: screen.x * 2, y: screen.y * 2), scale: 2)
                    try require(abs(source.x - point.x) < 1e-6 && abs(source.y - point.y) < 1e-6, "Retina/pan/zoom inverse changed source point")
                }
            }
        }
    }

    private func ownership() async throws {
        let session = try ViewerPixelSession(), budget = PixelCopyBudget(maxLiveBytes: 30)
        let prepared = try await session.prepareNativeFrame(path: path("gray-le.dcm"))
        var owned: OwnedPixelFrame? = try await prepared.copy(using: budget)
        weak let weakOwned = owned
        var uploaded: UploadedPixelFrame? = try await renderer!.upload(owned!)
        owned = nil
        try require(weakOwned != nil && budget.snapshot().liveBytes == 30, "upload lost owned source before GPU use")
        _ = try await renderer!.renderOffscreen(uploaded!)
        try require(budget.snapshot().liveBytes == 30, "GPU completion released still-owned upload")
        uploaded = nil
        for _ in 0..<100 {
            if weakOwned == nil && budget.snapshot().liveBytes == 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try require(weakOwned == nil && budget.snapshot().liveBytes == 0, "last GPU owner did not return Swift budget")
        await session.close()
    }
}
