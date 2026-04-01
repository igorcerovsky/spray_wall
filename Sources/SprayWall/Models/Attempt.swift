import Foundation
import SwiftData

@Model
final class Attempt {
    @Attribute(.unique) var attemptID: Int
    var routeID: Int
    var climberID: UUID
    var date: Date
    var resultRaw: String
    var notes: String

    init(
        attemptID: Int,
        routeID: Int,
        climberID: UUID,
        date: Date = .now,
        result: AttemptResult,
        notes: String = ""
    ) {
        self.attemptID = attemptID
        self.routeID = routeID
        self.climberID = climberID
        self.date = date
        self.resultRaw = result.rawValue
        self.notes = notes
    }

    var result: AttemptResult {
        get { AttemptResult(rawValue: resultRaw) ?? .failure }
        set { resultRaw = newValue.rawValue }
    }
}
