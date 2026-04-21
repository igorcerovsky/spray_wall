import Foundation
import SwiftData

@Model
final class Boulder {
    @Attribute(.unique) var boulderID: Int
    var name: String

    var statusRaw: String

    var startHoldIDsCSV: String
    var holdIDsCSV: String
    var footholdIDsCSV: String
    var topHoldIDsCSV: String

    var grade: String
    var setter: String
    var tags: String
    var notes: String
    var attemptCount: Int
    var ascentLogged: Bool
    var ascentLoggedAt: Date?

    var createdAt: Date
    var updatedAt: Date

    init(
        boulderID: Int,
        name: String,
        status: BoulderStatus = .draft,
        startHoldIDs: [Int] = [],
        holdIDs: [Int] = [],
        footholdIDs: [Int] = [],
        topHoldIDs: [Int] = [],
        grade: String = "",
        setter: String = "",
        tags: String = "",
        notes: String = "",
        attemptCount: Int = 0,
        ascentLogged: Bool = false,
        ascentLoggedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.boulderID = boulderID
        self.name = name
        self.statusRaw = status.rawValue
        self.startHoldIDsCSV = CSVIntCodec.encode(startHoldIDs)
        self.holdIDsCSV = CSVIntCodec.encode(holdIDs)
        self.footholdIDsCSV = CSVIntCodec.encode(footholdIDs)
        self.topHoldIDsCSV = CSVIntCodec.encode(topHoldIDs)
        self.grade = grade
        self.setter = setter
        self.tags = tags
        self.notes = notes
        self.attemptCount = attemptCount
        self.ascentLogged = ascentLogged
        self.ascentLoggedAt = ascentLoggedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var status: BoulderStatus {
        get { BoulderStatus(rawValue: statusRaw) ?? .draft }
        set {
            statusRaw = newValue.rawValue
            touch()
        }
    }

    var startHoldIDs: [Int] {
        get { CSVIntCodec.decode(startHoldIDsCSV) }
        set {
            startHoldIDsCSV = CSVIntCodec.encode(newValue)
            touch()
        }
    }

    var holdIDs: [Int] {
        get { CSVIntCodec.decode(holdIDsCSV) }
        set {
            holdIDsCSV = CSVIntCodec.encode(newValue)
            touch()
        }
    }

    var footholdIDs: [Int] {
        get { CSVIntCodec.decode(footholdIDsCSV) }
        set {
            footholdIDsCSV = CSVIntCodec.encode(newValue)
            touch()
        }
    }

    var topHoldIDs: [Int] {
        get { CSVIntCodec.decode(topHoldIDsCSV) }
        set {
            topHoldIDsCSV = CSVIntCodec.encode(newValue)
            touch()
        }
    }

    func contains(_ holdID: Int) -> Bool {
        startHoldIDs.contains(holdID) || holdIDs.contains(holdID) || footholdIDs.contains(holdID) || topHoldIDs.contains(holdID)
    }

    func role(for holdID: Int) -> BoulderHoldGroup? {
        if startHoldIDs.contains(holdID) { return .start }
        if holdIDs.contains(holdID) { return .hold }
        if footholdIDs.contains(holdID) { return .foothold }
        if topHoldIDs.contains(holdID) { return .top }
        return nil
    }

    @discardableResult
    func assign(_ holdID: Int, to group: BoulderHoldGroup) -> String? {
        switch group {
        case .start:
            if !startHoldIDs.contains(holdID), startHoldIDs.count >= 2 {
                return "Cannot add more than 2 start holds."
            }
        case .top:
            if !topHoldIDs.contains(holdID), topHoldIDs.count >= 2 {
                return "Cannot add more than 2 top holds."
            }
        case .hold, .foothold:
            break
        }

        remove(holdID)

        switch group {
        case .start:
            startHoldIDs = startHoldIDs + [holdID]
        case .hold:
            holdIDs = holdIDs + [holdID]
        case .foothold:
            footholdIDs = footholdIDs + [holdID]
        case .top:
            topHoldIDs = topHoldIDs + [holdID]
        }

        dedupeAll()
        return nil
    }

    func remove(_ holdID: Int) {
        startHoldIDs = startHoldIDs.filter { $0 != holdID }
        holdIDs = holdIDs.filter { $0 != holdID }
        footholdIDs = footholdIDs.filter { $0 != holdID }
        topHoldIDs = topHoldIDs.filter { $0 != holdID }
    }

    func validateForEstablish(existingHoldIDs: Set<Int>) -> [String] {
        var issues: [String] = []

        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Name is required.")
        }

        if !(1...2).contains(startHoldIDs.count) {
            issues.append("Start holds must contain 1 or 2 holds.")
        }

        if topHoldIDs.isEmpty {
            issues.append("Top holds must contain at least one hold.")
        }

        if topHoldIDs.count > 2 {
            issues.append("Top holds can contain at most two holds.")
        }

        let allIDs = startHoldIDs + holdIDs + footholdIDs + topHoldIDs
        let uniqueCount = Set(allIDs).count
        if uniqueCount != allIDs.count {
            issues.append("Each hold can belong to exactly one group in a boulder.")
        }

        let missing = Set(allIDs).subtracting(existingHoldIDs)
        if !missing.isEmpty {
            let sorted = missing.sorted().map(String.init).joined(separator: ", ")
            issues.append("Unknown hold IDs: \(sorted)")
        }

        return issues
    }

    func normalizeForDraft() {
        dedupeAll()
    }

    @discardableResult
    func logAttempt() -> String? {
        guard status == .established else {
            return "Attempts can be logged only for established boulders."
        }

        guard !ascentLogged else {
            return "Ascent already logged. Attempt count is locked."
        }

        attemptCount += 1
        touch()
        return nil
    }

    @discardableResult
    func logAscent() -> String? {
        guard status == .established else {
            return "Ascent can be logged only for established boulders."
        }

        guard !ascentLogged else {
            return "Ascent already logged."
        }

        ascentLogged = true
        ascentLoggedAt = .now
        touch()
        return nil
    }

    private func dedupeAll() {
        startHoldIDs = deduped(startHoldIDs)
        holdIDs = deduped(holdIDs)
        footholdIDs = deduped(footholdIDs)
        topHoldIDs = deduped(topHoldIDs)

        for id in startHoldIDs {
            holdIDs.removeAll { $0 == id }
            footholdIDs.removeAll { $0 == id }
            topHoldIDs.removeAll { $0 == id }
        }

        for id in holdIDs {
            footholdIDs.removeAll { $0 == id }
            topHoldIDs.removeAll { $0 == id }
        }

        for id in footholdIDs {
            topHoldIDs.removeAll { $0 == id }
        }

        if startHoldIDs.count > 2 {
            startHoldIDs = Array(startHoldIDs.suffix(2))
        }

        if topHoldIDs.count > 2 {
            topHoldIDs = Array(topHoldIDs.suffix(2))
        }
    }

    private func deduped(_ values: [Int]) -> [Int] {
        var seen = Set<Int>()
        var output: [Int] = []

        for value in values where !seen.contains(value) {
            seen.insert(value)
            output.append(value)
        }

        return output
    }

    private func touch() {
        updatedAt = .now
    }
}
