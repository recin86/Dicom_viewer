// swift-tools-version:5.9
// P0-FFI-CONTRACT consumer. Built with Command Line Tools only (no Xcode).
// Generated UniFFI files, the copied C header and libp0contract.a are placed here by ../run.sh.
import PackageDescription

let libDir = Context.packageDirectory + "/lib"

let package = Package(
    name: "P0ContractCheck",
    platforms: [.macOS(.v14)],
    targets: [
        // Generated UniFFI header (p0contractFFI.h + module.modulemap).
        .target(name: "p0contractFFI", path: "Sources/p0contractFFI"),
        // Hand-written typed copy bridge (copied from ../include/p0_contract_copy.h).
        .target(name: "P0ContractCopy", path: "Sources/P0ContractCopy"),
        .executableTarget(
            name: "P0ContractCheck",
            dependencies: ["p0contractFFI", "P0ContractCopy"],
            path: "Sources/P0ContractCheck",
            linkerSettings: [
                .unsafeFlags(["-L", libDir]),
                .linkedLibrary("p0contract"),
                .linkedFramework("Metal"),
            ]
        ),
    ]
)
