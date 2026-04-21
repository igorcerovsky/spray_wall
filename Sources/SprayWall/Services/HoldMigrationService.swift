import Foundation
import SwiftData

enum HoldMigrationService {
    private static let migrationVersionKey = "spraywall.hold_migration_version"
    private static let currentMigrationVersion = 1

    static func migrateToCurrentVersion(context: ModelContext) throws {
        let defaults = UserDefaults.standard
        let appliedVersion = defaults.integer(forKey: migrationVersionKey)
        guard appliedVersion < currentMigrationVersion else {
            return
        }

        let holds = try context.fetch(FetchDescriptor<Hold>(sortBy: [SortDescriptor(\.holdID)]))
        guard !holds.isEmpty else {
            defaults.set(currentMigrationVersion, forKey: migrationVersionKey)
            return
        }

        var changed = false
        var usedIDs = Set<Int>()
        var maxID = holds.map(\.holdID).max() ?? 0

        for hold in holds {
            if hold.holdID <= 0 || usedIDs.contains(hold.holdID) {
                maxID += 1
                hold.holdID = maxID
                changed = true
            }
            usedIDs.insert(hold.holdID)

            let clampedX = clamp(hold.xCm, min: 0, max: WallSpec.widthCm)
            if clampedX != hold.xCm {
                hold.xCm = clampedX
                changed = true
            }

            let clampedY = clamp(hold.yCm, min: 0, max: WallSpec.totalHeightCm)
            if clampedY != hold.yCm {
                hold.yCm = clampedY
                changed = true
            }

            let expectedPlane: HoldPlane = hold.yCm <= WallSpec.kickboardHeightCm ? .kickboard : .main
            if hold.plane != expectedPlane {
                hold.plane = expectedPlane
                changed = true
            }

            if HoldRole(rawValue: hold.roleRaw) == nil {
                hold.role = .hand
                changed = true
            }

            let orderedGrips = hold.grips.sorted { $0.createdAt < $1.createdAt }
            let maxGrips = hold.role == .microFoot ? 1 : WallSpec.maxGripPerHold
            if orderedGrips.count > maxGrips {
                for grip in orderedGrips.dropFirst(maxGrips) {
                    context.delete(grip)
                }
                changed = true
            }

            for grip in orderedGrips.prefix(maxGrips) {
                let normalizedAngle = normalizedDegrees(grip.angleDeg)
                if normalizedAngle != grip.angleDeg {
                    grip.angleDeg = normalizedAngle
                    changed = true
                }

                let clampedStrength = clamp(grip.strength, min: 0, max: 1)
                if clampedStrength != grip.strength {
                    grip.strength = clampedStrength
                    changed = true
                }

                let clampedPrecision = clamp(grip.precision, min: 0, max: 1)
                if clampedPrecision != grip.precision {
                    grip.precision = clampedPrecision
                    changed = true
                }
            }
        }

        if changed {
            try context.save()
        }

        defaults.set(currentMigrationVersion, forKey: migrationVersionKey)
    }

    private static func clamp(_ value: Double, min minimum: Double, max maximum: Double) -> Double {
        Swift.min(Swift.max(value, minimum), maximum)
    }

    private static func normalizedDegrees(_ value: Double) -> Double {
        var output = value.truncatingRemainder(dividingBy: 360)
        if output < 0 {
            output += 360
        }
        return output
    }
}
