import Foundation
import SwiftData

@Model
final class Route {
    @Attribute(.unique) var routeID: Int
    var name: String

    var startHoldIDsCSV: String
    var startFootIDsCSV: String
    var sequenceIDsCSV: String
    var topHoldIDsCSV: String

    var startHoldIDsArray: [Int]?
    var startFootIDsArray: [Int]?
    var sequenceIDsArray: [Int]?
    var topHoldIDsArray: [Int]?

    var topModeRaw: String
    var createdAt: Date

    init(
        routeID: Int,
        name: String,
        startHolds: [Int] = [],
        startFeet: [Int] = [],
        sequence: [Int] = [],
        topHolds: [Int] = [],
        topMode: TopMode = .match,
        createdAt: Date = .now
    ) {
        self.routeID = routeID
        self.name = name
        self.startHoldIDsCSV = CSVIntCodec.encode(startHolds)
        self.startFootIDsCSV = CSVIntCodec.encode(startFeet)
        self.sequenceIDsCSV = CSVIntCodec.encode(sequence)
        self.topHoldIDsCSV = CSVIntCodec.encode(topHolds)
        self.topModeRaw = topMode.rawValue
        self.createdAt = createdAt
    }

    var startHoldIDs: [Int] {
        get { startHoldIDsArray ?? CSVIntCodec.decode(startHoldIDsCSV) }
        set {
            startHoldIDsArray = newValue
            startHoldIDsCSV = CSVIntCodec.encode(newValue)
        }
    }

    var startFootIDs: [Int] {
        get { startFootIDsArray ?? CSVIntCodec.decode(startFootIDsCSV) }
        set {
            startFootIDsArray = newValue
            startFootIDsCSV = CSVIntCodec.encode(newValue)
        }
    }

    var sequenceIDs: [Int] {
        get { sequenceIDsArray ?? CSVIntCodec.decode(sequenceIDsCSV) }
        set {
            sequenceIDsArray = newValue
            sequenceIDsCSV = CSVIntCodec.encode(newValue)
        }
    }

    var topHoldIDs: [Int] {
        get { topHoldIDsArray ?? CSVIntCodec.decode(topHoldIDsCSV) }
        set {
            topHoldIDsArray = newValue
            topHoldIDsCSV = CSVIntCodec.encode(newValue)
        }
    }

    var topMode: TopMode {
        get { TopMode(rawValue: topModeRaw) ?? .match }
        set { topModeRaw = newValue.rawValue }
    }
}
