import SwiftUI

/// Reusable toolbar containing zoom controls, scale percentage, fit-to-window button,
/// loupe toggle checkbox, and the loupe configuration settings menu.
struct WallZoomControlsView: View {
    @Binding var zoomScale: CGFloat
    @Binding var panOffset: CGSize
    @Binding var baseZoomScale: CGFloat
    @Binding var loupeConfig: HoldLoupeConfig

    var minScale: CGFloat = 1.0
    var maxScale: CGFloat = 5.0

    var body: some View {
        HStack(spacing: 8) {
            Button {
                stepZoom(by: -0.25)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("Zoom Out")

            Text("\(Int(zoomScale * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 42)

            Button {
                stepZoom(by: 0.25)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("Zoom In")

            if zoomScale > 1.0 {
                Button("Fit") {
                    withAnimation(.easeOut(duration: 0.15)) {
                        zoomScale = 1.0
                        baseZoomScale = 1.0
                        panOffset = .zero
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Reset zoom to fit window")
            }

            Divider()
                .frame(height: 14)

            // Checkbox to enable or disable the magnifying loupe
            #if os(macOS)
            Toggle("Use Loupe", isOn: $loupeConfig.isEnabled)
                .toggleStyle(.checkbox)
                .font(.caption)
                .help("Toggle high-resolution hold magnifying loupe")
            #else
            Button {
                loupeConfig.isEnabled.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: loupeConfig.isEnabled ? "checkmark.square.fill" : "square")
                        .font(.caption)
                        .foregroundStyle(loupeConfig.isEnabled ? Color.accentColor : Color.secondary)
                    Text("Loupe")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
            #endif

            HoldLoupeMenu(config: $loupeConfig)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func stepZoom(by delta: CGFloat) {
        let newScale = min(maxScale, max(minScale, zoomScale + delta))
        withAnimation(.easeOut(duration: 0.15)) {
            zoomScale = newScale
            baseZoomScale = newScale
            if newScale <= 1.0 {
                panOffset = .zero
            }
        }
    }
}

