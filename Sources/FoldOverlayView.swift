import AppKit

/// The iPhone Duo fold: the desktop swings away about the hinge as the lid closes, foreshortening
/// into a trapezoid while black void opens behind it. Progressive blur and darkening ride on top.
final class FoldOverlayView: NSView {
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
        let look = FoldModel.frame(progress: progress, tiltDegrees: tiltDegrees, configuration: .current)

        // Swing the content away about the hinge, exactly as the lid moves, under a fixed camera.
        // The far edge foreshortens toward the vanishing point and black void opens behind it.
        var perspective = CATransform3DIdentity
        perspective.m34 = CGFloat(look.perspective)
        let swung = CATransform3DRotate(perspective, CGFloat(look.rotationRadians), 1, 0, 0)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        content.transform = swung
        blur?.setValue(look.blurRadius, forKey: "inputRadius")
        dark.colors = look.darkness.map { NSColor.black.withAlphaComponent($0).cgColor }
        glass.opacity = Float(look.glassOpacity)
        reflection.opacity = Float(look.reflectionOpacity)
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
            let alpha = FoldModel.blurMaskByte(row: row, rows: height)
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
