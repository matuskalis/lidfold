import AppKit

/// The iPhone Duo fold: the desktop stays standing in space at the angle where the fold armed
/// while the panel closes away from it. The panel is a window onto that standing image, so the
/// content counter-rotates against the lid — which reads as magnification toward the hinge plus
/// keystone widening at the far edge. Progressive blur and darkening ride on top.
final class FoldOverlayView: NSView {
    private static let maxBlurRadius = 72.0
    private static let eyeDistance = Double(ProcessInfo.processInfo.environment["LIDFOLD_EYE"] ?? "") ?? 2200.0
    private static let tiltSign = Double(ProcessInfo.processInfo.environment["LIDFOLD_TILT_SIGN"] ?? "1") ?? 1

    private let content = CALayer()
    private let dark = CAGradientLayer()
    private let glass = CAGradientLayer()
    private let reflection = CAGradientLayer()
    private var blur: NSObject?

    init(frozen: CGImage) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        content.contents = frozen
        content.contentsGravity = .resize
        content.anchorPoint = CGPoint(x: 0.5, y: 0)
        if let blur = Self.makeVariableBlur() {
            content.filters = [blur]
            self.blur = blur
        }
        layer?.addSublayer(content)

        glass.colors = [
            NSColor(red: 0.82, green: 0.85, blue: 0.86, alpha: 1).cgColor,
            NSColor(red: 0.82, green: 0.85, blue: 0.86, alpha: 0).cgColor,
        ]
        glass.compositingFilter = "softLightBlendMode"
        glass.opacity = 0

        reflection.colors = [
            NSColor.white.withAlphaComponent(0).cgColor,
            NSColor.white.cgColor,
            NSColor.white.withAlphaComponent(0).cgColor,
        ]
        reflection.locations = [0.24, 0.35, 0.46]
        reflection.opacity = 0

        dark.colors = Array(repeating: NSColor.black.cgColor, count: 6)
        dark.locations = [0, 0.2, 0.4, 0.6, 0.8, 1.0]

        for gradient in [glass, dark, reflection] {
            gradient.startPoint = CGPoint(x: 0.5, y: 1)
            gradient.endPoint = CGPoint(x: 0.5, y: 0)
            layer?.addSublayer(gradient)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contentsScale = scale
        content.contentsScale = scale
        content.bounds = bounds
        content.position = CGPoint(x: bounds.midX, y: 0)
        dark.frame = bounds
        glass.frame = bounds
        reflection.frame = bounds
        CATransaction.commit()
    }

    /// - Parameters:
    ///   - progress: 0 at the arming angle, 1 with the lid shut.
    ///   - tiltDegrees: how far the lid has closed past the arming angle.
    func update(progress: Double, tiltDegrees: Double) {
        let motion = progress * progress * (3 - 2 * progress)

        var transform = CATransform3DIdentity
        transform.m34 = -1 / Self.eyeDistance
        transform = CATransform3DRotate(
            transform,
            CGFloat(Self.tiltSign * tiltDegrees * .pi / 180),
            1, 0, 0
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        content.transform = transform
        blur?.setValue(Self.maxBlurRadius * motion, forKey: "inputRadius")

        dark.colors = (0..<6).map { step in
            let fromHinge = 1 - Double(step) * 0.2
            let gradient = max(0, min(1, (fromHinge - 0.2) / 0.8))
            let effect = motion * pow(gradient, 1.35)
            return NSColor.black.withAlphaComponent(min(1, effect * 2)).cgColor
        }

        glass.opacity = Float(0.20 * motion)
        reflection.opacity = Float(0.06 * motion)
        CATransaction.commit()
    }

    private static func makeVariableBlur() -> NSObject? {
        guard let filterClass = NSClassFromString("CAFilter") as AnyObject as? NSObjectProtocol,
              let filter = filterClass.perform(NSSelectorFromString("filterWithType:"), with: "variableBlur")?
                  .takeUnretainedValue() as? NSObject
        else { return nil }
        filter.setValue(blurRamp(), forKey: "inputMaskImage")
        filter.setValue(0.0, forKey: "inputRadius")
        filter.setValue(true, forKey: "inputNormalizeEdges")
        filter.setValue("blur", forKey: "name")
        return filter
    }

    /// Opaque at the top (farthest from the hinge, most defocus) on the Duo's
    /// `pow(fromHinge, 1.35)` curve. `variableBlur` reads the mask's alpha, not its luminance.
    private static func blurRamp() -> CGImage? {
        let height = 512
        let width = 8
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32
        ) else { return nil }

        for row in 0..<height {
            let fromHinge = 1 - Double(row) / Double(height - 1)
            let alpha = UInt8(max(0, min(255, pow(fromHinge, 1.35) * 255)))
            for column in 0..<width {
                let offset = row * width * 4 + column * 4
                rep.bitmapData![offset] = alpha
                rep.bitmapData![offset + 1] = alpha
                rep.bitmapData![offset + 2] = alpha
                rep.bitmapData![offset + 3] = alpha
            }
        }
        return rep.cgImage
    }
}
