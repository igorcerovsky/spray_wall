import Foundation

struct CalibrationPoint: Codable, Identifiable, Hashable {
    let id: String
    let label: String
    var xPx: Double
    var yPx: Double
    var xCm: Double
    var yCm: Double

    init(
        id: String,
        label: String,
        xPx: Double = 0,
        yPx: Double = 0,
        xCm: Double? = nil,
        yCm: Double? = nil
    ) {
        self.id = id
        self.label = label
        self.xPx = xPx
        self.yPx = yPx

        let fallback = CalibrationPointTemplates.defaultWorldCoordinate(for: id)
        self.xCm = xCm ?? fallback?.x ?? 0
        self.yCm = yCm ?? fallback?.y ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case xPx
        case yPx
        case xCm
        case yCm
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        xPx = try container.decodeIfPresent(Double.self, forKey: .xPx) ?? 0
        yPx = try container.decodeIfPresent(Double.self, forKey: .yPx) ?? 0

        if let decodedXCm = try container.decodeIfPresent(Double.self, forKey: .xCm),
           let decodedYCm = try container.decodeIfPresent(Double.self, forKey: .yCm) {
            xCm = decodedXCm
            yCm = decodedYCm
        } else {
            let fallback = CalibrationPointTemplates.defaultWorldCoordinate(for: id)
            xCm = fallback?.x ?? 0
            yCm = fallback?.y ?? 0
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(xPx, forKey: .xPx)
        try container.encode(yPx, forKey: .yPx)
        try container.encode(xCm, forKey: .xCm)
        try container.encode(yCm, forKey: .yCm)
    }
}

enum CalibrationPointTemplates {
    static let all: [CalibrationPoint] = [
        CalibrationPoint(id: "kb_bl", label: "Kickboard Bottom Left", xPx: 1800, yPx: 500),
        CalibrationPoint(id: "kb_br", label: "Kickboard Bottom Right", xPx: 6000, yPx: 300),
        CalibrationPoint(id: "kb_tl", label: "Kickboard Top Left", xPx: 1900, yPx: 1200),
        CalibrationPoint(id: "kb_tr", label: "Kickboard Top Right", xPx: 6000, yPx: 1100),
        CalibrationPoint(id: "mw_bl", label: "Main Wall Bottom Left", xPx: 1900, yPx: 1200),
        CalibrationPoint(id: "mw_br", label: "Main Wall Bottom Right", xPx: 6000, yPx: 1100),
        CalibrationPoint(id: "mw_tl", label: "Main Wall Top Left", xPx: 560, yPx: 5500),
        CalibrationPoint(id: "mw_tr", label: "Main Wall Top Right", xPx: 8800, yPx: 5700)
    ]

    static func defaultWorldCoordinate(for id: String) -> (x: Double, y: Double)? {
        switch id {
        case "kb_bl":
            return (0, 0)
        case "kb_br":
            return (WallSpec.widthCm, 0)
        case "kb_tl":
            return (0, WallSpec.kickboardHeightCm)
        case "kb_tr":
            return (WallSpec.widthCm, WallSpec.kickboardHeightCm)
        case "mw_bl":
            return (0, WallSpec.kickboardHeightCm)
        case "mw_br":
            return (WallSpec.widthCm, WallSpec.kickboardHeightCm)
        case "mw_tl":
            return (0, WallSpec.totalHeightCm)
        case "mw_tr":
            return (WallSpec.widthCm, WallSpec.totalHeightCm)
        default:
            return nil
        }
    }

    static func normalized(_ points: [CalibrationPoint]) -> [CalibrationPoint] {
        let byID = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })

        return all.map { template in
            guard let existing = byID[template.id] else {
                return template
            }

            return CalibrationPoint(
                id: template.id,
                label: template.label,
                xPx: existing.xPx,
                yPx: existing.yPx,
                xCm: existing.xCm,
                yCm: existing.yCm
            )
        }
    }
}
