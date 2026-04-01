import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppModel {
    enum AuthMode: String, CaseIterable, Identifiable {
        case login
        case register

        var id: String { rawValue }
    }

    enum AppTab: String, CaseIterable, Identifiable {
        case calibration
        case holds
        case routes
        case attempts
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .calibration:
                return "Calibration"
            case .holds:
                return "Holds"
            case .routes:
                return "Routes"
            case .attempts:
                return "Attempts"
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
            case .routes:
                return "point.topleft.down.curvedto.point.bottomright.up"
            case .attempts:
                return "checklist"
            case .settings:
                return "gear"
            }
        }
    }

    var authMode: AuthMode = .login
    var selectedTab: AppTab = .calibration

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
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    func login(email: String, password: String, context: ModelContext) {
        do {
            currentUser = try AuthService.login(email: email, password: password, context: context)
            authErrorMessage = nil
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
            return
        }

        let descriptor = FetchDescriptor<UserAccount>(sortBy: [SortDescriptor(\.createdAt)])
        if let first = try? context.fetch(descriptor).first {
            currentUser = first
        }
    }

    func ensureCalibrationExists(context: ModelContext) {
        let descriptor = FetchDescriptor<WallCalibration>()
        if let existing = try? context.fetch(descriptor), existing.isEmpty {
            let calibration = WallCalibration()
            context.insert(calibration)
            try? context.save()
        }
    }
}
