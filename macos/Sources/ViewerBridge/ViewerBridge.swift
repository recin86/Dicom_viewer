internal import ViewerBindings

/// Bootstrap identity. This is not a modality or transfer-syntax capability list.
public struct ViewerReadiness: Sendable {
    public let apiRevision: UInt32
    public let coreVersion: String
    public let dicomRSVersion: String
    public let canOpenDicom: Bool
}

/// Generated bindings stay behind this module. Pixel handles and typed copies
/// will be added with the product memory/lifetime contract in the next task.
public enum ViewerBridge {
    public static func readiness() -> ViewerReadiness {
        let info = bootstrapInfo()
        return ViewerReadiness(
            apiRevision: info.apiRevision,
            coreVersion: info.coreVersion,
            dicomRSVersion: info.dicomRsVersion,
            canOpenDicom: info.frameDecodeImplemented
        )
    }
}
