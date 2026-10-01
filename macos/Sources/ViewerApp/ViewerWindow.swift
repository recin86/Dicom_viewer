import AppKit
@preconcurrency import MetalKit
import ViewerBridge
import ViewerRendering

@MainActor
final class ViewerWindow: NSObject, MTKViewDelegate, NSWindowDelegate {
    let window: NSWindow
    let openButton: NSButton
    var presentationObserver: ((Bool, UInt64, PixelFrameMetadata?) -> Void)?
    private let gate = DisplayGenerationGate()
    private let budget = PixelCopyBudget()
    private let metalView = FrameMetalView(frame: .zero, device: nil)
    private let emptyLabel = NSTextField(labelWithString: "열린 영상이 없습니다.\n파일 열기로 단일 영상을 선택해 주세요.")
    private let loadingLabel = NSTextField(labelWithString: "불러오는 중…")
    private let imageLabel = NSTextField(labelWithString: "영상 없음")
    private let statusLabel = NSTextField(labelWithString: "")
    private let limitationLabel = NSTextField(wrappingLabelWithString: "")
    private let retryButton = NSButton(title: "다시 시도", target: nil, action: nil)
    private let windows = NSPopUpButton(frame: .zero, pullsDown: false)
    private let centerField = NSTextField(string: "")
    private let widthField = NSTextField(string: "")
    private let invertButton = NSButton(checkboxWithTitle: "반전", target: nil, action: nil)
    private let fitButton = NSButton(title: "맞춤", target: nil, action: nil)
    private var renderer: MetalFrameRenderer?
    private var uploaded: UploadedPixelFrame?
    private var lastPresented: UploadedPixelFrame?
    private lazy var stateHistory = PresentedStateHistory(gate: gate)
    private var drawRevision: UInt64 = 0
    private var installedGeneration: UInt64 = 0
    private var presentedGeneration: UInt64 = 0
    private var selectedWindow: VoiWindow?
    private var userInvert = false
    private var zoomMultiplier: Double = 1
    private var pan = PixelPoint2D.zero
    private var requestedPath: String?
    private var loadTask: Task<Void, Never>?
    private var loading = false
    private let traceEnabled = CommandLine.arguments.contains("--trace-display")
    private var submittedDraws: UInt64 = 0
    private var gpuCompletedDraws: UInt64 = 0
    private var actualPresentedDraws: UInt64 = 0

    init(readiness: ViewerReadiness) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "DICOM Viewer"; window.minSize = NSSize(width: 980, height: 540)
        window.isReleasedWhenClosed = false; window.setFrameAutosaveName("ViewerMainWindow")
        openButton = NSButton(title: "열기…", target: nil, action: nil)
        super.init()
        window.delegate = self
        openButton.target = self; openButton.action = #selector(openFile(_:))
        openButton.isEnabled = ViewerBridge.nativeDisplayAvailable(); openButton.bezelStyle = .rounded
        openButton.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        openButton.imagePosition = .imageLeading
        setupContent()
        metalView.colorPixelFormat = .bgra8Unorm; metalView.framebufferOnly = true
        metalView.isPaused = true; metalView.enableSetNeedsDisplay = true
        metalView.preferredFramesPerSecond = 60
        metalView.clearColor = MTLClearColorMake(0, 0, 0, 1); metalView.delegate = self
        metalView.onPan = { [weak self] dx, dy in self?.move(dx: dx, dy: dy) }
        metalView.onZoom = { [weak self] factor, point in self?.zoom(factor: factor, around: point) }
        metalView.onFit = { [weak self] in self?.fit(nil) }
        setControlsEnabled(false)
    }

    @objc func openFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false; panel.title = "영상 파일 열기"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let path = panel.url?.path else { return }
            self?.load(path: path)
        }
    }

    func load(path: String) {
        requestedPath = path
        let generation = gate.begin()
        pauseDrawing()
        loadTask?.cancel(); loading = true; loadingLabel.isHidden = false; retryButton.isHidden = true
        trace("load_started", generation: generation)
        statusLabel.stringValue = ""; setControlsEnabled(false)
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var session: ViewerPixelSession?
            do {
                let created = try ViewerPixelSession(); session = created
                let prepared = try await created.prepareNativeFrame(path: path)
                let owned = try await prepared.copy(using: budget)
                let rendering: MetalFrameRenderer
                if let renderer { rendering = renderer } else { rendering = try await MetalFrameRenderer.make() }
                let ready = try await rendering.upload(owned)
                await created.close(); session = nil
                gate.installIfCurrent(generation) {
                    renderer = rendering; metalView.device = rendering.device
                    uploaded = ready; installedGeneration = generation
                    selectedWindow = owned.display.defaultWindow; userInvert = false
                    zoomMultiplier = 1; pan = .zero; emptyLabel.isHidden = true
                    // Sheets and resize transactions may skip the first drawable.
                    // Keep requesting fresh drawables until actual presentation,
                    // then return to on-demand drawing for ordinary interaction.
                    metalView.enableSetNeedsDisplay = false; metalView.isPaused = false
                    trace("candidate_installed", generation: generation)
                    requestDraw()
                }
            } catch {
                if let session { await session.close() }
                guard gate.accepts(generation) else { return }
                fail(error: error, generation: generation)
            }
        }
    }

    func windowWillClose(_ notification: Notification) { gate.begin(); loadTask?.cancel(); pauseDrawing(); metalView.delegate = nil }
    private func fail(error: any Error, generation: UInt64) {
        guard gate.accepts(generation) else { return }
        pauseDrawing()
        loading = false; loadingLabel.isHidden = true; retryButton.isHidden = false
        trace("load_failed", generation: generation)
        uploaded = lastPresented
        emptyLabel.isHidden = uploaded != nil
        if let state = stateHistory.restoration(forFailedGeneration: generation) {
            selectedWindow = state.window; userInvert = state.inverted
            zoomMultiplier = state.zoom; pan = state.pan; installedGeneration = state.generation
            populateControls()
        }
        statusLabel.stringValue = safeFailure(error); setControlsEnabled(uploaded != nil)
        requestDraw()
        presentationObserver?(false, generation, nil)
    }
    private func safeFailure(_ error: any Error) -> String {
        guard let error = error as? ViewerPixelError else { return "영상을 표시하지 못했습니다. 다시 시도해 주세요." }
        switch error {
        case .unsupported: return "이 영상 형식이나 변환은 아직 지원하지 않습니다."
        case .resourceLimit: return "영상이 현재 메모리 한도를 초과했습니다."
        case .decodeFailed: return "영상 파일을 읽지 못했습니다. 파일을 확인해 주세요."
        case .invalidArgument: return "영상의 입력 정보를 확인해 주세요."
        default: return "영상을 준비하지 못했습니다. 다시 시도해 주세요."
        }
    }
    private func requestDraw() { drawRevision += 1; metalView.setNeedsDisplay(metalView.bounds) }
    private func pauseDrawing() { metalView.isPaused = true; metalView.enableSetNeedsDisplay = true }
    private func trace(_ event: String, generation: UInt64) {
        guard traceEnabled else { return }
        let value = DisplayTrace(event: event, generation: generation, revision: drawRevision,
                                 loading: loading, submitted: submittedDraws,
                                 gpuCompleted: gpuCompletedDraws, actuallyPresented: actualPresentedDraws)
        guard let data = try? JSONEncoder().encode(value) else { return }
        FileHandle.standardError.write(data); FileHandle.standardError.write(Data([10]))
    }
    private func transform() throws -> ViewportTransform {
        guard let uploaded else { throw RenderingError.invalidDisplay }
        let info = uploaded.owned.info
        let fit = try ViewportTransform(width: info.width, height: info.height, aspect: uploaded.owned.display.pixelHeightOverWidth,
                                       viewWidth: max(1, metalView.bounds.width), viewHeight: max(1, metalView.bounds.height))
        return try ViewportTransform(width: info.width, height: info.height, aspect: fit.aspect,
                                     viewWidth: fit.viewWidth, viewHeight: fit.viewHeight, zoom: fit.zoom * zoomMultiplier, pan: pan)
    }
    func draw(in view: MTKView) {
        guard let renderer, let uploaded, let drawable = view.currentDrawable else { return }
        let generation = installedGeneration
        let requestGeneration = loading ? generation : gate.current
        let revision = drawRevision
        do {
            try renderer.draw(uploaded, drawable: drawable, transform: transform(), window: selectedWindow, userInvert: userInvert,
                              event: { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch event {
                    case .submitted: submittedDraws += 1
                    case .gpuCompleted: gpuCompletedDraws += 1
                    case .presented: actualPresentedDraws += 1
                    case .gpuFailed, .skipped: break
                    }
                    trace(event.rawValue, generation: generation)
                }
            }) { [weak self] success in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard gate.accepts(requestGeneration), self.uploaded === uploaded else {
                        trace("stale_presentation_ignored", generation: generation); return
                    }
                    // Resizing may enqueue another draw while the first candidate
                    // is presenting. Loading controls cannot change its VOI, so
                    // that valid first presentation must still make the UI Ready.
                    guard loading || drawRevision == revision else { return }
                    guard success else { fail(error: RenderingError.commandFailed, generation: requestGeneration); return }
                    lastPresented = uploaded
                    let firstPresentation = presentedGeneration != generation
                    if firstPresentation {
                        presentedGeneration = generation; loading = false; loadingLabel.isHidden = true
                        pauseDrawing(); trace("ready", generation: generation)
                        imageLabel.stringValue = "\(uploaded.owned.info.width) × \(uploaded.owned.info.height) · "
                            + (uploaded.owned.info.pixelFormat == .grayF32LE ? "회색조" : "컬러")
                        statusLabel.stringValue = uploaded.owned.display.automaticWindow ? "자동 대비" : "파일 대비"
                        limitationLabel.stringValue = limitations(uploaded.owned.display)
                        limitationLabel.toolTip = limitationLabel.stringValue
                        populateControls(); setControlsEnabled(true)
                    }
                    stateHistory.record(PresentedViewState(window: selectedWindow, inverted: userInvert, zoom: zoomMultiplier,
                                                           pan: pan, generation: generation), requestGeneration: requestGeneration)
                    if firstPresentation { presentationObserver?(true, generation, uploaded.owned.info) }
                }
            }
        } catch { fail(error: error, generation: requestGeneration) }
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { requestDraw() }
    private func populateControls() {
        windows.removeAllItems(); windows.addItem(withTitle: "기본 대비")
        if let uploaded {
            for (index, item) in uploaded.owned.display.windows.enumerated() { windows.addItem(withTitle: "대비 \(index + 1) · \(item.center) / \(item.width)") }
            if !sameWindow(selectedWindow, uploaded.owned.display.defaultWindow) {
                if let index = uploaded.owned.display.windows.firstIndex(where: { sameWindow($0, selectedWindow) }) {
                    windows.selectItem(at: index + 1)
                } else { windows.addItem(withTitle: "사용자 대비"); windows.selectItem(at: windows.numberOfItems - 1) }
            }
        }
        centerField.stringValue = selectedWindow.map { String($0.center) } ?? ""
        widthField.stringValue = selectedWindow.map { String($0.width) } ?? ""
        invertButton.state = userInvert ? .on : .off
    }
    private func sameWindow(_ lhs: VoiWindow?, _ rhs: VoiWindow?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return lhs.center == rhs.center && lhs.width == rhs.width && lhs.function == rhs.function
    }
    private func limitations(_ display: FrameDisplayInfo) -> String {
        let messages = ["overlay_not_applied": "오버레이 표시 안 함", "shutter_not_applied": "셔터 적용 안 함",
                        "display_aspect_assumed_square": "정방형 픽셀 가정", "display_aspect_conflict": "픽셀 비율 정보 불일치",
                        "unprofiled_rgb": "색 프로파일 미적용", "no_valid_pixels": "유효 픽셀 없음"]
        var text: [String] = []
        for code in display.diagnostics {
            if code == "unit_unknown" || code == "automatic_voi_from_display_range" { continue }
            let message = messages[code] ?? (code.hasPrefix("invalid_") && (code.contains("spacing") || code.contains("aspect"))
                                           ? "픽셀 비율 정보 오류" : "표시 제한 있음")
            if !text.contains(message) { text.append(message) }
        }
        if display.aspectEstimated && !text.contains("정방형 픽셀 가정") { text.append("정방형 픽셀 가정") }
        text.append(display.unit == "HU" ? "단위: HU" : "단위 정보 없음")
        return text.joined(separator: "\n")
    }
    private func setControlsEnabled(_ enabled: Bool) {
        let gray = enabled && !loading && uploaded?.owned.display.canWindow == true
        [windows, centerField, widthField, invertButton].forEach { $0.isEnabled = gray }
        fitButton.isEnabled = enabled
    }
    @objc private func chooseWindow(_ sender: Any?) {
        guard let uploaded else { return }
        let index = windows.indexOfSelectedItem
        guard index <= uploaded.owned.display.windows.count else { populateControls(); return }
        selectedWindow = index == 0 ? uploaded.owned.display.defaultWindow : uploaded.owned.display.windows[index - 1]
        statusLabel.stringValue = index == 0 && uploaded.owned.display.automaticWindow ? "자동 대비" : "파일 대비"
        populateControls(); requestDraw()
    }
    @objc private func editWindow(_ sender: Any?) {
        guard let selectedWindow, let center = Double(centerField.stringValue), let width = Double(widthField.stringValue),
              center.isFinite, width.isFinite, width > 0, selectedWindow.function != .linear || width >= 1 else {
            statusLabel.stringValue = "중심과 폭에 올바른 숫자를 입력해 주세요."; return
        }
        self.selectedWindow = VoiWindow(center: center, width: width, function: selectedWindow.function)
        statusLabel.stringValue = "사용자 대비"; populateControls(); requestDraw()
    }
    @objc private func invert(_ sender: Any?) { userInvert = invertButton.state == .on; requestDraw() }
    @objc private func fit(_ sender: Any?) { zoomMultiplier = 1; pan = .zero; requestDraw() }
    @objc private func retry(_ sender: Any?) { if let requestedPath { load(path: requestedPath) } }
    private func move(dx: Double, dy: Double) {
        guard !loading, let mapping = try? transform() else { return }
        pan = PixelPoint2D(x: pan.x + dx / mapping.zoom, y: pan.y + dy / (mapping.zoom * mapping.aspect)); requestDraw()
    }
    private func zoom(factor: Double, around point: PixelPoint2D) {
        guard !loading, factor > 0, let old = try? transform() else { return }
        let source = old.screenToSource(point); zoomMultiplier = min(100, max(0.05, zoomMultiplier * factor))
        if let next = try? transform() { let moved = next.screenToSource(point); pan = PixelPoint2D(x: pan.x + moved.x - source.x, y: pan.y + moved.y - source.y) }
        requestDraw()
    }
    private func setupContent() {
        let root = NSView(); window.contentView = root
        let sidebar = NSView(), main = NSView(), divider = NSBox(); divider.boxType = .separator
        [sidebar, main, divider].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; root.addSubview($0) }
        let sidebarTitle = NSTextField(labelWithString: "검사 목록"); sidebarTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        let sidebarInfo = NSTextField(wrappingLabelWithString: "현재는 단일 영상 파일을 열 수 있습니다."); sidebarInfo.textColor = .secondaryLabelColor
        limitationLabel.textColor = .secondaryLabelColor
        [sidebarTitle, sidebarInfo, imageLabel, limitationLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview($0) }
        let controls = NSStackView(); controls.orientation = .horizontal; controls.spacing = 10
        [openButton, windows, centerField, widthField, invertButton, fitButton].forEach { controls.addArrangedSubview($0) }
        centerField.placeholderString = "중심"; widthField.placeholderString = "폭"
        centerField.toolTip = "대비 중심"; widthField.toolTip = "대비 폭"
        centerField.setAccessibilityLabel("대비 중심"); widthField.setAccessibilityLabel("대비 폭")
        centerField.widthAnchor.constraint(equalToConstant: 85).isActive = true; widthField.widthAnchor.constraint(equalToConstant: 85).isActive = true
        windows.widthAnchor.constraint(equalToConstant: 170).isActive = true
        windows.target = self; windows.action = #selector(chooseWindow(_:)); centerField.target = self; centerField.action = #selector(editWindow(_:))
        widthField.target = self; widthField.action = #selector(editWindow(_:)); invertButton.target = self; invertButton.action = #selector(invert(_:))
        fitButton.target = self; fitButton.action = #selector(fit(_:)); retryButton.target = self; retryButton.action = #selector(retry(_:)); retryButton.isHidden = true
        [controls, metalView, statusLabel, retryButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; main.addSubview($0) }
        [emptyLabel, loadingLabel].forEach { $0.textColor = .white; $0.alignment = .center; $0.maximumNumberOfLines = 0; $0.translatesAutoresizingMaskIntoConstraints = false; metalView.addSubview($0) }
        loadingLabel.isHidden = true; statusLabel.lineBreakMode = .byTruncatingTail
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor), sidebar.topAnchor.constraint(equalTo: root.topAnchor), sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor), sidebar.widthAnchor.constraint(equalToConstant: 210),
            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor), divider.widthAnchor.constraint(equalToConstant: 1), divider.topAnchor.constraint(equalTo: root.topAnchor), divider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            main.leadingAnchor.constraint(equalTo: divider.trailingAnchor), main.trailingAnchor.constraint(equalTo: root.trailingAnchor), main.topAnchor.constraint(equalTo: root.topAnchor), main.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebarTitle.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18), sidebarTitle.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 22),
            sidebarInfo.leadingAnchor.constraint(equalTo: sidebarTitle.leadingAnchor), sidebarInfo.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -18), sidebarInfo.topAnchor.constraint(equalTo: sidebarTitle.bottomAnchor, constant: 20),
            imageLabel.leadingAnchor.constraint(equalTo: sidebarTitle.leadingAnchor), imageLabel.topAnchor.constraint(equalTo: sidebarInfo.bottomAnchor, constant: 20),
            limitationLabel.leadingAnchor.constraint(equalTo: sidebarTitle.leadingAnchor), limitationLabel.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -18), limitationLabel.topAnchor.constraint(equalTo: imageLabel.bottomAnchor, constant: 20),
            controls.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 16), controls.topAnchor.constraint(equalTo: main.topAnchor, constant: 16), controls.trailingAnchor.constraint(lessThanOrEqualTo: main.trailingAnchor, constant: -16),
            metalView.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 16), metalView.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -16), metalView.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 16), metalView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -14),
            statusLabel.leadingAnchor.constraint(equalTo: metalView.leadingAnchor), statusLabel.bottomAnchor.constraint(equalTo: main.bottomAnchor, constant: -16), statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: retryButton.leadingAnchor, constant: -8),
            retryButton.trailingAnchor.constraint(equalTo: metalView.trailingAnchor), retryButton.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: metalView.centerXAnchor), emptyLabel.centerYAnchor.constraint(equalTo: metalView.centerYAnchor),
            loadingLabel.centerXAnchor.constraint(equalTo: metalView.centerXAnchor), loadingLabel.topAnchor.constraint(equalTo: metalView.topAnchor, constant: 14)
        ])
    }
}

private struct DisplayTrace: Encodable {
    let event: String
    let generation: UInt64
    let revision: UInt64
    let loading: Bool
    let submitted: UInt64
    let gpuCompleted: UInt64
    let actuallyPresented: UInt64
}

@MainActor
private final class FrameMetalView: MTKView {
    override var isFlipped: Bool { true }
    var onPan: ((Double, Double) -> Void)?
    var onZoom: ((Double, PixelPoint2D) -> Void)?
    var onFit: (() -> Void)?
    private var previous: NSPoint?
    override func mouseDown(with event: NSEvent) { if event.clickCount == 2 { onFit?(); return }; previous = convert(event.locationInWindow, from: nil) }
    override func mouseDragged(with event: NSEvent) { let next = convert(event.locationInWindow, from: nil); if let previous { onPan?(next.x - previous.x, next.y - previous.y) }; previous = next }
    override func mouseUp(with event: NSEvent) { previous = nil }
    override func scrollWheel(with event: NSEvent) { let p = convert(event.locationInWindow, from: nil); onZoom?(exp(-event.scrollingDeltaY * 0.01), PixelPoint2D(x: p.x, y: p.y)) }
    override func magnify(with event: NSEvent) { let p = convert(event.locationInWindow, from: nil); onZoom?(1 + event.magnification, PixelPoint2D(x: p.x, y: p.y)) }
}
