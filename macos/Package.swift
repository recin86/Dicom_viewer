// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DicomViewer",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "ViewerApp", targets: ["ViewerApp"]),
        .executable(name: "ViewerContractChecks", targets: ["ViewerContractChecks"]),
        .executable(name: "ViewerDisplayChecks", targets: ["ViewerDisplayChecks"]),
        .executable(name: "ViewerColorChecks", targets: ["ViewerColorChecks"]),
    ],
    targets: [
        .target(name: "viewer_ffiFFI", path: "Sources/viewer_ffiFFI"),
        .target(name: "ViewerPixelCopy", path: "Sources/ViewerPixelCopy"),
        .target(
            name: "ViewerBindings",
            dependencies: ["viewer_ffiFFI"],
            path: "Sources/ViewerBindings",
            linkerSettings: [
                .unsafeFlags(["-L", Context.packageDirectory + "/lib"]),
                .linkedLibrary("viewer_ffi"),
                .linkedLibrary("c++"),
                .linkedLibrary("z"),
            ]
        ),
        .target(name: "ViewerBridge", dependencies: ["ViewerBindings", "ViewerPixelCopy"]),
        .target(
            name: "ViewerRendering", dependencies: ["ViewerBridge"],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("Metal"), .linkedFramework("MetalKit")]
        ),
        .executableTarget(name: "ViewerContractChecks", dependencies: ["ViewerBridge"]),
        .executableTarget(name: "ViewerDisplayChecks", dependencies: ["ViewerBridge", "ViewerRendering"]),
        .executableTarget(name: "ViewerColorChecks", dependencies: ["ViewerBridge", "ViewerRendering"]),
        .executableTarget(
            name: "ViewerApp",
            dependencies: ["ViewerBridge", "ViewerRendering"],
            linkerSettings: [.linkedFramework("AppKit")]
        ),
    ]
)
