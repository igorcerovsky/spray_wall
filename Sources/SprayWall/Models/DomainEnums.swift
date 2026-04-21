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

enum BoulderStatus: String, Codable, CaseIterable, Identifiable {
    case draft
    case established

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}

enum BoulderHoldGroup: String, Codable, CaseIterable, Identifiable {
    case start
    case hold
    case foothold
    case top

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .start:
            return "Start"
        case .hold:
            return "Hold"
        case .foothold:
            return "Foothold"
        case .top:
            return "Top"
        }
    }
}
