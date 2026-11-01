import SwiftUI

/// Reusable wall background displaying the rectified main wall and kickboard images
/// scaled and aligned to the given canvas size.
struct WallBackgroundView: View {
    let size: CGSize

    var body: some View {
        let kickboardHeight = size.height * (WallSpec.kickboardHeightCm / WallSpec.totalHeightCm)
        let mainWallHeight = max(0, size.height - kickboardHeight)
        let mainWallImageURL = existingURL(for: { try WallProjectPaths.defaultMainWallRectifiedURL() })
        let kickboardImageURL = existingURL(for: { try WallProjectPaths.defaultKickboardRectifiedURL() })

        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                wallSectionBackground(
                    imageURL: mainWallImageURL,
                    fallbackColor: Color.gray.opacity(0.2)
                )
                .frame(height: mainWallHeight)

                wallSectionBackground(
                    imageURL: kickboardImageURL,
                    fallbackColor: Color.brown.opacity(0.22)
                )
                .frame(height: kickboardHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(Color.black.opacity(0.35))
                .frame(height: 1)
                .offset(y: -kickboardHeight)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func wallSectionBackground(imageURL: URL?, fallbackColor: Color) -> some View {
        if let imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(fallbackColor)
                default:
                    Rectangle().fill(fallbackColor)
                }
            }
        } else {
            Rectangle().fill(fallbackColor)
        }
    }

    private func existingURL(for resolver: () throws -> URL) -> URL? {
        guard let resolved = try? resolver(),
              FileManager.default.fileExists(atPath: resolved.path) else {
            return nil
        }
        return resolved
    }
}

