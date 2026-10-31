import CoreGraphics
import SwiftUI

/// Floating magnifying loupe view that displays a pristine, high-resolution crop of a hovered hold.
/// Shape and styling adapt dynamically based on `HoldLoupeConfig`.
struct HoldLoupeView: View {
    let croppedImage: CGImage?
    let hold: Hold
    let role: BoulderHoldGroup?
    let config: HoldLoupeConfig

    init(
        croppedImage: CGImage?,
        hold: Hold,
        role: BoulderHoldGroup? = nil,
        config: HoldLoupeConfig = .defaultCircle
    ) {
        self.croppedImage = croppedImage
        self.hold = hold
        self.role = role
        self.config = config
    }

    var body: some View {
        VStack(spacing: 6) {
            loupeBody
                .frame(width: config.size.width, height: config.size.height)
                .shadow(color: Color.black.opacity(0.40), radius: config.shadowRadius, x: 0, y: 6)

            if config.showBadge {
                badgeView
            }
        }
    }

    // MARK: - Loupe Body with Shape Masking

    @ViewBuilder
    private var loupeBody: some View {
        ZStack {
            // Background fill
            Color.black

            // High-resolution cropped hold image
            if let croppedImage {
                Image(decorative: croppedImage, scale: 1.0)
                    .resizable()
                    .scaledToFill()
                    .frame(width: config.size.width, height: config.size.height)
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }

            // Center targeting reticle / crosshair
            if config.showCrosshair {
                reticleOverlay
            }

            // Lens glass reflection highlight
            lensGlassHighlight
        }
        .clipShape(loupeClipShape)
        .overlay(
            loupeBorderShape
                .stroke(config.borderColor, lineWidth: config.borderWidth)
        )
    }

    // MARK: - Dynamic Shapes

    private var loupeClipShape: AnyShape {
        switch config.shape {
        case .circle:
            return AnyShape(Circle())
        case .roundedRectangle:
            return AnyShape(RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous))
        }
    }

    private var loupeBorderShape: AnyShape {
        switch config.shape {
        case .circle:
            return AnyShape(Circle())
        case .roundedRectangle:
            return AnyShape(RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous))
        }
    }

    // MARK: - Center Reticle

    private var reticleOverlay: some View {
        ZStack {
            // Subtle cross lines
            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(width: 1, height: 18)
            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(width: 18, height: 1)

            // Center target ring
            Circle()
                .stroke(Color.white.opacity(0.85), lineWidth: 1.5)
                .frame(width: 12, height: 12)
            Circle()
                .fill(Color.red.opacity(0.80))
                .frame(width: 3, height: 3)
        }
    }

    // MARK: - Lens Highlight

    private var lensGlassHighlight: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0.20),
                Color.white.opacity(0.04),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .center
        )
        .allowsHitTesting(false)
    }

    // MARK: - Hold Info Badge

    private var badgeView: some View {
        HStack(spacing: 5) {
            Text("Hold #\(hold.holdID)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            if let role {
                Text(role.displayName.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(roleColor(for: role))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.78))
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 2)
    }

    private func roleColor(for role: BoulderHoldGroup) -> Color {
        switch role {
        case .start:
            return .green
        case .hold:
            return .blue
        case .foothold:
            return .yellow
        case .top:
            return .red
        }
    }
}
