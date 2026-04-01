import CryptoKit
import Foundation
import SwiftData

enum AuthError: Error, LocalizedError {
    case invalidEmail
    case weakPassword
    case accountAlreadyExists
    case invalidCredentials

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "Please enter a valid email address."
        case .weakPassword:
            return "Password must be at least 8 characters."
        case .accountAlreadyExists:
            return "An account with this email already exists."
        case .invalidCredentials:
            return "Invalid email or password."
        }
    }
}

enum AuthService {
    static func register(
        displayName: String,
        email: String,
        password: String,
        context: ModelContext
    ) throws -> UserAccount {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalizedEmail.contains("@"), normalizedEmail.contains(".") else {
            throw AuthError.invalidEmail
        }

        guard password.count >= 8 else {
            throw AuthError.weakPassword
        }

        let descriptor = FetchDescriptor<UserAccount>(
            predicate: #Predicate<UserAccount> { account in
                account.email == normalizedEmail
            }
        )

        if let _ = try context.fetch(descriptor).first {
            throw AuthError.accountAlreadyExists
        }

        let account = UserAccount(
            email: normalizedEmail,
            displayName: normalizedName.isEmpty ? "Climber" : normalizedName,
            passwordHash: hash(password)
        )
        context.insert(account)
        try context.save()
        return account
    }

    static func login(email: String, password: String, context: ModelContext) throws -> UserAccount {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let descriptor = FetchDescriptor<UserAccount>(
            predicate: #Predicate<UserAccount> { account in
                account.email == normalizedEmail
            }
        )

        guard let account = try context.fetch(descriptor).first,
              account.passwordHash == hash(password)
        else {
            throw AuthError.invalidCredentials
        }

        return account
    }

    static func hash(_ password: String) -> String {
        let digest = SHA256.hash(data: Data(password.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
