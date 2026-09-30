import AppKit
import ImageIO
import Metal
import QuartzCore
import UniformTypeIdentifiers

// Renders the real FoldOverlayView offscreen: no window, no display, no Screen Recording. The view's layer tree
// goes through CARenderer into a Metal texture, private `variableBlur` included. The source picture stands in
// for the frozen capture the app takes of the built-in display.
//
//   build/render --source Tools/standin/desktop.png --angles 88,70,50,30,5 --out build/frames
//   build/render --source Tools/standin/desktop.png --simulate 100:5:2.4:0.5 --seconds 6 --fps 20 --out build/frames
//   build/render --verify
//   build/render --bench 120
//   build/render --table 90,88,70,50,30,5
//
// Options: --width <px> scales the output, --strip adds the lid gauge and readout under each frame.

@MainActor
final class OffscreenRenderer {
    static let panelPoints = CGSize(width: 1728, height: 1117)
    static let scale: CGFloat = 2

    let pixelWidth = Int(panelPoints.width * scale)
    let pixelHeight = Int(panelPoints.height * scale)
    private let view: FoldOverlayView
    private let root = CALayer()
    private let texture: MTLTexture
    private let queue: MTLCommandQueue
    private let renderer: CARenderer

    init?(source: CGImage) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: pixelWidth, height: pixelHeight, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        self.texture = texture
        self.queue = queue

        view = FoldOverlayView(frozen: source)
        view.frame = CGRect(origin: .zero, size: Self.panelPoints)
        view.layoutSubtreeIfNeeded()

        root.bounds = CGRect(origin: .zero, size: Self.panelPoints)
        root.anchorPoint = .zero
        root.position = .zero
        root.sublayerTransform = CATransform3DMakeScale(Self.scale, Self.scale, 1)
        root.backgroundColor = NSColor.black.cgColor
        if let layer = view.layer { root.addSublayer(layer) }

        renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue: queue])
        renderer.layer = root
        renderer.bounds = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
    }

    /// Draws one frame into the texture and waits for the GPU. Returns the seconds it took.
    @discardableResult
    func draw(progress: Double, tiltDegrees: Double) -> Double {
        let start = CACurrentMediaTime()
        view.update(progress: progress, tiltDegrees: tiltDegrees)
        CATransaction.flush()
        renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
        renderer.addUpdate(renderer.updateBounds())
        renderer.render()
        renderer.endFrame()
        let fence = queue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
        return CACurrentMediaTime() - start
    }

    /// Times only the layer property updates, which is what the app does on the main thread every tick.
    func updateCost(progress: Double, tiltDegrees: Double) -> Double {
        let start = CACurrentMediaTime()
        view.update(progress: progress, tiltDegrees: tiltDegrees)
        return CACurrentMediaTime() - start
    }

    /// The texture stores layer space, bottom row first. Flip it into a normal top-down image.
    func image() -> CGImage? {
        let rowBytes = pixelWidth * 4
        var raw = [UInt8](repeating: 0, count: rowBytes * pixelHeight)
        texture.getBytes(&raw, bytesPerRow: rowBytes, from: MTLRegionMake2D(0, 0, pixelWidth, pixelHeight), mipmapLevel: 0)
        var flipped = [UInt8](repeating: 0, count: raw.count)
        for row in 0..<pixelHeight {
            let from = row * rowBytes
            let to = (pixelHeight - 1 - row) * rowBytes
            flipped[to..<to + rowBytes] = raw[from..<from + rowBytes]
        }
        guard let provider = CGDataProvider(data: Data(flipped) as CFData) else { return nil }
        return CGImage(
            width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}

enum Readout {
    /// A black strip under the picture: the lid as seen from the side, and the numbers behind the frame.
    static func compose(_ picture: CGImage, angle: Double, readout: String, width: Int) -> CGImage {
        let pictureHeight = width * picture.height / picture.width
        let stripHeight = Int(Double(width) * 0.1)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: width, height: pictureHeight + stripHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: pictureHeight + stripHeight))
        context.interpolationQuality = .high
        context.draw(picture, in: CGRect(x: 0, y: stripHeight, width: width, height: pictureHeight))

        let unit = Double(width) / 720
        let hinge = CGPoint(x: 92 * unit, y: Double(stripHeight) * 0.3)
        let radians = angle * .pi / 180
        context.setLineCap(.round)
        context.setLineWidth(2.5 * unit)
        context.setStrokeColor(CGColor(gray: 0.45, alpha: 1))
        context.move(to: hinge)
        context.addLine(to: CGPoint(x: hinge.x - 62 * unit, y: hinge.y))
        context.strokePath()
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.move(to: hinge)
        context.addLine(to: CGPoint(x: hinge.x - 50 * unit * cos(radians), y: hinge.y + 50 * unit * sin(radians)))
        context.strokePath()
        context.setLineWidth(1.5 * unit)
        context.setStrokeColor(CGColor(gray: 0.6, alpha: 1))
        context.addArc(center: hinge, radius: 20 * unit, startAngle: .pi - radians, endAngle: .pi, clockwise: false)
        context.strokePath()

        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let big = NSFont.monospacedSystemFont(ofSize: 24 * unit, weight: .medium)
        let small = NSFont.monospacedSystemFont(ofSize: 13 * unit, weight: .regular)
        let baseline = Double(stripHeight) * 0.3 - 4 * unit
        NSAttributedString(string: String(format: "%.0f°", angle), attributes: [.font: big, .foregroundColor: NSColor.white])
            .draw(at: NSPoint(x: 112 * unit, y: baseline))
        let attributed = NSAttributedString(string: readout, attributes: [.font: small, .foregroundColor: NSColor(white: 0.65, alpha: 1)])
        attributed.draw(at: NSPoint(x: Double(width) - attributed.size().width - 18 * unit, y: baseline + 6 * unit))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()!
    }
}

extension Readout {
    static func scaled(_ picture: CGImage, width: Int) -> CGImage {
        let height = width * picture.height / picture.width
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.interpolationQuality = .high
        context.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}

func loadImage(_ path: String) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func savePNG(_ image: CGImage, to path: String) {
    guard let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { fatalError("cannot write \(path)") }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

func flatPicture(gray: CGFloat) -> CGImage {
    let context = CGContext(
        data: nil, width: 3456, height: 2234, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(gray: gray, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 3456, height: 2234))
    return context.makeImage()!
}

func level(_ pixels: [UInt8], width: Int, x: Int, y: Int) -> Int {
    Int(pixels[(y * width + x) * 4])
}

func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
    sorted[min(sorted.count - 1, Int(Double(sorted.count) * fraction))]
}

func pixelBytes(_ image: CGImage) -> [UInt8]? {
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return bytes
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    fputs(message + "\n", stderr)
    exit(code)
}

struct Options {
    static let switches: Set<String> = ["strip", "verify"]
    private(set) var values: [String: String] = [:]
    private(set) var flags: Set<String> = []

    init(_ arguments: ArraySlice<String>) {
        var remaining = arguments
        while let argument = remaining.popFirst() {
            guard argument.hasPrefix("--") else { continue }
            let key = String(argument.dropFirst(2))
            if Self.switches.contains(key) { flags.insert(key) } else if let value = remaining.popFirst() { values[key] = value }
        }
    }

    func number(_ key: String) -> Double? { values[key].flatMap(Double.init) }
    func numbers(_ key: String) -> [Double]? { values[key].map { $0.split(separator: ",").compactMap { Double($0) } } }
}

/// Turns a lid angle into a finished PNG: the model decides the fold, the real view draws it.
@MainActor
struct FrameWriter {
    let renderer: OffscreenRenderer
    let directory: String
    let width: Int
    let strip: Bool
    let configuration = FoldConfiguration.current

    func write(name: String, angle: Double) {
        var progress = 0.0
        var tilt = 0.0
        var readout = "overlay off"
        if case let .fold(foldProgress, foldTilt) = FoldModel.presentation(angle: angle, configuration: configuration) {
            let look = FoldModel.frame(progress: foldProgress, tiltDegrees: foldTilt, configuration: configuration)
            progress = foldProgress
            tilt = foldTilt
            readout = String(format: "progress %.2f   tilt %.0f°   blur %.0f pt", progress, tilt, look.blurRadius)
        }
        renderer.draw(progress: progress, tiltDegrees: tilt)
        guard var image = renderer.image() else { fail("readback failed") }
        if strip {
            image = Readout.compose(image, angle: angle, readout: readout, width: width)
        } else if width != renderer.pixelWidth {
            image = Readout.scaled(image, width: width)
        }
        savePNG(image, to: "\(directory)/\(name).png")
    }
}

let usage = """
    usage: render --source <image> (--angles a,b,c | --simulate open:closed:seconds[:hold] [--seconds s] [--fps n] | --bench n)
                  [--out dir] [--width px] [--strip]
           render --verify
           render --table a,b,c
    """

@main
enum Render {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let options = Options(CommandLine.arguments.dropFirst())
        if options.flags.contains("verify") { exit(verify() ? 0 : 1) }
        if let angles = options.numbers("table") { table(angles: angles); return }
        guard let source = options.values["source"].flatMap(loadImage) else { fail(usage, code: 2) }
        guard let renderer = OffscreenRenderer(source: source) else { fail("no Metal device") }
        if let frames = options.number("bench") { bench(renderer, frames: Int(frames)); return }

        let directory = options.values["out"] ?? "build/frames"
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let frames = FrameWriter(
            renderer: renderer, directory: directory,
            width: options.number("width").map(Int.init) ?? renderer.pixelWidth, strip: options.flags.contains("strip")
        )
        if let angles = options.numbers("angles") {
            for angle in angles { frames.write(name: String(format: "angle_%03.0f", angle), angle: angle) }
        } else if let lid = options.values["simulate"].flatMap(AngleSimulation.init(specification:)) {
            simulate(lid, seconds: options.number("seconds") ?? 6, fps: options.number("fps") ?? 20, into: frames)
        } else {
            fail(usage, code: 2)
        }
    }

    /// A scripted lid through the filter the app runs. The sensor ticks at 60 Hz, frames are taken at `fps`.
    @MainActor
    static func simulate(_ lid: AngleSimulation, seconds: Double, fps: Double, into frames: FrameWriter) {
        let sensorHz = 60.0
        var filter = AngleFilter()
        var sensorTick = 0
        for frame in 0..<Int(seconds * fps) {
            let time = Double(frame) / fps
            while Double(sensorTick) / sensorHz <= time {
                let sensorTime = Double(sensorTick) / sensorHz
                sensorTick += 1
                if filter.shouldPoll() { _ = filter.ingest(lid.angle(at: sensorTime), at: sensorTime) }
            }
            frames.write(name: String(format: "frame_%04d", frame), angle: filter.smoothed ?? lid.angle(at: time))
        }
    }

    /// Checks the pure silhouette model against what Core Animation really draws. A flat light picture is swung
    /// with no blur or darkening, so its edges are plain to find.
    @MainActor
    static func verify() -> Bool {
        guard let renderer = OffscreenRenderer(source: flatPicture(gray: 0.8)) else { fail("no Metal device") }
        let width = renderer.pixelWidth
        let height = renderer.pixelHeight
        let panelHeight = Double(OffscreenRenderer.panelPoints.height)
        let litAbove = 100
        var worst = 0.0
        print("tilt   far edge row, model / drawn   half width 60 px below it, model / drawn")
        for tilt in [10.0, 30, 50, 70, 85] {
            renderer.draw(progress: 0, tiltDegrees: tilt)
            guard let image = renderer.image(), let pixels = pixelBytes(image) else { return false }
            let shape = FoldModel.silhouette(tiltDegrees: tilt, panelHeight: panelHeight, configuration: FoldConfiguration())
            let farRow = Double(height) * (1 - shape.farEdgeHeight)
            let farHalf = Double(width) / 2 * shape.farEdgeWidth
            let probe = Int(farRow) + 60
            let along = (Double(probe) - farRow) / (Double(height) - farRow)
            let modelHalf = farHalf + (Double(width) / 2 - farHalf) * along

            let drawnRow = (0..<height).first { level(pixels, width: width, x: width / 2, y: $0) > litAbove }.map(Double.init) ?? -1
            let left = (0..<width).first { level(pixels, width: width, x: $0, y: probe) > litAbove } ?? 0
            let right = (0..<width).last { level(pixels, width: width, x: $0, y: probe) > litAbove } ?? 0
            let drawnHalf = Double(right - left + 1) / 2
            worst = max(worst, abs(drawnRow - farRow), abs(drawnHalf - modelHalf))
            print(String(format: "%4.0f   %8.1f / %8.1f            %8.1f / %8.1f", tilt, farRow, drawnRow, modelHalf, drawnHalf))
        }
        print(String(format: "worst error %.1f px on a %dx%d frame", worst, width, height))
        return worst <= 3
    }

    /// The model at chosen lid angles, as markdown.
    @MainActor
    static func table(angles: [Double]) {
        let configuration = FoldConfiguration()
        let panelHeight = Double(OffscreenRenderer.panelPoints.height)
        print("| Lid angle | Fold | Tilt | Blur radius | Far edge width | Far edge height |")
        print("|---|---|---|---|---|---|")
        for angle in angles {
            guard case let .fold(progress, tilt) = FoldModel.presentation(angle: angle, configuration: configuration) else {
                print(String(format: "| %.0f° | overlay off | | | | |", angle))
                continue
            }
            let look = FoldModel.frame(progress: progress, tiltDegrees: tilt, configuration: configuration)
            let shape = FoldModel.silhouette(tiltDegrees: tilt, panelHeight: panelHeight, configuration: configuration)
            print(String(format: "| %.0f° | %.2f | %.1f° | %.0f pt | %.0f%% | %.0f%% |",
                         angle, progress, tilt, look.blurRadius, shape.farEdgeWidth * 100, shape.farEdgeHeight * 100))
        }
    }

    /// Frame cost of the real layer tree at retina size. Every frame differs from the last, otherwise
    /// Core Animation has nothing to redraw and the timing means nothing.
    @MainActor
    static func bench(_ renderer: OffscreenRenderer, frames: Int) {
        let configuration = FoldConfiguration()
        let fullTilt = configuration.armBelow - configuration.closedAngle
        renderer.draw(progress: 0.5, tiltDegrees: fullTilt / 2)
        var times: [Double] = []
        for index in 0..<frames {
            let progress = 0.5 + 0.5 * sin(Double(index) * 0.1)
            times.append(renderer.draw(progress: progress, tiltDegrees: fullTilt * progress) * 1000)
        }
        times.sort()
        print(String(format: "render %dx%d, %d frames that all differ: p50 %.2f ms  p95 %.2f ms  max %.2f ms",
                     renderer.pixelWidth, renderer.pixelHeight, frames, percentile(times, 0.5), percentile(times, 0.95), times.last!))
        var costs: [Double] = []
        for index in 0..<frames * 10 {
            costs.append(renderer.updateCost(progress: Double(index % 100) / 100, tiltDegrees: 40) * 1_000_000)
        }
        costs.sort()
        print(String(format: "view.update on the main thread, %d calls: p50 %.0f us  p95 %.0f us  max %.0f us",
                     costs.count, percentile(costs, 0.5), percentile(costs, 0.95), costs.last!))
    }
}
