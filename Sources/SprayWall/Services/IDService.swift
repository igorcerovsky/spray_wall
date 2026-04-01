import Foundation
import SwiftData

enum IDService {
    static func nextHoldID(in context: ModelContext) throws -> Int {
        try nextID(for: Hold.self, keyPath: \.holdID, in: context)
    }

    static func nextRouteID(in context: ModelContext) throws -> Int {
        try nextID(for: Route.self, keyPath: \.routeID, in: context)
    }

    static func nextAttemptID(in context: ModelContext) throws -> Int {
        try nextID(for: Attempt.self, keyPath: \.attemptID, in: context)
    }

    private static func nextID<ModelType: PersistentModel>(
        for model: ModelType.Type,
        keyPath: KeyPath<ModelType, Int>,
        in context: ModelContext
    ) throws -> Int {
        var descriptor = FetchDescriptor<ModelType>()
        descriptor.fetchLimit = 0

        let values = try context.fetch(descriptor).map { $0[keyPath: keyPath] }
        return (values.max() ?? 0) + 1
    }
}
