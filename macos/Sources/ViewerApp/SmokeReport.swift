import Darwin
import Foundation
import ViewerBridge

struct BootstrapReport: Encodable {
    let apiRevision: UInt32
    let coreVersion: String
    let dicomRSVersion: String
    let frameDecodeImplemented: Bool

    init(readiness: ViewerReadiness) {
        apiRevision = readiness.apiRevision
        coreVersion = readiness.coreVersion
        dicomRSVersion = readiness.dicomRSVersion
        frameDecodeImplemented = readiness.canOpenDicom
    }

    var validationFailure: String? {
        guard apiRevision == 1 else { return "unexpected_api_revision" }
        guard !coreVersion.isEmpty else { return "missing_core_version" }
        guard dicomRSVersion == "0.10.0" else { return "unexpected_dicom_rs_version" }
        // This shell has no file-opening implementation. A new capability needs
        // its consumer implementation before a future contract can enable it.
        guard !frameDecodeImplemented else { return "unexpected_open_capability" }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case apiRevision = "api_revision"
        case coreVersion = "core_version"
        case dicomRSVersion = "dicom_rs_version"
        case frameDecodeImplemented = "frame_decode_implemented"
    }
}

struct BootstrapFailure: Encodable {
    let bootstrap: BootstrapReport
    let reason: String
    let status = "fail"
}

struct LaunchFailure: Encodable {
    let reason: String
    let status = "fail"
}

struct UISmokeReport: Encodable {
    let bootstrap: BootstrapReport
    let windowVisible: Bool
    let hasAppMenu: Bool
    let hasFileMenu: Bool
    let hasWindowMenu: Bool
    let openCommandEnabled: Bool
    let openButtonEnabled: Bool
    let quitKeyEquivalent: String
    let quitUsesCommandModifier: Bool
    let quitActionIsTerminate: Bool
    let eventLoopRan: Bool
    var lastWindowCloseTriggeredTermination = false

    var passed: Bool {
        bootstrap.validationFailure == nil
            && windowVisible && hasAppMenu && hasFileMenu && hasWindowMenu
            && !openCommandEnabled && !openButtonEnabled
            && quitKeyEquivalent == "q" && quitUsesCommandModifier
            && quitActionIsTerminate && eventLoopRan
            && lastWindowCloseTriggeredTermination
    }

    enum CodingKeys: String, CodingKey {
        case bootstrap
        case windowVisible = "window_visible"
        case hasAppMenu = "has_app_menu"
        case hasFileMenu = "has_file_menu"
        case hasWindowMenu = "has_window_menu"
        case openCommandEnabled = "open_command_enabled"
        case openButtonEnabled = "open_button_enabled"
        case quitKeyEquivalent = "quit_key_equivalent"
        case quitUsesCommandModifier = "quit_uses_command_modifier"
        case quitActionIsTerminate = "quit_action_is_terminate"
        case eventLoopRan = "event_loop_ran"
        case lastWindowCloseTriggeredTermination = "last_window_close_triggered_termination"
        case passed
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bootstrap, forKey: .bootstrap)
        try container.encode(windowVisible, forKey: .windowVisible)
        try container.encode(hasAppMenu, forKey: .hasAppMenu)
        try container.encode(hasFileMenu, forKey: .hasFileMenu)
        try container.encode(hasWindowMenu, forKey: .hasWindowMenu)
        try container.encode(openCommandEnabled, forKey: .openCommandEnabled)
        try container.encode(openButtonEnabled, forKey: .openButtonEnabled)
        try container.encode(quitKeyEquivalent, forKey: .quitKeyEquivalent)
        try container.encode(quitUsesCommandModifier, forKey: .quitUsesCommandModifier)
        try container.encode(quitActionIsTerminate, forKey: .quitActionIsTerminate)
        try container.encode(eventLoopRan, forKey: .eventLoopRan)
        try container.encode(lastWindowCloseTriggeredTermination, forKey: .lastWindowCloseTriggeredTermination)
        try container.encode(passed, forKey: .passed)
    }
}

enum SmokeOutput {
    static func write(_ report: some Encodable) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(report)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([0x0A]))
        } catch {
            FileHandle.standardError.write(Data("Unable to encode smoke result.\n".utf8))
            exit(1)
        }
    }
}
