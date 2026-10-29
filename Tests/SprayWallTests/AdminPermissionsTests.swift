import Foundation
import Testing
@testable import SprayWall

@MainActor
@Test("Admin permissions identify igor cerovsky")
func testAdminPermissions() throws {
    let appModel = AppModel()

    // Test with matching display name
    let userWithName = UserAccount(email: "climber@spraywall.com", displayName: "igor cerovsky", passwordHash: "dummy")
    appModel.currentUser = userWithName
    #expect(appModel.isAdmin == true)

    // Test with matching email
    let userWithEmail = UserAccount(email: "igor.cerovsky@gmail.com", displayName: "Igor", passwordHash: "dummy")
    appModel.currentUser = userWithEmail
    #expect(appModel.isAdmin == true)

    // Test with non-admin user
    let regularUser = UserAccount(email: "jane.doe@example.com", displayName: "Jane Doe", passwordHash: "dummy")
    appModel.currentUser = regularUser
    #expect(appModel.isAdmin == false)
}
