// swift-tools-version:5.9
// P0-FFI experiment package. Built with Command Line Tools only (no Xcode).
// The generated UniFFI files and libp0ffi.a are placed here by ../run.sh.
import PackageDescription

let libDir = Context.packageDirectory + "/lib"

let package = Package(
    name: "P0Bench",
    platforms: [.macOS(.v14)],
    targets: [
        // C module exposing the generated FFI header (p0ffiFFI.h + module.modulemap).
        .target(name: "p0ffiFFI", path: "Sources/p0ffiFFI"),
        .executableTarget(
            name: "P0Bench",
            dependencies: ["p0ffiFFI"],
            path: "Sources/P0Bench",
            linkerSettings: [
                .unsafeFlags(["-L", libDir]),
                .linkedLibrary("p0ffi"),
            ]
        ),
    ]
)
