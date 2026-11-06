import CoreImage
import Foundation
import UIKit

/// Colour filters that make the cell/blob easier to see.
/// Applied in software (CoreImage) to the zoom photo to produce photo 3,
/// so photos 2 and 3 show exactly the same moment.
/// The same chain drives the live preview in the Settings tab.
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

    /// Applies this preset to a CIImage (used for live preview and photos).
    func applied(to image: CIImage) -> CIImage {
        switch self {
        case .none:
            return image
        case .contrast:
            let f = CIFilter(name: "CIColorControls")
            f?.setValue(image, forKey: kCIInputImageKey)
            f?.setValue(1.6, forKey: kCIInputContrastKey)
            f?.setValue(0.05, forKey: kCIInputBrightnessKey)
            f?.setValue(0.0, forKey: kCIInputSaturationKey)
            return f?.outputImage ?? image
        case .invert:
            let f = CIFilter(name: "CIColorInvert")
            f?.setValue(image, forKey: kCIInputImageKey)
            return f?.outputImage ?? image
        case .mono:
            let f = CIFilter(name: "CIPhotoEffectMono")
            f?.setValue(image, forKey: kCIInputImageKey)
            return f?.outputImage ?? image
        case .falseColor:
            let f = CIFilter(name: "CIFalseColor")
            f?.setValue(image, forKey: kCIInputImageKey)
            return f?.outputImage ?? image
        }
    }

    /// Per-channel gains via a colour matrix (R/G/B/A sliders).
    static func applyChannels(to image: CIImage,
                              red: Double, green: Double, blue: Double, alpha: Double) -> CIImage {
        guard red != 1 || green != 1 || blue != 1 || alpha != 1 else { return image }
        let f = CIFilter(name: "CIColorMatrix")
        f?.setValue(image, forKey: kCIInputImageKey)
        f?.setValue(CIVector(x: CGFloat(red), y: 0, z: 0, w: 0), forKey: "inputRVector")
        f?.setValue(CIVector(x: 0, y: CGFloat(green), z: 0, w: 0), forKey: "inputGVector")
        f?.setValue(CIVector(x: 0, y: 0, z: CGFloat(blue), w: 0), forKey: "inputBVector")
        f?.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(alpha)), forKey: "inputAVector")
        return f?.outputImage ?? image
    }

    /// Extra contrast (contrast slider), 1 = unchanged.
    static func applyContrast(to image: CIImage, value: Double) -> CIImage {
        guard value != 1 else { return image }
        let f = CIFilter(name: "CIColorControls")
        f?.setValue(image, forKey: kCIInputImageKey)
        f?.setValue(value, forKey: kCIInputContrastKey)
        f?.setValue(0, forKey: kCIInputBrightnessKey)
        f?.setValue(1, forKey: kCIInputSaturationKey)
        return f?.outputImage ?? image
    }

    /// Full chain for a saved photo: preset + channels + contrast. Returns JPEG data.
    func applied(to jpegData: Data, red: Double, green: Double, blue: Double, alpha: Double,
                 contrast: Double) -> Data? {
        guard let ciImage = CIImage(data: jpegData,
                                    options: [.applyOrientationProperty: true]) else { return nil }
        var output = applied(to: ciImage)
        output = Self.applyChannels(to: output, red: red, green: green, blue: blue, alpha: alpha)
        output = Self.applyContrast(to: output, value: contrast)
        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.9)
    }
}
