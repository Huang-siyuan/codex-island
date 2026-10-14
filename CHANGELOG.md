# Changelog

All notable changes to Codex Island are recorded here.

## [Unreleased]

### Improved — 2026-10-14（面板内设置）

- 齿轮按钮改为在浮动面板内部显示设置页，与会话、用量互相切换，不再打开独立设置窗口。
- 设置页沿用当前面板外观；语言和外观使用内嵌分段选项，保留自启动、提示音开关、自定义音效和恢复默认的功能。

### Verification — 2026-10-14（面板内设置）

- `swift test --jobs 2`：76 个测试通过；提示音开关与面板窗口检查脚本、release 构建、严格签名和安装包一致性检查通过。
- 实机验证齿轮在原面板内切换设置、切回会话和用量，以及中英文、两种外观、提示音开关与音频选择取消；测试后恢复原有偏好。

### Added — 2026-10-14（集中设置）

- 将语言、外观、提示音开关、自定义音效和恢复内置音效集中到独立设置窗口，面板只保留一个齿轮入口。
- 新增「开机自启动」勾选框，通过 macOS 登录项注册和取消；读取系统真实状态，保留待批准提示和操作失败信息，不在启动时自动注册。

### Verification — 2026-10-14（集中设置）

- `swift test --jobs 2`：76 个测试通过，覆盖登录项注册、取消、待批准、失败重试及系统外部变更；提示音开关检查通过。
- 安装后的应用可从齿轮按钮打开设置窗口，实际勾选、取消自启动均成功，测试后恢复关闭；未执行真实重启或注销。
- release 构建、安装包可执行文件一致性、严格签名校验和 `git diff --check` 通过。

### Added — 2026-10-14

- 内置由正弦波合成的 0.8 秒轻柔双音完成提示音，未指定自定义音效或自定义文件失效时自动使用；静音设置保持生效。
- 清除自定义音效后恢复内置提示音，音效按钮提示当前默认选择；应用打包时携带音频资源。

### Verification — 2026-10-14

- `swift test --jobs 2`：71 个测试通过，覆盖默认音、自定义音效优先、失效文件回退、静音和清除自定义选择。
- release 构建、提示音开关脚本和发布 ZIP 检查通过；独立打包探针在禁止访问 SwiftPM 构建资源时成功加载、播放内置音。
- 已安装并启动本地新版，安装包与构建包的可执行文件及音频一致，`codesign --verify --deep --strict` 和 `git diff --check` 通过。

### Fixed — 2026-10-09

- 按逐请求 `token_usage_record.payload.usage` 统计输入＋输出，缓存输入包含在输入内，不额外相加；不使用会话或轮次累计量充当本次消耗。
- 用 `response_id` 对跨文件复制、续接和重复写入的请求去重；每次刷新从缓存的请求记录重建去重集合，保留增量读取。
- 有逐请求记录后忽略后续显示计数器，防止延迟计数器、重复通知和压缩后的旧值再次累加。旧格式优先读取 `last_token_usage`；只有累计计数时先建立基线，再统计后续非回退差值。
- 将快照版本升级至 3，升级后自动重建旧统计缓存。缓存卡片改为“已计入”，并说明本地请求用量包含缓存输入且不等同于结算账单。

### Verification — 2026-10-09

- `swift test --jobs 2`：66 个测试通过，覆盖续接累计量、重复响应、压缩请求、延迟和重复显示计数器、旧格式兼容、增量刷新和旧缓存迁移。
- `swift build --jobs 2` 和 release 构建通过。安装并启动新版后，确认使用新快照版本、缓存卡片文案和修正后的当前日用量；安装包与构建包的可执行文件一致，签名验证通过。
- 使用脱敏的本地用量事件按固定截止时间重放，与独立逐请求计数对账；分组总量与整体总量一致。
- `git diff --check` 通过。

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
