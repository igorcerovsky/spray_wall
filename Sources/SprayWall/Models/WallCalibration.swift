import Foundation
import SwiftData

@Model
final class WallCalibration {
    static let defaultPhotoPath = "/Users/igorcerovsky/Documents/spray_wall/wall.jpg"

    @Attribute(.unique) var id: UUID
    var photoPath: String
    var pointsJSON: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        photoPath: String = WallCalibration.defaultPhotoPath,
        points: [CalibrationPoint] = CalibrationPointTemplates.all,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.photoPath = photoPath
        self.pointsJSON = Self.encode(points)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var points: [CalibrationPoint] {
        get { Self.decode(pointsJSON) }
        set {
            pointsJSON = Self.encode(newValue)
            updatedAt = .now
        }
    }

    private static func encode(_ points: [CalibrationPoint]) -> String {
        guard let data = try? JSONEncoder().encode(points),
              let value = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return value
    }

    private static func decode(_ text: String) -> [CalibrationPoint] {
        guard let data = text.data(using: .utf8),
              let points = try? JSONDecoder().decode([CalibrationPoint].self, from: data)
        else {
            return CalibrationPointTemplates.all
        }
        return CalibrationPointTemplates.normalized(points)
    }
}
