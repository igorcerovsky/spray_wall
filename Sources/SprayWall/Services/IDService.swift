import Foundation
import SwiftData

enum IDService {
    static func nextHoldID(in context: ModelContext) throws -> Int {
        var descriptor = FetchDescriptor<Hold>(sortBy: [SortDescriptor(\.holdID, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try context.fetch(descriptor).first?.holdID ?? 0) + 1
    }

    static func nextRouteID(in context: ModelContext) throws -> Int {
        var descriptor = FetchDescriptor<Route>(sortBy: [SortDescriptor(\.routeID, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try context.fetch(descriptor).first?.routeID ?? 0) + 1
    }

    static func nextAttemptID(in context: ModelContext) throws -> Int {
        var descriptor = FetchDescriptor<Attempt>(sortBy: [SortDescriptor(\.attemptID, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try context.fetch(descriptor).first?.attemptID ?? 0) + 1
    }
}
