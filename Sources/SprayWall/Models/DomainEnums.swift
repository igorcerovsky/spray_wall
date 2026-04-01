import Foundation

enum HoldPlane: String, Codable, CaseIterable, Identifiable {
    case main
    case kickboard

    var id: String { rawValue }
}

enum HoldRole: String, Codable, CaseIterable, Identifiable {
    case hand
    case foot
    case microFoot = "micro_foot"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hand:
            return "Hand"
        case .foot:
            return "Foot"
        case .microFoot:
            return "Micro Foot"
        }
    }
}

enum TopMode: String, Codable, CaseIterable, Identifiable {
    case match
    case touch

    var id: String { rawValue }
}

enum AttemptResult: String, Codable, CaseIterable, Identifiable {
    case success
    case failure

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}
