# Changelog

All notable changes to Codex Island are recorded here.

## [Unreleased]

### Fixed — 2026-10-05

- Added a localized manual refresh button beside the Usage dashboard's update time, with a progress indicator and disabled state while a refresh is running.
- Manual refresh now bypasses the 30-minute snapshot cache while retaining incremental transcript reads. Ordinary requests keep the existing cache interval; no background refresh timer was added.
- Included topic and projectless Codex sessions in overall token usage, active time, run counts, cache statistics, and model totals. Imported workspace roots now control grouping instead of excluding sessions from the aggregate.
- Added a localized "Topics / No project" group for sessions outside imported workspaces or without a working directory, and renamed the aggregate filter to "All sessions".
- Invalidated snapshots produced by the previous project-only accounting so the first load after upgrading rebuilds the cached totals.

### Development notes

- A pushed source fix does not replace the installed app. The running bundle was still an older build, so the updated app must be packaged, installed, and relaunched for the accounting and refresh controls to appear.
- Manual and automatic usage requests share one in-flight task. The button cannot queue duplicate scans, and unchanged transcript files keep their parsed results in memory.
- The earlier workspace filter skipped unmatched sessions before merging overall usage. Group assignment now happens after that merge; project subdirectories still resolve to the most specific imported root.
- Kept the existing local transcript source and 30-day scan window. This change does not add cloud or archived-session data sources.

### Verification

- Manual refresh: `swift build --jobs 2` succeeded and `swift test --jobs 2` passed all 62 tests. The added regression covers a recent cached snapshot, appended usage visible only after forcing refresh, repeated refresh without double counting, and persisted cache reload.
- Installed and relaunched the release bundle: verified nonzero current-day topic usage, the topic filter, preserved macOS Glass, and a manual refresh updating both totals and timestamp. A 15-second idle observation found no usage-cache rewrite; installed and packaged executables match and code signing verification passed.
- `swift build` succeeded; `swift test` passed all 61 tests, including projectless grouping, scoped-total reconciliation, incremental refresh, and cache migration coverage.
- A read-only scan of current-day local transcripts counted previously excluded topic usage and confirmed that the sum of group totals equals overall usage.
- `git diff --check` passed.

### Added

- Added a persistent appearance switch between Classic Dark and macOS Glass.
- Added a native macOS glass backdrop that samples and blurs content behind the island window.

### Improved

- Matched the macOS Dock more closely with a dark HUD material, purple-to-blue environmental tint, top highlight, and thin luminous border.
- Applied the glass treatment consistently to the Usage workspace menu and chart tooltip.

### Fixed

- Removed the opaque gray layer and outer corner shadow that made the glass appearance look like a solid panel.

### Verification

- `swift test`: 57 tests passed.
- Window chrome and active-screen-following checks passed.
- Integration verification on 2026-10-05: merged the projectless-usage fix from `main` while retaining both appearance modes; `swift build --jobs 2` succeeded and `swift test --jobs 2` passed all 61 tests.

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
