# Changelog

All notable changes to Codex Island are recorded here.

## [v0.2.1] - 2026-08-11

### Added

- Added an English and Simplified Chinese language switch for island status, sessions, and usage views.
- Added workspace filtering with usage, recent-activity, and name sorting modes.
- Added hover emphasis for usage cards and exact values for daily chart bars.

### Improved

- Refined the Usage dashboard layout, typography, compact chart sizing, empty-value placement, and workspace selector affordance.
- Kept workspace menus inside the expanded island so selecting a project no longer triggers an unintended collapse.
- Improved localized duration and date formatting so longer Chinese values remain readable.

### Fixed

- Limited the workspace picker and aggregate usage totals to projects explicitly imported into Codex.
- Mapped sessions created from project subdirectories back to their imported Codex workspace root.
- Removed temporary and unknown session directories from workspace choices and usage totals.

### Verification

- `swift test`: 55 tests passed.

## [v0.2.0] - 2026-08-11

### Added

- Added a local Usage dashboard with Sessions and Usage tabs.
- Added token and active-time views for today, the last 7 days, and the last 30 days.
- Added a compact seven-day chart with exact daily values on hover.
- Added cache hit rate, cached token savings, average usage, peak day, activity streak, and top-model statistics.
- Added custom completion sounds with in-app selection, reset, and mute controls.

### Improved

- Made island expansion and collapse smoother while keeping genuine pointer exits immediate.
- Kept the expanded panel attached to the top edge and improved built-in MacBook notch adaptation.
- Cached usage aggregation to reduce repeated local database and transcript reads.
- Kept Sessions as the default expanded tab and aligned the Usage dashboard with the island's dark visual style.

### Fixed

- Prevented stale sessions from leaving the island permanently in Running state.
- Recognized manually interrupted Codex responses as stopped work.
- Avoided false completion alerts during context compaction and transient completion events.
- Kept macOS notification banners disabled by default while preserving completion sounds.

### Verification

- `swift test`: 52 tests passed.
