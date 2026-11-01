import CoreGraphics
import SwiftUI

/// Floating magnifying loupe view that displays a pristine, high-resolution crop of a hovered or edited hold.
/// Shape and styling adapt dynamically based on `HoldLoupeConfig`.
struct HoldLoupeView: View {
    let croppedImage: CGImage?
    let title: String
    let subtitle: String?
    let role: BoulderHoldGroup?
    let config: HoldLoupeConfig

    init(
        croppedImage: CGImage?,
        title: String,
        subtitle: String? = nil,
        role: BoulderHoldGroup? = nil,
        config: HoldLoupeConfig = .defaultCircle
    ) {
        self.croppedImage = croppedImage
        self.title = title
        self.subtitle = subtitle
        self.role = role
        self.config = config
    }

    init(
        croppedImage: CGImage?,
        hold: Hold,
        role: BoulderHoldGroup? = nil,
        config: HoldLoupeConfig = .defaultCircle,
        showCoordinates: Bool = false
    ) {
        self.croppedImage = croppedImage
        self.title = "Hold #\(hold.holdID)"
        self.subtitle = showCoordinates ? "\(Int(hold.xCm)), \(Int(hold.yCm)) cm" : nil
        self.role = role
        self.config = config
    }

    var body: some View {
        if config.isEnabled {
            VStack(spacing: 6) {
                loupeBody
                    .frame(width: config.size.width, height: config.size.height)
                    .shadow(color: Color.black.opacity(0.40), radius: config.shadowRadius, x: 0, y: 6)

                if config.showBadge {
                    badgeView
                }
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
                .fill(Color.white.opacity(0.45))
                .frame(width: 1.2, height: 22)
            Rectangle()
                .fill(Color.white.opacity(0.45))
                .frame(width: 22, height: 1.2)

            // Center target ring
            Circle()
                .stroke(Color.white.opacity(0.85), lineWidth: 1.5)
                .frame(width: 14, height: 14)
            Circle()
                .fill(Color.red.opacity(0.85))
                .frame(width: 3.5, height: 3.5)
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
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
            }

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
        .background(Color.black.opacity(0.82))
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

/// Menu for configuring hold loupe shape, size, and display options.
struct HoldLoupeMenu: View {
    @Binding var config: HoldLoupeConfig

    var body: some View {
        Menu {
            Toggle("Enable Loupe Preview", isOn: $config.isEnabled)

            Divider()

            Section("Loupe Shape") {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        config.shape = .circle
                    }
                } label: {
                    Label("Circle", systemImage: config.shape == .circle ? "checkmark.circle.fill" : "circle")
                }

                Button {
                    withAnimation(.spring(response: 0.3)) {
                        config.shape = .roundedRectangle
                    }
                } label: {
                    Label("Rounded Card", systemImage: config.shape == .roundedRectangle ? "checkmark.circle.fill" : "app")
                }
            }

            Section("Loupe Size") {
                Button("Compact (150 pt)") {
                    withAnimation(.spring(response: 0.3)) {
                        config.size = CGSize(width: 150, height: 150)
                        config.cropPixelSpan = 300
                    }
                }

                Button("Standard (190 pt)") {
                    withAnimation(.spring(response: 0.3)) {
                        config.size = CGSize(width: 190, height: 190)
                        config.cropPixelSpan = 380
                    }
                }

                Button("Large (240 pt)") {
                    withAnimation(.spring(response: 0.3)) {
                        config.size = CGSize(width: 240, height: 240)
                        config.cropPixelSpan = 480
                    }
                }
            }

            Section("Details") {
                Toggle("Center Reticle", isOn: $config.showCrosshair)
                Toggle("Hold Badge", isOn: $config.showBadge)
            }
        } label: {
            Image(systemName: config.shape == .circle ? "viewfinder.circle" : "viewfinder.rectangular")
                .font(.caption)
        }
        .buttonStyle(.plain)
        .help("Hold Loupe Settings (Shape & Size)")
    }
}

