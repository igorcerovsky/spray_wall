import SwiftUI

struct HoldMarkerView: View {
    let hold: Hold
    let colorBlindMode: Bool
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            marker
            RotationIndicatorShape(angleDeg: rotationIndicatorAngle)
                .stroke(indicatorColor, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            RotationIndicatorTipShape(angleDeg: rotationIndicatorAngle)
                .fill(indicatorColor)
        }
        .frame(width: markerSize.width, height: markerSize.height)
    }

    private var markerSize: CGSize {
        hold.role == .microFoot ? CGSize(width: size * 0.6, height: size * 0.6) : CGSize(width: size, height: size)
    }

    @ViewBuilder
    private var marker: some View {
        if hold.isStart {
            RoundedRectangle(cornerRadius: 4)
                .fill(fillColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(strokeColor, lineWidth: 1.2)
                }
                .rotationEffect(.degrees(90))
        } else if hold.isTop {
            RoundedRectangle(cornerRadius: 4)
                .fill(fillColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(strokeColor, lineWidth: 1.2)
                }
        } else {
            switch hold.role {
            case .hand:
                Circle()
                    .fill(fillColor)
                    .overlay {
                        Circle().stroke(strokeColor, lineWidth: 1.2)
                    }
            case .foot:
                Triangle()
                    .fill(fillColor)
                    .overlay {
                        Triangle().stroke(strokeColor, lineWidth: 1.2)
                    }
            case .microFoot:
                Circle()
                    .fill(fillColor)
                    .overlay {
                        Circle().stroke(strokeColor, lineWidth: 1.2)
                    }
            }
        }
    }

    private var fillColor: Color {
        let baseColor: Color
        if colorBlindMode {
            baseColor = .white
        } else if hold.isStart {
            baseColor = .green
        } else if hold.isTop {
            baseColor = .red
        } else {
            switch hold.role {
            case .hand:
                baseColor = .blue
            case .foot:
                baseColor = .yellow
            case .microFoot:
                baseColor = .orange
            }
        }

        return baseColor.opacity(0.18)
    }

    private var strokeColor: Color {
        colorBlindMode ? .black.opacity(0.75) : .white.opacity(0.85)
    }

    private var indicatorColor: Color {
        colorBlindMode ? .black.opacity(0.9) : .white.opacity(0.95)
    }

    private var rotationIndicatorAngle: Double {
        let orderedGrips = hold.grips.sorted { $0.createdAt < $1.createdAt }
        if let primaryGrip = orderedGrips.first {
            return primaryGrip.angleDeg
        }

        switch hold.role {
        case .hand:
            return 210
        case .foot, .microFoot:
            return 180
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct RotationIndicatorShape: Shape {
    let angleDeg: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.32
        let radians = angleDeg * .pi / 180
        let end = CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y - sin(radians) * radius
        )

        var path = Path()
        path.move(to: center)
        path.addLine(to: end)
        return path
    }
}

private struct RotationIndicatorTipShape: Shape {
    let angleDeg: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.32
        let radians = angleDeg * .pi / 180
        let tipCenter = CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y - sin(radians) * radius
        )
        let tipRadius = max(1.8, min(rect.width, rect.height) * 0.08)

        return Path(ellipseIn: CGRect(
            x: tipCenter.x - tipRadius,
            y: tipCenter.y - tipRadius,
            width: tipRadius * 2,
            height: tipRadius * 2
        ))
    }
}
