import Foundation

enum WallSpec {
    static let widthCm: Double = 360
    static let mainWallHeightCm: Double = 320
    static let kickboardHeightCm: Double = 40
    static let totalHeightCm: Double = mainWallHeightCm + kickboardHeightCm

    static let mainWallAngleDegFromFloor: Double = 45
    static let kickboardAngleDegFromFloor: Double = 90

    static let rectifiedPixelsPerCm: Double = 2

    static let mainPlaneName = "main"
    static let kickboardPlaneName = "kickboard"

    static let maxGripPerHold = 3
}
