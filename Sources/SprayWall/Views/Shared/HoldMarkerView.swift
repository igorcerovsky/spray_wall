import SwiftUI

struct HoldMarkerView: View {
    let hold: Hold
    let colorBlindMode: Bool
    var size: CGFloat = 20

    var body: some View {
        marker
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
                        .stroke(.black.opacity(0.7), lineWidth: 1)
                }
                .rotationEffect(.degrees(90))
        } else if hold.isTop {
            RoundedRectangle(cornerRadius: 4)
                .fill(fillColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(.black.opacity(0.7), lineWidth: 1)
                }
        } else {
            switch hold.role {
            case .hand:
                Circle()
                    .fill(fillColor)
                    .overlay {
                        Circle().stroke(.black.opacity(0.7), lineWidth: 1)
                    }
            case .foot:
                Triangle()
                    .fill(fillColor)
                    .overlay {
                        Triangle().stroke(.black.opacity(0.7), lineWidth: 1)
                    }
            case .microFoot:
                Circle()
                    .fill(fillColor)
                    .overlay {
                        Circle().stroke(.black.opacity(0.7), lineWidth: 1)
                    }
            }
        }
    }

    private var fillColor: Color {
        if colorBlindMode {
            return .white
        }

        if hold.isStart {
            return .green
        }

        if hold.isTop {
            return .red
        }

        switch hold.role {
        case .hand:
            return .blue
        case .foot:
            return .yellow
        case .microFoot:
            return .orange
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
