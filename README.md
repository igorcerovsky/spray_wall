# Spray Wall App (MVP Scaffold)

This repository now contains an initial SwiftUI + SwiftData scaffold for the Spray Wall app.

## Scope implemented

- iOS-first SwiftUI app architecture (package scaffold)
- Multi-user auth (register/login)
- Wall calibration screen with 8 reference points
- In-app photo picking from the device photo library (imports to `wall_project/photo_original.jpg`)
- Real image rectification pipeline:
  - Perspective correction for main wall and kickboard using calibration points
  - Output files: `main_wall_rectified.png` and `kickboard_rectified.png`
- Hold editor:
  - Tap canvas to add hold
  - Drag hold to move
  - Context menu delete
  - Hold detail + grip editing
- Route editor:
  - Create/edit routes
  - Active route preview (single route at a time)
- Attempt logger:
  - Log success/failure against a route
  - Attempt history
- Settings:
  - JSON export/import for project data
  - Logout
- SwiftData persistence (SQLite-backed)
- Native Xcode project generator: `Tools/generate_xcodeproj.rb`
- App model and architecture refactored for security (Keychain), performance (batched archive imports), and modern data typing (native `[Int]` properties instead of CSV strings).

## Notes

- Generate the native Xcode project with:
  - `gem install --user-install xcodeproj` (or `bundle install`)
  - `ruby Tools/generate_xcodeproj.rb`
- Build/test shortcuts:
  - `make ios-build`
  - `make ios-test`
  - `make ios-destinations`
  - CLI targets disable code signing (`CODE_SIGNING_ALLOWED=NO`) for local/CI validation.
- Open `SprayWall.xcodeproj` in Xcode and run on iOS 17+ target.
- `swift test` passes in this repository.

## Data model highlights

- Hold IDs, route IDs, and attempt IDs are generated with monotonic increment (`max + 1`) and never reused.
- Kickboard is set to **90 degrees from floor** per requirement.
