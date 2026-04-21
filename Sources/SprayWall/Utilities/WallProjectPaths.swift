import Foundation

enum WallProjectPathError: Error, LocalizedError {
    case emptyPath
    case photoNotFound(String)
    case documentsDirectoryUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyPath:
            return "Please provide a photo path first."
        case let .photoNotFound(path):
            return "Photo not found at path: \(path)"
        case .documentsDirectoryUnavailable:
            return "Could not resolve app documents directory."
        }
    }
}

enum WallProjectPaths {
    static let projectFolderName = "wall_project"

    static func documentsDirectory() throws -> URL {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw WallProjectPathError.documentsDirectoryUnavailable
        }
        return url
    }

    static func projectDirectory() throws -> URL {
        try documentsDirectory().appendingPathComponent(projectFolderName, isDirectory: true)
    }

    @discardableResult
    static func ensureProjectDirectory() throws -> URL {
        let directory = try projectDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func resolvePhotoURL(from path: String) throws -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw WallProjectPathError.emptyPath
        }

        let fileManager = FileManager.default

        let absolute = URL(fileURLWithPath: trimmed)
        if absolute.isFileURL, fileManager.fileExists(atPath: absolute.path) {
            return absolute
        }

        let projectRelative = try projectDirectory().appendingPathComponent(trimmed)
        if fileManager.fileExists(atPath: projectRelative.path) {
            return projectRelative
        }

        throw WallProjectPathError.photoNotFound(trimmed)
    }

    static func defaultPhotoOriginalURL() throws -> URL {
        try projectDirectory().appendingPathComponent("photo_original.jpg")
    }

    static func defaultMainWallRectifiedURL() throws -> URL {
        try projectDirectory().appendingPathComponent("main_wall_rectified.png")
    }

    static func defaultKickboardRectifiedURL() throws -> URL {
        try projectDirectory().appendingPathComponent("kickboard_rectified.png")
    }

    static func primaryModelStoreURL() throws -> URL {
        try projectDirectory().appendingPathComponent("spraywall.sqlite")
    }
}
