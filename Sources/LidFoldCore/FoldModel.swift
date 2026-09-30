import Foundation

/// Thresholds and look parameters. The defaults are what ships. The environment variables exist so the
/// fold can be reproduced without touching the lid.
struct FoldConfiguration: Equatable {
    /// The fold starts when the lid is at or below this angle, in degrees.
    var armBelow = 88.0
    /// The overlay is removed above this angle. The effect never runs above 90 degrees.
    var disarmAbove = 90.0
    /// The fold is complete at this angle.
    var closedAngle = 5.0
    /// Below this the lid is shut for practical purposes and the overlay steps aside.
    var minVisibleAngle = 3.0
    var progressOverride: Double?
    var tiltOverride: Double?
    /// Viewing distance in points. Shorter means a harder perspective and more void.
    var eyeDistance = 3000.0
    /// How far the content swings per degree of lid travel.
    var swing = 0.55

    init() {}

    init(environment: [String: String]) {
        func number(_ key: String) -> Double? { environment[key].flatMap(Double.init) }
        armBelow = number("LIDFOLD_ARM") ?? armBelow
        disarmAbove = number("LIDFOLD_DISARM") ?? disarmAbove
        progressOverride = number("LIDFOLD_PROGRESS")
        tiltOverride = number("LIDFOLD_TILT")
        eyeDistance = number("LIDFOLD_EYE_Z") ?? eyeDistance
        swing = number("LIDFOLD_SWING") ?? swing
    }

    static let current = FoldConfiguration(environment: ProcessInfo.processInfo.environment)
}

enum FoldPresentation: Equatable {
    case hidden
    case fold(progress: Double, tiltDegrees: Double)
}

/// Everything the overlay draws at one moment, derived from a fold amount and a tilt.
struct FoldFrame: Equatable {
    /// `progress` eased with smoothstep. Drives darkening, glass and reflection.
    var motion: Double
    /// Drives the blur. Leads `motion` over the first two thirds of the fold.
    var frost: Double
    var blurRadius: Double
    /// Black overlay alpha at each gradient stop, from the far edge down to the hinge.
    var darkness: [Double]
    var glassOpacity: Double
    var reflectionOpacity: Double
    /// Rotation of the picture about the hinge, negative swings the far edge away from the viewer.
    var rotationRadians: Double
    /// Core Animation `m34`.
    var perspective: Double
}

enum FoldModel {
    static let maxBlurRadius = 96.0
    static let frostExponent = 0.7
    static let darknessStops = 6
    static let darknessStopSpacing = 0.2
    /// Distance from the hinge, as a fraction of the panel, below which nothing is darkened.
    static let darknessStart = 0.2
    static let darknessSpan = 0.8
    static let darknessExponent = 1.35
    static let darknessGain = 1.5
    static let blurMaskExponent = 1.35
    static let glassOpacityAtFullFold = 0.20
    static let reflectionOpacityAtFullFold = 0.06

    /// Lid angle to what the overlay should do. The fold runs from `armBelow` (progress 0) to
    /// `closedAngle` (progress 1). The overlay itself exists from `disarmAbove` down to
    /// `minVisibleAngle`, so between `armBelow` and `disarmAbove` it shows the frozen picture
    /// unchanged.
    static func presentation(angle: Double, configuration: FoldConfiguration) -> FoldPresentation {
        if angle > configuration.disarmAbove || angle < configuration.minVisibleAngle { return .hidden }
        let span = configuration.armBelow - configuration.closedAngle
        let tracked = min(max((configuration.armBelow - angle) / span, 0), 1)
        let tilt = max(0, configuration.armBelow - angle)
        return .fold(
            progress: configuration.progressOverride ?? tracked,
            tiltDegrees: configuration.tiltOverride ?? tilt
        )
    }

    static func smoothstep(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    static func frame(
        progress: Double,
        tiltDegrees: Double,
        configuration: FoldConfiguration
    ) -> FoldFrame {
        let motion = smoothstep(progress)
        // Frost leads the geometry: it is the first thing the eye reads, and the fold looks empty
        // if the picture is still crisp once the panel has visibly moved.
        let frost = pow(progress, frostExponent)
        let darkness = (0..<darknessStops).map { step -> Double in
            let fromHinge = 1 - Double(step) * darknessStopSpacing
            let gradient = max(0, min(1, (fromHinge - darknessStart) / darknessSpan))
            return min(1, motion * pow(gradient, darknessExponent) * darknessGain)
        }
        return FoldFrame(
            motion: motion,
            frost: frost,
            blurRadius: maxBlurRadius * frost,
            darkness: darkness,
            glassOpacity: glassOpacityAtFullFold * motion,
            reflectionOpacity: reflectionOpacityAtFullFold * motion,
            rotationRadians: -configuration.swing * tiltDegrees * .pi / 180,
            perspective: -1 / configuration.eyeDistance
        )
    }

    /// Alpha of one row of the blur mask, 8 bits. Row 0 is the far edge (alpha 255), the last row is the hinge
    /// (alpha 0). `variableBlur` reads this alpha, not luminance.
    static func blurMaskByte(row: Int, rows: Int) -> UInt8 {
        let fromHinge = 1 - Double(row) / Double(rows - 1)
        return UInt8(max(0, min(255, pow(fromHinge, blurMaskExponent) * 255)))
    }

    /// Where the swung picture lands, as fractions of the panel: the width of its far edge against the width
    /// at the hinge, and the height of its far edge above the hinge. Pure perspective geometry of the same
    /// transform the view applies, with the vanishing point at the hinge.
    static func silhouette(
        tiltDegrees: Double,
        panelHeight: Double,
        configuration: FoldConfiguration
    ) -> (farEdgeWidth: Double, farEdgeHeight: Double) {
        let rotation = configuration.swing * tiltDegrees * .pi / 180
        let scale = 1 / (1 + panelHeight * sin(rotation) / configuration.eyeDistance)
        return (scale, cos(rotation) * scale)
    }
}
