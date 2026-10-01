import AppKit
import Darwin
import ViewerBridge

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let readiness: ViewerReadiness
    private let uiSmoke: Bool
    private let initialPath: String?
    private let displaySmoke: Bool
    private var pendingDisplayReport: DisplaySmokeReport?
    private var viewerWindow: ViewerWindow?
    private var openMenuItem: NSMenuItem?
    private var quitMenuItem: NSMenuItem?
    private var pendingUISmokeReport: UISmokeReport?
    private var requestedSmokeClose = false
    private var lastWindowPolicyConsulted = false
    private var launchDate: Date?
    private(set) var didEmitUISmokeReport = false

    init(readiness: ViewerReadiness, uiSmoke: Bool, initialPath: String? = nil, displaySmoke: Bool = false) {
        self.readiness = readiness
        self.uiSmoke = uiSmoke
        self.initialPath = initialPath
        self.displaySmoke = displaySmoke
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchDate = Date()
        let viewerWindow = ViewerWindow(readiness: readiness)
        self.viewerWindow = viewerWindow
        installMenus(window: viewerWindow.window)
        viewerWindow.window.center()
        viewerWindow.window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()

        if displaySmoke {
            viewerWindow.presentationObserver = { [weak self] success, generation, info in
                guard let self, pendingDisplayReport == nil else { return }
                pendingDisplayReport = DisplaySmokeReport(passed: success, generation: generation,
                                                          presentation: success, width: info?.width, height: info?.height)
                requestedSmokeClose = true
                viewerWindow.window.performClose(nil)
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(20))
                guard let self, !didEmitUISmokeReport else { return }
                SmokeOutput.write(LaunchFailure(reason: "presentation_timeout")); exit(1)
            }
        }
        if let initialPath { viewerWindow.load(path: initialPath) }

        if uiSmoke {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                self?.beginUISmokeClose()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        lastWindowPolicyConsulted = true
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if displaySmoke {
            guard var report = pendingDisplayReport else {
                SmokeOutput.write(LaunchFailure(reason: "display_terminated_before_observation")); exit(1)
            }
            report.lastWindowCloseTriggeredTermination = requestedSmokeClose && lastWindowPolicyConsulted
            report.passed = report.passed && report.lastWindowCloseTriggeredTermination
            didEmitUISmokeReport = true
            SmokeOutput.write(report)
            if !report.passed { exit(1) }
            return
        }
        guard uiSmoke else { return }
        guard var report = pendingUISmokeReport else {
            didEmitUISmokeReport = true
            SmokeOutput.write(LaunchFailure(reason: "ui_terminated_before_observation"))
            exit(1)
        }
        report.lastWindowCloseTriggeredTermination = requestedSmokeClose && lastWindowPolicyConsulted
        didEmitUISmokeReport = true
        pendingUISmokeReport = nil
        SmokeOutput.write(report)
        if !report.passed { exit(1) }
    }

    private func installMenus(window: NSWindow) {
        let application = NSApplication.shared
        let mainMenu = NSMenu()

        let appMenu = NSMenu(title: "DICOM Viewer")
        appMenu.addItem(withTitle: "DICOM Viewer 정보", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "DICOM Viewer 가리기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "기타 가리기", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "모두 보기", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let quit = appMenu.addItem(withTitle: "DICOM Viewer 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        quitMenuItem = quit
        addSubmenu(appMenu, to: mainMenu)

        let fileMenu = NSMenu(title: "파일")
        fileMenu.autoenablesItems = false
        let open = fileMenu.addItem(withTitle: "열기…", action: #selector(ViewerWindow.openFile(_:)), keyEquivalent: "o")
        open.target = viewerWindow
        open.keyEquivalentModifierMask = [.command]
        open.isEnabled = ViewerBridge.nativeDisplayAvailable()
        open.toolTip = "단일 영상 파일 열기"
        openMenuItem = open
        fileMenu.addItem(.separator())
        let close = fileMenu.addItem(withTitle: "창 닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        close.target = window
        close.keyEquivalentModifierMask = [.command]
        addSubmenu(fileMenu, to: mainMenu)

        let windowMenu = NSMenu(title: "윈도우")
        windowMenu.addItem(withTitle: "최소화", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "확대/축소", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "모두 앞으로 가져오기", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        addSubmenu(windowMenu, to: mainMenu)
        application.windowsMenu = windowMenu
        application.mainMenu = mainMenu
    }

    private func addSubmenu(_ submenu: NSMenu, to menu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    private func beginUISmokeClose() {
        guard let viewerWindow else {
            SmokeOutput.write(LaunchFailure(reason: "missing_window"))
            exit(1)
        }
        let application = NSApplication.shared
        let mainMenu = application.mainMenu
        pendingUISmokeReport = UISmokeReport(
            bootstrap: BootstrapReport(readiness: readiness),
            windowVisible: viewerWindow.window.isVisible,
            hasAppMenu: mainMenu?.item(withTitle: "DICOM Viewer")?.submenu != nil,
            hasFileMenu: mainMenu?.item(withTitle: "파일")?.submenu != nil,
            hasWindowMenu: application.windowsMenu != nil,
            openCommandEnabled: openMenuItem?.isEnabled ?? true,
            openButtonEnabled: viewerWindow.openButton.isEnabled,
            quitKeyEquivalent: quitMenuItem?.keyEquivalent ?? "",
            quitUsesCommandModifier: quitMenuItem?.keyEquivalentModifierMask == [.command],
            quitActionIsTerminate: quitMenuItem?.action == #selector(NSApplication.terminate(_:)),
            eventLoopRan: launchDate.map { Date().timeIntervalSince($0) >= 0.3 } ?? false
        )
        requestedSmokeClose = true
        // Closing the actual final window must invoke AppKit's termination policy.
        // A fallback only reports failure if that path never terminates the app.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, let report = self.pendingUISmokeReport else { return }
            self.didEmitUISmokeReport = true
            SmokeOutput.write(report)
            exit(1)
        }
        viewerWindow.window.performClose(nil)
    }
}
