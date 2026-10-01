import Foundation
internal import ViewerBindings

public enum VoiFunction: String, Sendable {
    case linear, linearExact, sigmoid
}
public struct VoiWindow: Sendable {
    public let center: Double
    public let width: Double
    public let function: VoiFunction
    public init(center: Double, width: Double, function: VoiFunction) {
        self.center = center; self.width = width; self.function = function
    }
    internal init(_ raw: ViewerBindings.VoiWindow) {
        center = raw.center; width = raw.width
        switch raw.function {
        case .linear: function = .linear
        case .linearExact: function = .linearExact
        case .sigmoid: function = .sigmoid
        }
    }
    internal var raw: ViewerBindings.VoiWindow {
        let kind: ViewerBindings.VoiFunction
        switch function {
        case .linear: kind = .linear
        case .linearExact: kind = .linearExact
        case .sigmoid: kind = .sigmoid
        }
        return ViewerBindings.VoiWindow(center: center, width: width, function: kind)
    }
    public var isValid: Bool {
        center.isFinite && width.isFinite && (function == .linear ? width >= 1 : width > 0)
    }
}

/// DISPLAY-1: Rust interpretation, immutable and tied to exact opened file bytes.
/// The aspect ratio conveys display shape; it grants no physical measurement capability.
public struct FrameDisplayInfo: Sendable {
    public let descriptorRevision: UInt32
    public let sourceRevision: String
    public let frameIndex: UInt32
    public let windows: [VoiWindow]
    public let defaultWindow: VoiWindow?
    public let automaticWindow: Bool
    public let inverted: Bool
    public let pixelHeightOverWidth: Double
    public let aspectSource: String
    public let aspectEstimated: Bool
    public let unit: String
    public let diagnostics: [String]
    public let canWindow: Bool

    internal init(_ raw: DisplayInfo) {
        descriptorRevision = raw.descriptorRevision; sourceRevision = raw.sourceRevision
        frameIndex = raw.frameIndex; windows = raw.windows.map(VoiWindow.init)
        defaultWindow = raw.defaultWindow.map(VoiWindow.init)
        automaticWindow = raw.automaticWindow; inverted = raw.inverted
        pixelHeightOverWidth = raw.pixelHeightOverWidth
        aspectSource = raw.aspectSource; aspectEstimated = raw.aspectEstimated
        unit = raw.unit; diagnostics = raw.diagnostics; canWindow = raw.canWindow
    }
    internal func validate(format: PixelBufferFormat) throws {
        guard descriptorRevision == 1, frameIndex == 0,
              sourceRevision.utf8.count == 64,
              sourceRevision.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              pixelHeightOverWidth.isFinite, pixelHeightOverWidth > 0,
              windows.allSatisfy(\.isValid), defaultWindow?.isValid != false else {
            throw ViewerPixelError.invalidContract(reason: "invalid display descriptor")
        }
        if format == .rgba8 {
            guard !canWindow, windows.isEmpty, defaultWindow == nil, !inverted else {
                throw ViewerPixelError.invalidContract(reason: "color has grayscale display settings")
            }
        } else if canWindow && defaultWindow == nil {
            throw ViewerPixelError.invalidContract(reason: "window capability lacks a default")
        }
    }
}
