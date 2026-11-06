import Foundation
import Vision
import CoreGraphics

/// Finds the blob (cell colony) in a photo with Vision contour detection
/// and suggests a zoom factor so the blob fills the wanted share of the frame.
/// Returns nil when nothing plausible is found — the caller then falls back
/// to the stored zoom from the settings.
enum BlobDetector {

    struct Detection {
        /// Bounding box in normalized image coordinates (0...1).
        var boundingBox: CGRect
        /// Zoom that would make the blob fill the target share of the width.
        var suggestedZoom: CGFloat
    }

    /// - Parameters:
    ///   - jpegData: the normal (1x) photo of this series
    ///   - currentZoom: zoom the photo was taken with (normally 1)
    ///   - targetFill: wanted share of image width, 0...1 (e.g. 0.8)
    ///   - maxZoom: hardware/app zoom cap
    static func detect(jpegData: Data,
                       currentZoom: CGFloat,
                       targetFill: CGFloat,
                       maxZoom: CGFloat) -> Detection? {
        let request = VNDetectContoursRequest()
        request.detectsDarkOnLight = true
        request.contrastAdjustment = 1.5
        request.maximumImageDimension = 1024

        let handler = VNImageRequestHandler(data: jpegData, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let contours = request.results?.first?.topLevelContours else { return nil }

        // Largest plausible contour wins. Implausible = tiny speck or
        // (almost) the whole picture, e.g. the petri dish rim / background.
        var best: CGRect?
        var bestArea: CGFloat = 0
        for contour in contours {
            let box = contour.normalizedPath.boundingBox
            let area = box.width * box.height
            guard box.width > 0.05, box.height > 0.05,
                  area > 0.005, area < 0.85,
                  box.width / max(box.height, 0.001) > 0.25,
                  box.width / max(box.height, 0.001) < 4 else { continue }
            if area > bestArea {
                bestArea = area
                best = box
            }
        }

        guard let box = best, box.width > 0 else { return nil }
        let zoom = currentZoom * (targetFill / box.width)
        return Detection(boundingBox: box,
                         suggestedZoom: min(max(zoom, 1), maxZoom))
    }
}
