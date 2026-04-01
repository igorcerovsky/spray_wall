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
        get { CSVIntCodec.decode(startHoldIDsCSV) }
        set { startHoldIDsCSV = CSVIntCodec.encode(newValue) }
    }

    var startFootIDs: [Int] {
        get { CSVIntCodec.decode(startFootIDsCSV) }
        set { startFootIDsCSV = CSVIntCodec.encode(newValue) }
    }

    var sequenceIDs: [Int] {
        get { CSVIntCodec.decode(sequenceIDsCSV) }
        set { sequenceIDsCSV = CSVIntCodec.encode(newValue) }
    }

    var topHoldIDs: [Int] {
        get { CSVIntCodec.decode(topHoldIDsCSV) }
        set { topHoldIDsCSV = CSVIntCodec.encode(newValue) }
    }

    var topMode: TopMode {
        get { TopMode(rawValue: topModeRaw) ?? .match }
        set { topModeRaw = newValue.rawValue }
    }
}
