# Changelog

All notable changes to Codex Island are recorded here.

## [Unreleased]

### Added — 2026-10-14

- 内置 0.8 秒轻柔双音完成提示音，未指定自定义音效、清除选择或自定义文件丢失、无法解码时自动使用；自定义音效优先，静音设置保持生效，发布包携带音频资源。
- 新增「开机自启动」勾选框，通过 macOS 登录项注册和取消，读取系统真实状态；需要批准时提供系统设置入口，操作失败时保留真实状态并显示错误，默认不主动注册。
- 新增 [设计语言规范](DESIGN.md)，将语义配色、排版、卡片、按钮、单选组和勾选框收敛到共用组件，并加入项目开发约束。

### Improved — 2026-10-14

- 语言、外观、提示音和自启动统一收进齿轮入口；设置直接在浮动面板内部显示，与会话、用量互相切换，不再打开独立设置窗口。
- 会话、用量和设置使用统一的文字层级、卡片、胶囊按钮和绿色选中状态；经典深色与 macOS 玻璃共用前景和控件样式，仅切换底层材质。
- 设置页的单选组和勾选框沿用面板样式，保留勾选框辅助功能角色、值和单选项的选中语义。

### Verification — 2026-10-14

- 最终功能提交 `218d02d` 的 `swift test --jobs 2`：76 个测试通过，覆盖音效回退、静音，以及登录项注册、取消、待批准、失败重试和系统外部变更。
- 提示音开关与面板窗口检查脚本、debug/release 构建、严格签名检查通过；安装后的签名可执行文件与 `dist` 打包产物一致。发布 ZIP 和独立打包音效播放已验证。
- 实机检查面板内设置切换、两种外观、中英文、提示音开关、音频选择取消，以及勾选框和单选组的辅助功能语义；登录项注册与取消已验证，未执行真实重启或注销。
- 最后整理字体引用和背景组件调用后重新完成构建、测试、签名检查和安装；此时 Mac 已锁屏，未重复截图。应用已重新启动。
- `git diff --check` 通过。

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
