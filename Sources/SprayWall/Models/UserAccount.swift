import Foundation
import SwiftData

@Model
final class UserAccount {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var email: String
    var displayName: String
    var passwordHash: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        email: String,
        displayName: String,
        passwordHash: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.passwordHash = passwordHash
        self.createdAt = createdAt
    }
}
