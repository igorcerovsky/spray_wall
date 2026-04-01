# Spray Wall App (MVP Scaffold)

This repository now contains an initial SwiftUI + SwiftData scaffold for the Spray Wall app.

## Scope implemented

- iOS-first SwiftUI app architecture (package scaffold)
- Multi-user auth (register/login)
- Wall calibration screen with 8 reference points
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

## Notes

- Current environment has Xcode Command Line Tools only, so iOS simulator builds were not executed here.
- Open in Xcode and run on iOS 17+ target.

## Data model highlights

- Hold IDs, route IDs, and attempt IDs are generated with monotonic increment (`max + 1`) and never reused.
- Kickboard is set to **90 degrees from floor** per requirement.
