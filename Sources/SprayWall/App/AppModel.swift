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

        try? LegacyStoreMigrationService.migrateHoldsAndBouldersIfNeeded(context: context)
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
        try? KeychainService.save(key: Self.lastLoggedInUserSnapshotKey, data: encodedSnapshot)
    }

    private func restoreLastUserSnapshotIfNeeded(email: String?, context: ModelContext) -> UserAccount? {
        guard let snapshotData = try? KeychainService.load(key: Self.lastLoggedInUserSnapshotKey),
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
        KeychainService.delete(key: Self.lastLoggedInUserSnapshotKey)
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

}
