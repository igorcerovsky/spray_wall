import Foundation
import SwiftData

@Model
final class Hold {
    @Attribute(.unique) var holdID: Int
    var xCm: Double
    var yCm: Double
    var planeRaw: String
    var roleRaw: String

    var isStart: Bool
    var isTop: Bool
    var isStartFoot: Bool

    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Grip.hold)
    var grips: [Grip]

    init(
        holdID: Int,
        xCm: Double,
        yCm: Double,
        plane: HoldPlane,
        role: HoldRole,
        isStart: Bool = false,
        isTop: Bool = false,
        isStartFoot: Bool = false,
        createdAt: Date = .now,
        grips: [Grip] = []
    ) {
        self.holdID = holdID
        self.xCm = xCm
        self.yCm = yCm
        self.planeRaw = plane.rawValue
        self.roleRaw = role.rawValue
        self.isStart = isStart
        self.isTop = isTop
        self.isStartFoot = isStartFoot
        self.createdAt = createdAt
        self.grips = grips
    }

    var plane: HoldPlane {
        get { HoldPlane(rawValue: planeRaw) ?? .main }
        set { planeRaw = newValue.rawValue }
    }

    var role: HoldRole {
        get { HoldRole(rawValue: roleRaw) ?? .hand }
        set { roleRaw = newValue.rawValue }
    }

    var canAddGrip: Bool {
        role == .microFoot ? grips.isEmpty : grips.count < WallSpec.maxGripPerHold
    }
}

@Model
final class Grip {
    @Attribute(.unique) var id: UUID
    var angleDeg: Double
    var strength: Double
    var precision: Double
    var createdAt: Date

    var hold: Hold?

    init(
        id: UUID = UUID(),
        angleDeg: Double,
        strength: Double,
        precision: Double,
        createdAt: Date = .now,
        hold: Hold? = nil
    ) {
        self.id = id
        self.angleDeg = angleDeg
        self.strength = strength
        self.precision = precision
        self.createdAt = createdAt
        self.hold = hold
    }
}
