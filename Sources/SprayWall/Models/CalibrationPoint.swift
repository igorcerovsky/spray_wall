import Foundation

struct CalibrationPoint: Codable, Identifiable, Hashable {
    let id: String
    let label: String
    var xPx: Double
    var yPx: Double

    init(id: String, label: String, xPx: Double = 0, yPx: Double = 0) {
        self.id = id
        self.label = label
        self.xPx = xPx
        self.yPx = yPx
    }
}

enum CalibrationPointTemplates {
    static let all: [CalibrationPoint] = [
        CalibrationPoint(id: "kb_bl", label: "Kickboard Bottom Left"),
        CalibrationPoint(id: "kb_br", label: "Kickboard Bottom Right"),
        CalibrationPoint(id: "kb_tl", label: "Kickboard Top Left"),
        CalibrationPoint(id: "kb_tr", label: "Kickboard Top Right"),
        CalibrationPoint(id: "mw_bl", label: "Main Wall Bottom Left"),
        CalibrationPoint(id: "mw_br", label: "Main Wall Bottom Right"),
        CalibrationPoint(id: "mw_tl", label: "Main Wall Top Left"),
        CalibrationPoint(id: "mw_tr", label: "Main Wall Top Right")
    ]
}
