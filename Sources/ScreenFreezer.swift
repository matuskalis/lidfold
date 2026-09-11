import AppKit
import ScreenCaptureKit

enum ScreenFreezerError: Error {
    case noBuiltInDisplay
}

final class ScreenFreezer {
    private(set) var unavailable = false

    func captureBuiltInDisplay(excludingWindowNumber windowNumber: Int) async throws -> CGImage {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }) else {
                throw ScreenFreezerError.noBuiltInDisplay
            }
            let ownWindows = windowNumber > 0
                ? content.windows.filter { $0.windowID == CGWindowID(windowNumber) }
                : []
            let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            let config = SCStreamConfiguration()
            config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
            config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
            config.captureResolution = .best
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            unavailable = false
            return image
        } catch let error as ScreenFreezerError {
            throw error
        } catch {
            unavailable = true
            throw error
        }
    }
}
