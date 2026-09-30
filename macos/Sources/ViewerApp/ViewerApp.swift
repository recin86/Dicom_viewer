import AppKit
import Darwin
import ViewerBridge

@main
@MainActor
struct ViewerApp {
    static func main() {
        let arguments = Set(CommandLine.arguments.dropFirst())
        let headlessSmoke = arguments.contains("--smoke-test")
        let uiSmoke = arguments.contains("--ui-smoke-test")

        guard !(headlessSmoke && uiSmoke) else {
            SmokeOutput.write(LaunchFailure(reason: "conflicting_smoke_options"))
            exit(1)
        }

        // BOOTSTRAP-1 performs no file I/O or decoding. Heavy core work must use
        // a separate background execution path when file opening is implemented.
        let readiness = ViewerBridge.readiness()
        let bootstrap = BootstrapReport(readiness: readiness)
        if let failure = bootstrap.validationFailure {
            SmokeOutput.write(BootstrapFailure(bootstrap: bootstrap, reason: failure))
            exit(1)
        }

        if headlessSmoke {
            SmokeOutput.write(bootstrap)
            return
        }

        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let delegate = AppDelegate(readiness: readiness, uiSmoke: uiSmoke)
        application.delegate = delegate
        application.run()

        // Keep the delegate alive for the entire native event loop.
        withExtendedLifetime(delegate) {}
        if uiSmoke && !delegate.didEmitUISmokeReport {
            SmokeOutput.write(LaunchFailure(reason: "event_loop_ended_without_ui_result"))
            exit(1)
        }
    }
}
