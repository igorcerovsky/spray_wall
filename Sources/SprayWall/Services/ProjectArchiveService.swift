import Foundation
import SwiftData

struct ProjectArchive: Codable {
    var version: Int
    var exportedAt: Date
    var geometry: GeometryDTO
    var calibration: CalibrationDTO?
    var users: [UserAccountDTO]
    var holds: [HoldDTO]
    var routes: [RouteDTO]
    var attempts: [AttemptDTO]
}

struct GeometryDTO: Codable {
    var wallWidthCm: Double
    var mainWallHeightCm: Double
    var kickboardHeightCm: Double
    var mainWallAngleDegFromFloor: Double
    var kickboardAngleDegFromFloor: Double
}

struct CalibrationDTO: Codable {
    var id: UUID
    var photoPath: String
    var points: [CalibrationPoint]
    var createdAt: Date
    var updatedAt: Date
}

struct UserAccountDTO: Codable {
    var id: UUID
    var email: String
    var displayName: String
    var passwordHash: String
    var createdAt: Date
}

struct HoldDTO: Codable {
    var holdID: Int
    var xCm: Double
    var yCm: Double
    var plane: String
    var role: String
    var isStart: Bool
    var isTop: Bool
    var isStartFoot: Bool
    var createdAt: Date
    var grips: [GripDTO]
}

struct GripDTO: Codable {
    var id: UUID
    var angleDeg: Double
    var strength: Double
    var precision: Double
    var createdAt: Date
}

struct RouteDTO: Codable {
    var routeID: Int
    var name: String
    var startHolds: [Int]
    var startFeet: [Int]
    var sequence: [Int]
    var topHolds: [Int]
    var topMode: String
    var createdAt: Date
}

struct AttemptDTO: Codable {
    var attemptID: Int
    var routeID: Int
    var climberID: UUID
    var date: Date
    var result: String
    var notes: String
}

enum ProjectArchiveService {
    static func exportJSON(context: ModelContext) throws -> String {
        let archive = try exportArchive(context: context)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archive)
        return String(decoding: data, as: UTF8.self)
    }

    static func importJSON(_ text: String, context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(ProjectArchive.self, from: Data(text.utf8))
        try importArchive(archive, context: context)
    }

    static func exportArchive(context: ModelContext) throws -> ProjectArchive {
        let users = try context.fetch(FetchDescriptor<UserAccount>())
        let holds = try context.fetch(FetchDescriptor<Hold>())
        let routes = try context.fetch(FetchDescriptor<Route>())
        let attempts = try context.fetch(FetchDescriptor<Attempt>())
        let calibration = try context.fetch(FetchDescriptor<WallCalibration>()).first

        return ProjectArchive(
            version: 1,
            exportedAt: .now,
            geometry: GeometryDTO(
                wallWidthCm: WallSpec.widthCm,
                mainWallHeightCm: WallSpec.mainWallHeightCm,
                kickboardHeightCm: WallSpec.kickboardHeightCm,
                mainWallAngleDegFromFloor: WallSpec.mainWallAngleDegFromFloor,
                kickboardAngleDegFromFloor: WallSpec.kickboardAngleDegFromFloor
            ),
            calibration: calibration.map {
                CalibrationDTO(
                    id: $0.id,
                    photoPath: $0.photoPath,
                    points: $0.points,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            users: users.map {
                UserAccountDTO(
                    id: $0.id,
                    email: $0.email,
                    displayName: $0.displayName,
                    passwordHash: $0.passwordHash,
                    createdAt: $0.createdAt
                )
            },
            holds: holds.map {
                HoldDTO(
                    holdID: $0.holdID,
                    xCm: $0.xCm,
                    yCm: $0.yCm,
                    plane: $0.planeRaw,
                    role: $0.roleRaw,
                    isStart: $0.isStart,
                    isTop: $0.isTop,
                    isStartFoot: $0.isStartFoot,
                    createdAt: $0.createdAt,
                    grips: $0.grips.map {
                        GripDTO(
                            id: $0.id,
                            angleDeg: $0.angleDeg,
                            strength: $0.strength,
                            precision: $0.precision,
                            createdAt: $0.createdAt
                        )
                    }
                )
            },
            routes: routes.map {
                RouteDTO(
                    routeID: $0.routeID,
                    name: $0.name,
                    startHolds: $0.startHoldIDs,
                    startFeet: $0.startFootIDs,
                    sequence: $0.sequenceIDs,
                    topHolds: $0.topHoldIDs,
                    topMode: $0.topModeRaw,
                    createdAt: $0.createdAt
                )
            },
            attempts: attempts.map {
                AttemptDTO(
                    attemptID: $0.attemptID,
                    routeID: $0.routeID,
                    climberID: $0.climberID,
                    date: $0.date,
                    result: $0.resultRaw,
                    notes: $0.notes
                )
            }
        )
    }

    static func importArchive(_ archive: ProjectArchive, context: ModelContext) throws {
        for dto in archive.users {
            let normalizedEmail = dto.email.lowercased()
            let descriptor = FetchDescriptor<UserAccount>(
                predicate: #Predicate<UserAccount> { account in
                    account.email == normalizedEmail
                }
            )

            if let existing = try context.fetch(descriptor).first {
                existing.displayName = dto.displayName
                existing.passwordHash = dto.passwordHash
            } else {
                let account = UserAccount(
                    id: dto.id,
                    email: normalizedEmail,
                    displayName: dto.displayName,
                    passwordHash: dto.passwordHash,
                    createdAt: dto.createdAt
                )
                context.insert(account)
            }
        }

        for dto in archive.holds {
            let id = dto.holdID
            let descriptor = FetchDescriptor<Hold>(
                predicate: #Predicate<Hold> { hold in
                    hold.holdID == id
                }
            )

            let hold: Hold
            if let existing = try context.fetch(descriptor).first {
                hold = existing
            } else {
                let created = Hold(
                    holdID: dto.holdID,
                    xCm: dto.xCm,
                    yCm: dto.yCm,
                    plane: HoldPlane(rawValue: dto.plane) ?? .main,
                    role: HoldRole(rawValue: dto.role) ?? .hand,
                    isStart: dto.isStart,
                    isTop: dto.isTop,
                    isStartFoot: dto.isStartFoot,
                    createdAt: dto.createdAt
                )
                context.insert(created)
                hold = created
            }

            hold.xCm = dto.xCm
            hold.yCm = dto.yCm
            hold.planeRaw = dto.plane
            hold.roleRaw = dto.role
            hold.isStart = dto.isStart
            hold.isTop = dto.isTop
            hold.isStartFoot = dto.isStartFoot

            let incomingGripIDs = Set(dto.grips.map(\.id))
            for grip in hold.grips where !incomingGripIDs.contains(grip.id) {
                context.delete(grip)
            }

            for gripDTO in dto.grips {
                if let existingGrip = hold.grips.first(where: { $0.id == gripDTO.id }) {
                    existingGrip.angleDeg = gripDTO.angleDeg
                    existingGrip.strength = gripDTO.strength
                    existingGrip.precision = gripDTO.precision
                } else {
                    let grip = Grip(
                        id: gripDTO.id,
                        angleDeg: gripDTO.angleDeg,
                        strength: gripDTO.strength,
                        precision: gripDTO.precision,
                        createdAt: gripDTO.createdAt,
                        hold: hold
                    )
                    context.insert(grip)
                    hold.grips.append(grip)
                }
            }
        }

        for dto in archive.routes {
            let id = dto.routeID
            let descriptor = FetchDescriptor<Route>(
                predicate: #Predicate<Route> { route in
                    route.routeID == id
                }
            )

            if let route = try context.fetch(descriptor).first {
                route.name = dto.name
                route.startHoldIDs = dto.startHolds
                route.startFootIDs = dto.startFeet
                route.sequenceIDs = dto.sequence
                route.topHoldIDs = dto.topHolds
                route.topModeRaw = dto.topMode
            } else {
                let route = Route(
                    routeID: dto.routeID,
                    name: dto.name,
                    startHolds: dto.startHolds,
                    startFeet: dto.startFeet,
                    sequence: dto.sequence,
                    topHolds: dto.topHolds,
                    topMode: TopMode(rawValue: dto.topMode) ?? .match,
                    createdAt: dto.createdAt
                )
                context.insert(route)
            }
        }

        for dto in archive.attempts {
            let id = dto.attemptID
            let descriptor = FetchDescriptor<Attempt>(
                predicate: #Predicate<Attempt> { attempt in
                    attempt.attemptID == id
                }
            )

            if let attempt = try context.fetch(descriptor).first {
                attempt.routeID = dto.routeID
                attempt.climberID = dto.climberID
                attempt.date = dto.date
                attempt.resultRaw = dto.result
                attempt.notes = dto.notes
            } else {
                let attempt = Attempt(
                    attemptID: dto.attemptID,
                    routeID: dto.routeID,
                    climberID: dto.climberID,
                    date: dto.date,
                    result: AttemptResult(rawValue: dto.result) ?? .failure,
                    notes: dto.notes
                )
                context.insert(attempt)
            }
        }

        if let calibrationDTO = archive.calibration {
            let id = calibrationDTO.id
            let descriptor = FetchDescriptor<WallCalibration>(
                predicate: #Predicate<WallCalibration> { calibration in
                    calibration.id == id
                }
            )

            if let calibration = try context.fetch(descriptor).first {
                calibration.photoPath = calibrationDTO.photoPath
                calibration.points = calibrationDTO.points
            } else {
                let calibration = WallCalibration(
                    id: calibrationDTO.id,
                    photoPath: calibrationDTO.photoPath,
                    points: calibrationDTO.points,
                    createdAt: calibrationDTO.createdAt,
                    updatedAt: calibrationDTO.updatedAt
                )
                context.insert(calibration)
            }
        }

        try context.save()
    }
}
