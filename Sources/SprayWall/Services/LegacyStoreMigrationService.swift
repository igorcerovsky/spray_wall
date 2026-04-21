import Foundation
import SwiftData

enum LegacyStoreMigrationService {
    private static let migrationKey = "spraywall.legacy_holds_boulders_migration_v1"

    static func migrateHoldsAndBouldersIfNeeded(context: ModelContext) throws {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: migrationKey) {
            return
        }

        let currentHoldsCount = try context.fetchCount(FetchDescriptor<Hold>())
        let currentBouldersCount = try context.fetchCount(FetchDescriptor<Boulder>())
        if currentHoldsCount > 0 || currentBouldersCount > 0 {
            defaults.set(true, forKey: migrationKey)
            return
        }

        let schema = Schema([
            UserAccount.self,
            Hold.self,
            Grip.self,
            Boulder.self,
            Route.self,
            Attempt.self,
            WallCalibration.self
        ])

        guard let legacyContainer = try? ModelContainer(for: schema) else {
            defaults.set(true, forKey: migrationKey)
            return
        }

        let legacyContext = ModelContext(legacyContainer)
        let legacyHolds = try legacyContext.fetch(FetchDescriptor<Hold>(sortBy: [SortDescriptor(\.holdID)]))
        let legacyBoulders = try legacyContext.fetch(FetchDescriptor<Boulder>(sortBy: [SortDescriptor(\.boulderID)]))

        if legacyHolds.isEmpty && legacyBoulders.isEmpty {
            defaults.set(true, forKey: migrationKey)
            return
        }

        var insertedSomething = false

        for legacyHold in legacyHolds {
            let holdID = legacyHold.holdID
            let existingDescriptor = FetchDescriptor<Hold>(
                predicate: #Predicate<Hold> { hold in
                    hold.holdID == holdID
                }
            )
            if try context.fetchCount(existingDescriptor) > 0 {
                continue
            }

            let newHold = Hold(
                holdID: legacyHold.holdID,
                xCm: legacyHold.xCm,
                yCm: legacyHold.yCm,
                plane: legacyHold.plane,
                role: legacyHold.role,
                isStart: legacyHold.isStart,
                isTop: legacyHold.isTop,
                isStartFoot: legacyHold.isStartFoot,
                createdAt: legacyHold.createdAt
            )
            context.insert(newHold)

            for legacyGrip in legacyHold.grips {
                let newGrip = Grip(
                    id: legacyGrip.id,
                    angleDeg: legacyGrip.angleDeg,
                    strength: legacyGrip.strength,
                    precision: legacyGrip.precision,
                    createdAt: legacyGrip.createdAt,
                    hold: newHold
                )
                context.insert(newGrip)
                newHold.grips.append(newGrip)
            }

            insertedSomething = true
        }

        for legacyBoulder in legacyBoulders {
            let boulderID = legacyBoulder.boulderID
            let existingDescriptor = FetchDescriptor<Boulder>(
                predicate: #Predicate<Boulder> { boulder in
                    boulder.boulderID == boulderID
                }
            )
            if try context.fetchCount(existingDescriptor) > 0 {
                continue
            }

            let newBoulder = Boulder(
                boulderID: legacyBoulder.boulderID,
                name: legacyBoulder.name,
                status: legacyBoulder.status,
                startHoldIDs: legacyBoulder.startHoldIDs,
                holdIDs: legacyBoulder.holdIDs,
                footholdIDs: legacyBoulder.footholdIDs,
                topHoldIDs: legacyBoulder.topHoldIDs,
                grade: legacyBoulder.grade,
                setter: legacyBoulder.setter,
                tags: legacyBoulder.tags,
                notes: legacyBoulder.notes,
                rating: legacyBoulder.rating,
                attemptCount: legacyBoulder.attemptCount,
                ascentLogged: legacyBoulder.ascentLogged,
                ascentLoggedAt: legacyBoulder.ascentLoggedAt,
                createdAt: legacyBoulder.createdAt,
                updatedAt: legacyBoulder.updatedAt
            )
            context.insert(newBoulder)
            insertedSomething = true
        }

        if insertedSomething {
            try context.save()
        }

        defaults.set(true, forKey: migrationKey)
    }
}
