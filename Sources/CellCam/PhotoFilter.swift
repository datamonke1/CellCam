import CoreImage
import Foundation
import UIKit

/// Colour filters that make the cell/blob easier to see.
/// Applied in software (CoreImage) to the zoom photo to produce photo 3,
/// so photos 2 and 3 show exactly the same moment.
enum CellPhotoFilter: String, Codable, CaseIterable, Identifiable {
    case none
    case contrast
    case invert
    case mono
    case falseColor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "Keiner"
        case .contrast: return "Kontrast"
        case .invert: return "Invertiert"
        case .mono: return "Schwarz-Weiss"
        case .falseColor: return "Falschfarben"
        }
    }

    /// Returns filtered JPEG data, or nil if filtering failed.
    func applied(to jpegData: Data) -> Data? {
        guard self != .none else { return jpegData }
        guard let ciImage = CIImage(data: jpegData,
                                    options: [.applyOrientationProperty: true]) else { return nil }

        let filter: CIFilter?
        switch self {
        case .none:
            return jpegData
        case .contrast:
            filter = CIFilter(name: "CIColorControls")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
            filter?.setValue(1.6, forKey: kCIInputContrastKey)
            filter?.setValue(0.05, forKey: kCIInputBrightnessKey)
            filter?.setValue(0.0, forKey: kCIInputSaturationKey)
        case .invert:
            filter = CIFilter(name: "CIColorInvert")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
        case .mono:
            filter = CIFilter(name: "CIPhotoEffectMono")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
        case .falseColor:
            filter = CIFilter(name: "CIFalseColor")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
        }

        guard let output = filter?.outputImage else { return nil }
        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.9)
    }
}
