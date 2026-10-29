import SwiftUI
import CoreImage
import CoreGraphics
import ImageIO

struct InteractiveCalibrationEditor: View {
    @Binding var points: [CalibrationPoint]
    let photoURL: URL?
    var onSave: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    enum LoadState {
        case loading
        case loaded(CGImage, CGSize)
        case failed(String)
    }

    @State private var loadState: LoadState = .loading
    @State private var editedPoints: [CalibrationPoint] = []
    
    var body: some View {
        NavigationStack {
            VStack {
                switch loadState {
                case .loading:
                    ProgressView("Loading image...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let error):
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("Could not load image.")
                            .font(.headline)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .loaded(let cgImage, let imageSize):
                    GeometryReader { geo in
                        let scale = min(geo.size.width / imageSize.width, geo.size.height / imageSize.height)
                        let displayedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
                        let offsetX = (geo.size.width - displayedSize.width) / 2
                        let offsetY = (geo.size.height - displayedSize.height) / 2
                        
                        ZStack(alignment: .topLeading) {
                            Image(cgImage, scale: 1.0, label: Text("Calibration Image"))
                                .resizable()
                                .scaledToFit()
                                .frame(width: geo.size.width, height: geo.size.height)
                                
                            ForEach($editedPoints) { $point in
                                PointDraggableView(
                                    point: $point,
                                    scale: scale,
                                    offsetX: offsetX,
                                    offsetY: offsetY,
                                    imageSize: imageSize
                                )
                            }
                        }
                    }
                    .padding()
                }
            }
            #if os(macOS)
            .frame(minWidth: 800, idealWidth: 1200, minHeight: 600, idealHeight: 900)
            #endif
            .navigationTitle("Edit Points")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        points = editedPoints
                        dismiss()
                        onSave?()
                    }
                    .disabled(ifcaseLoaded == false)
                }
            }
            .task {
                load()
            }
        }
    }
    
    private var ifcaseLoaded: Bool {
        if case .loaded = loadState { return true }
        return false
    }
    
    private func load() {
        editedPoints = points
        
        guard let url = photoURL else {
            loadState = .failed("No photo available. Please import or specify a valid photo.")
            return
        }
        
        Task.detached {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                await MainActor.run { loadState = .failed("Failed to open image file.") }
                return
            }
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false
            ]
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
                await MainActor.run { loadState = .failed("Failed to decode image.") }
                return
            }
            
            let width = CGFloat(image.width)
            let height = CGFloat(image.height)
            
            await MainActor.run {
                self.loadState = .loaded(image, CGSize(width: width, height: height))
                
                for index in self.editedPoints.indices {
                    self.editedPoints[index].xPx = round(max(0, min(width, self.editedPoints[index].xPx)))
                    self.editedPoints[index].yPx = round(max(0, min(height, self.editedPoints[index].yPx)))
                }
            }
        }
    }
}

private struct PointDraggableView: View {
    @Binding var point: CalibrationPoint
    let scale: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat
    let imageSize: CGSize
    
    @State private var dragStartPoint: CGPoint? = nil
    
    var body: some View {
        let displayedHeight = imageSize.height * scale
        let viewX = offsetX + (point.xPx * scale)
        let viewY = offsetY + displayedHeight - (point.yPx * scale)
        
        Circle()
            .fill(Color.blue.opacity(0.4))
            .frame(width: 30, height: 30)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .overlay(Circle().fill(Color.red).frame(width: 6, height: 6))
            .overlay(alignment: .bottom) {
                Text(point.label)
                    .font(.system(size: 10, weight: .bold))
                    .fixedSize()
                    .padding(4)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(4)
                    .offset(y: -20)
            }
            .position(x: viewX, y: viewY)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStartPoint == nil {
                            dragStartPoint = CGPoint(x: point.xPx, y: point.yPx)
                        }
                        if let start = dragStartPoint {
                            let deltaXPx = value.translation.width / scale
                            let deltaYPx = -value.translation.height / scale
                            
                            point.xPx = round(max(0, min(imageSize.width, start.x + deltaXPx)))
                            point.yPx = round(max(0, min(imageSize.height, start.y + deltaYPx)))
                        }
                    }
                    .onEnded { _ in
                        dragStartPoint = nil
                    }
            )
            .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
    }
}
