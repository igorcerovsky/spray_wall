import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppModel {
    private static let lastLoggedInEmailKey = "spraywall.last_logged_in_email"
    private static let lastLoggedInUserSnapshotKey = "spraywall.last_logged_in_user_snapshot"

    private struct PersistedUserSnapshot: Codable {
        var id: UUID
        var email: String
        var displayName: String
        var passwordHash: String
        var createdAt: Date
    }

    enum AuthMode: String, CaseIterable, Identifiable {
        case login
        case register

        var id: String { rawValue }
    }

    enum AppTab: String, CaseIterable, Identifiable {
        case calibration
        case holds
        case boulder
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .calibration:
                return "Calibration"
            case .holds:
                return "Holds"
            case .boulder:
                return "Boulder"
            case .settings:
                return "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .calibration:
                return "viewfinder"
            case .holds:
                return "circle.grid.cross"
            case .boulder:
                return "slider.horizontal.3"
            case .settings:
                return "gear"
            }
        }
    }

    var authMode: AuthMode = .login
    var selectedTab: AppTab = .boulder

    var didBootstrap = true

    var currentUser: UserAccount?
    var authErrorMessage: String?
    var globalMessage: String?

    var isAuthenticated: Bool {
        currentUser != nil
    }

    func register(displayName: String, email: String, password: String, context: ModelContext) {
        do {
            currentUser = try AuthService.register(
                displayName: displayName,
                email: email,
                password: password,
                context: context
            )
            authErrorMessage = nil
            persistLoggedInUser()
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    func login(email: String, password: String, context: ModelContext) {
        do {
            currentUser = try AuthService.login(email: email, password: password, context: context)
            authErrorMessage = nil
            persistLoggedInUser()
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    func logout() {
        currentUser = nil
        authMode = .login
    }

    func bootstrap(context: ModelContext) {
        if currentUser != nil {
            didBootstrap = true
            return
        }

        try? migrateLegacyHoldsAndBouldersIfNeeded(context: context)
        try? HoldMigrationService.migrateToCurrentVersion(context: context)
        try? migrateBoulderRatings(context: context)

        let persistedEmail = UserDefaults.standard.string(forKey: Self.lastLoggedInEmailKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let persistedEmail, !persistedEmail.isEmpty {
            let descriptor = FetchDescriptor<UserAccount>(sortBy: [SortDescriptor(\.createdAt)])
            if let account = try? context.fetch(descriptor).first(where: { $0.email == persistedEmail }) {
                currentUser = account
                persistLoggedInUser()
                return
            }

            if let restored = restoreLastUserSnapshotIfNeeded(email: persistedEmail, context: context) {
                currentUser = restored
                persistLoggedInUser()
                return
            }
        }

        // Migration fallback for older installs that don't have persisted login key yet.
        let fallbackDescriptor = FetchDescriptor<UserAccount>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        if let fallbackUser = try? context.fetch(fallbackDescriptor).first {
            currentUser = fallbackUser
            persistLoggedInUser()
            didBootstrap = true
            return
        }

        // Last resort: restore from snapshot even if persisted email key is missing.
        if let restored = restoreLastUserSnapshotIfNeeded(email: nil, context: context) {
            currentUser = restored
            persistLoggedInUser()
        }

        didBootstrap = true
    }

    func ensureCalibrationExists(context: ModelContext) {
        let descriptor = FetchDescriptor<WallCalibration>()
        if let existing = try? context.fetch(descriptor), existing.isEmpty {
            let calibration = WallCalibration()
            context.insert(calibration)
            try? context.save()
        }
    }

    private func persistLoggedInUser() {
        guard let user = currentUser else {
            return
        }

        let email = user.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !email.isEmpty else {
            return
        }

        let snapshot = PersistedUserSnapshot(
            id: user.id,
            email: email,
            displayName: user.displayName,
            passwordHash: user.passwordHash,
            createdAt: user.createdAt
        )

        guard let encodedSnapshot = try? JSONEncoder().encode(snapshot) else {
            UserDefaults.standard.set(email, forKey: Self.lastLoggedInEmailKey)
            return
        }

        UserDefaults.standard.set(email, forKey: Self.lastLoggedInEmailKey)
        UserDefaults.standard.set(encodedSnapshot, forKey: Self.lastLoggedInUserSnapshotKey)
    }

    private func restoreLastUserSnapshotIfNeeded(email: String?, context: ModelContext) -> UserAccount? {
        guard let snapshotData = UserDefaults.standard.data(forKey: Self.lastLoggedInUserSnapshotKey),
              let snapshot = try? JSONDecoder().decode(PersistedUserSnapshot.self, from: snapshotData)
        else {
            return nil
        }

        let normalizedSnapshotEmail = snapshot.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedSnapshotEmail.isEmpty else {
            return nil
        }

        if let email, normalizedSnapshotEmail != email {
            return nil
        }

        let descriptor = FetchDescriptor<UserAccount>(sortBy: [SortDescriptor(\.createdAt)])
        if let existing = try? context.fetch(descriptor).first(where: { $0.email == normalizedSnapshotEmail }) {
            return existing
        }

        let restored = UserAccount(
            id: snapshot.id,
            email: normalizedSnapshotEmail,
            displayName: snapshot.displayName,
            passwordHash: snapshot.passwordHash,
            createdAt: snapshot.createdAt
        )
        context.insert(restored)
        try? context.save()
        return restored
    }

    private func clearPersistedLogin() {
        UserDefaults.standard.removeObject(forKey: Self.lastLoggedInEmailKey)
        UserDefaults.standard.removeObject(forKey: Self.lastLoggedInUserSnapshotKey)
    }

    private func migrateBoulderRatings(context: ModelContext) throws {
        let key = "spraywall.boulder_migration_version"
        let currentVersion = 1
        let defaults = UserDefaults.standard

        let appliedVersion = defaults.integer(forKey: key)
        guard appliedVersion < currentVersion else {
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

        defaults.set(currentVersion, forKey: key)
    }

    private func migrateLegacyHoldsAndBouldersIfNeeded(context: ModelContext) throws {
        let key = "spraywall.legacy_holds_boulders_migration_v1"
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: key) {
            return
        }

        let currentHoldsCount = try context.fetchCount(FetchDescriptor<Hold>())
        let currentBouldersCount = try context.fetchCount(FetchDescriptor<Boulder>())
        if currentHoldsCount > 0 || currentBouldersCount > 0 {
            defaults.set(true, forKey: key)
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
            defaults.set(true, forKey: key)
            return
        }

        let legacyContext = ModelContext(legacyContainer)
        let legacyHolds = try legacyContext.fetch(FetchDescriptor<Hold>(sortBy: [SortDescriptor(\.holdID)]))
        let legacyBoulders = try legacyContext.fetch(FetchDescriptor<Boulder>(sortBy: [SortDescriptor(\.boulderID)]))

        if legacyHolds.isEmpty && legacyBoulders.isEmpty {
            defaults.set(true, forKey: key)
            return
        }

        var changed = false

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

            changed = true
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
            changed = true
        }

        if changed {
            try context.save()
        }

        defaults.set(true, forKey: key)
    }
}
