import Foundation
import ViewerBridge

public struct PixelPoint2D: Sendable, Equatable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public static let zero = PixelPoint2D(x: 0, y: 0)
}

/// Screen coordinates are top-left macOS points. Pan is in original pixels.
/// Backing scale affects raster resolution, not source or physical coordinates.
public struct ViewportTransform: Sendable {
    public let width: Double
    public let height: Double
    public let aspect: Double
    public let viewWidth: Double
    public let viewHeight: Double
    public let zoom: Double
    public let pan: PixelPoint2D

    public init(width: UInt32, height: UInt32, aspect: Double,
                viewWidth: Double, viewHeight: Double,
                zoom: Double? = nil, pan: PixelPoint2D = .zero) throws {
        guard width > 0, height > 0, aspect.isFinite, aspect > 0,
              viewWidth.isFinite, viewHeight.isFinite, viewWidth > 0, viewHeight > 0,
              pan.x.isFinite, pan.y.isFinite else { throw RenderingError.invalidDisplay }
        self.width = Double(width); self.height = Double(height); self.aspect = aspect
        self.viewWidth = viewWidth; self.viewHeight = viewHeight; self.pan = pan
        self.zoom = zoom ?? min(viewWidth / Double(width), viewHeight / (Double(height) * aspect))
        guard self.zoom.isFinite, self.zoom > 0 else { throw RenderingError.invalidDisplay }
    }

    public func sourceToScreen(_ point: PixelPoint2D) -> PixelPoint2D {
        PixelPoint2D(x: viewWidth / 2 + zoom * (point.x - (width - 1) / 2 + pan.x),
                     y: viewHeight / 2 + zoom * aspect * (point.y - (height - 1) / 2 + pan.y))
    }

    public func screenToSource(_ point: PixelPoint2D) -> PixelPoint2D {
        PixelPoint2D(x: (point.x - viewWidth / 2) / zoom + (width - 1) / 2 - pan.x,
                     y: (point.y - viewHeight / 2) / (zoom * aspect) + (height - 1) / 2 - pan.y)
    }

    public func backingPixelToSource(_ point: PixelPoint2D, scale: Double) throws -> PixelPoint2D {
        guard scale.isFinite, scale > 0 else { throw RenderingError.invalidDisplay }
        return screenToSource(PixelPoint2D(x: point.x / scale, y: point.y / scale))
    }
}

/// The actual UI and integration checks use the same generation acceptance rule.
@MainActor
public final class DisplayGenerationGate {
    public private(set) var current: UInt64 = 0
    public init() {}
    @discardableResult public func begin() -> UInt64 {
        precondition(current < UInt64.max, "display generation exhausted")
        current += 1
        return current
    }
    public func accepts(_ generation: UInt64) -> Bool { current == generation }
    @discardableResult public func installIfCurrent(_ generation: UInt64, _ install: () -> Void) -> Bool {
        guard accepts(generation) else { return false }
        install()
        return true
    }
}

public struct PresentedViewState: Sendable {
    public let window: VoiWindow?
    public let inverted: Bool
    public let zoom: Double
    public let pan: PixelPoint2D
    public let generation: UInt64
    public init(window: VoiWindow?, inverted: Bool, zoom: Double, pan: PixelPoint2D, generation: UInt64) {
        self.window = window; self.inverted = inverted; self.zoom = zoom; self.pan = pan; self.generation = generation
    }
}

/// Save the whole state only after accepted presentation. A failed candidate
/// cannot replace it, and a stale failure cannot restore over a newer request.
@MainActor
public final class PresentedStateHistory {
    private let gate: DisplayGenerationGate
    private var saved: PresentedViewState?
    public init(gate: DisplayGenerationGate) { self.gate = gate }
    @discardableResult public func record(_ state: PresentedViewState, requestGeneration: UInt64) -> Bool {
        guard gate.accepts(requestGeneration) else { return false }
        saved = state; return true
    }
    public func restoration(forFailedGeneration generation: UInt64) -> PresentedViewState? {
        guard gate.accepts(generation) else { return nil }
        return saved
    }
}
