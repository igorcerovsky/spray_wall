import Foundation
import Testing
@testable import SprayWall

@Test("WallProjectPaths resolves project resources photo")
func testResolveProjectPhoto() throws {
    let resolved = try WallProjectPaths.resolvePhotoURL(from: "resources/281026_dd.jpeg")
    #expect(FileManager.default.fileExists(atPath: resolved.path))
    #expect(resolved.lastPathComponent == "281026_dd.jpeg")
}

@Test("WallCalibration default photo path is resources/281026_dd.jpeg")
func testDefaultPhotoPath() throws {
    #expect(WallCalibration.defaultPhotoPath == "resources/281026_dd.jpeg")
    let resolved = try WallProjectPaths.resolvePhotoURL(from: WallCalibration.defaultPhotoPath)
    #expect(FileManager.default.fileExists(atPath: resolved.path))
}

@Test("WallProjectPaths legacy fallback redirects to resources photo")
func testLegacyPhotoFallback() throws {
    let resolved = try WallProjectPaths.resolvePhotoURL(from: "photo_original.jpg")
    #expect(FileManager.default.fileExists(atPath: resolved.path))
}

