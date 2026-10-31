import CoreGraphics
import Foundation
import SwiftUI

import CoreGraphics
import Foundation
import SwiftUI

/// Configurable shape for the floating hold zoom loupe.
enum HoldLoupeShape: String, CaseIterable, Codable, Sendable {
    case circle
    case roundedRectangle
}

/// Configuration options for the floating hold loupe preview.
/// Shape, screen size, high-res crop span, and styling are easily customized.
struct HoldLoupeConfig: Sendable, Equatable {
    /// Visual shape of the loupe. Default is circular.
    var shape: HoldLoupeShape

    /// Dimensions of the floating preview on screen in points.
    var size: CGSize

    /// Corner radius when using `.roundedRectangle`.
    var cornerRadius: CGFloat

    /// Side length (width and height in original photo pixels) of the cropped region.
    /// Controls how much of the surrounding hold/wall is captured at full native resolution.
    var cropPixelSpan: CGFloat

    /// Width of the loupe border stroke.
    var borderWidth: CGFloat

    /// Color of the loupe border.
    var borderColorHex: String

    /// Shadow blur radius around the floating preview.
    var shadowRadius: CGFloat

    /// Whether to show a subtle centering reticle / crosshair at the hold center.
    var showCrosshair: Bool

    /// Whether to display a pill badge with the hold number and role.
    var showBadge: Bool

    /// Default floating offset from the center of the hovered hold marker.
    var offsetFromMarker: CGSize

    init(
        shape: HoldLoupeShape = .circle,
        size: CGSize = CGSize(width: 190, height: 190),
        cornerRadius: CGFloat = 18,
        cropPixelSpan: CGFloat = 380,
        borderWidth: CGFloat = 3.0,
        borderColorHex: String = "#FFFFFF",
        shadowRadius: CGFloat = 12.0,
        showCrosshair: Bool = true,
        showBadge: Bool = true,
        offsetFromMarker: CGSize = CGSize(width: 0, height: -125)
    ) {
        self.shape = shape
        self.size = size
        self.cornerRadius = cornerRadius
        self.cropPixelSpan = cropPixelSpan
        self.borderWidth = borderWidth
        self.borderColorHex = borderColorHex
        self.shadowRadius = shadowRadius
        self.showCrosshair = showCrosshair
        self.showBadge = showBadge
        self.offsetFromMarker = offsetFromMarker
    }

    /// Default circular loupe with clean white rim and crisp zoom.
    static let defaultCircle = HoldLoupeConfig(
        shape: .circle,
        size: CGSize(width: 190, height: 190),
        cropPixelSpan: 380
    )

    /// Larger circular loupe for inspecting micro-details.
    static let largeCircle = HoldLoupeConfig(
        shape: .circle,
        size: CGSize(width: 240, height: 240),
        cropPixelSpan: 480,
        offsetFromMarker: CGSize(width: 0, height: -150)
    )

    /// Rounded card preview variant.
    static let roundedCard = HoldLoupeConfig(
        shape: .roundedRectangle,
        size: CGSize(width: 210, height: 190),
        cornerRadius: 16,
        cropPixelSpan: 380
    )

    /// Compact circular loupe.
    static let compactCircle = HoldLoupeConfig(
        shape: .circle,
        size: CGSize(width: 150, height: 150),
        cropPixelSpan: 300,
        offsetFromMarker: CGSize(width: 0, height: -105)
    )

    var borderColor: Color {
        Color(hex: borderColorHex) ?? .white
    }
}

private extension Color {
    init?(hex: String) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHex.hasPrefix("#") {
            cleanHex.removeFirst()
        }
        guard let value = UInt64(cleanHex, radix: 16) else { return nil }
        if cleanHex.count == 6 {
            let r = Double((value & 0xFF0000) >> 16) / 255.0
            let g = Double((value & 0x00FF00) >> 8) / 255.0
            let b = Double(value & 0x0000FF) / 255.0
            self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
        } else if cleanHex.count == 8 {
            let r = Double((value & 0xFF000000) >> 24) / 255.0
            let g = Double((value & 0x00FF0000) >> 16) / 255.0
            let b = Double((value & 0x0000FF00) >> 8) / 255.0
            let a = Double(value & 0x000000FF) / 255.0
            self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
        } else {
            return nil
        }
    }
}
