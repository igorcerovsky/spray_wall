import Foundation
import SwiftData

enum BoulderMigrationService {
    private static let migrationVersionKey = "spraywall.boulder_migration_version"
    private static let currentMigrationVersion = 1

    static func migrateToCurrentVersion(context: ModelContext) throws {
        let defaults = UserDefaults.standard
        let appliedVersion = defaults.integer(forKey: migrationVersionKey)
        guard appliedVersion < currentMigrationVersion else {
            return
        }

        let boulders = try context.fetch(FetchDescriptor<Boulder>())
        var changed = false

        for boulder in boulders {
            let clamped = Boulder.clampedRating(boulder.ratingValue ?? 0)
            if boulder.ratingValue != clamped {
                boulder.ratingValue = clamped
                changed = true
            }
        }

        if changed {
            try context.save()
        }

        defaults.set(currentMigrationVersion, forKey: migrationVersionKey)
    }
}
