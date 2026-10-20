# Changelog

All notable changes to Codex Island are recorded here.

## [Unreleased]

### Added — 2026-10-20

- 展开后的 Codex 会话卡片新增「未读 / Unread」标签，与运行状态并列，直接标出需要查看的会话；与收起栏共用未读数据，随 Codex 已读状态刷新，展开或跳转不主动清除未读。

- 设置「通用」新增「显示模式」下拉框，可选择「跟随聚焦」或「每个屏幕一个刘海」，默认跟随聚焦，切换立即生效并保存到下次启动。
- 每屏模式为已连接显示器分别维护面板；展开、页面选择及菜单栏尺寸彼此独立，会话、用量与设置共享，轮询和通知仍只执行一份。屏幕变化时增减对应面板。

### Improved — 2026-10-20

- 会话卡片移除 Codex 来源标签，保留未读、运行状态和时间；其他工具会话继续显示来源以便区分。

### Fixed — 2026-10-20

- 修复用户已回复输入请求、任务继续运行时仍显示「等待输入」的问题：兼容桌面端 `response_item / message / user` 回复记录，实时轮询及重启后重读均清除已回答的请求；助手或系统消息不视为用户回复。
- 双屏下跟随前台应用最前面的正常窗口，不再被同应用更大的窗口固定在另一屏；补充同应用窗口切换检测，鼠标、键盘切换或拖动窗口跨屏后自动更新刘海位置，仅在目标屏变化时重新布局。
- 修正副屏位于主屏上方时的屏幕坐标换算，避免把窗口映射到错误屏幕。

### Verification — 2026-10-20

- 会话未读标签版本的 `swift test --jobs 2`：120 项测试通过，覆盖同数量下未读会话切换、已读刷新、数据不可用和其他提供方同 ID 隔离；使用真实 SwiftUI 组件与隔离样例检查中英文、经典深色/macOS 玻璃、长标题及辅助功能标签。Release 构建和签名通过，安装文件与打包产物 SHA-256 一致，安装后的应用启动、会话展开正常。

- 等待输入修复的 `swift test --jobs 2`：121 项测试通过，覆盖桌面端普通回复、输入卡片回复、重启重读、后续新问题及其他角色消息。真实会话在截图时刻的记录回放由等待输入恢复为运行中；Release 安装后的原会话卡片显示「运行中」，签名校验通过，安装二进制与打包产物 SHA-256 一致。
- 显示模式版本的 `swift test --jobs 2`：119 项测试通过，新增偏好默认值与恢复、独立面板状态、中英文选项，以及模式切换、屏幕快照增减和退出清理测试。屏幕断开/重连通过注入快照覆盖，未物理拔插显示器。
- 实机验证 HP D27k 与 Mi Monitor 每屏各一个刘海、第二个面板独立导航、切回跟随只保留一个面板、重启恢复每屏模式；中文/英文、经典深色/macOS 玻璃布局与下拉框辅助功能名称、当前值通过检查。最终保留原有中文、玻璃和跟随聚焦设置。
- 最终安装版本通过同应用双窗口跨屏切换及移动窗口五阶段回归；Release 签名通过，安装二进制与打包产物 SHA-256 一致。
- `swift test --jobs 2`：114 项测试通过，新增 7 项屏幕选择回归测试。
- Release 构建、签名校验和安装完成，安装后的可执行文件与打包产物 SHA-256 一致。
- 在 HP D27k 与 Mi Monitor 两块真实屏幕上，用同一临时应用的大小窗口来回切换四次，并移动活跃窗口跨屏，刘海均跟随到目标屏幕；实时面板位置检查通过。上下排列屏幕通过坐标单元测试覆盖，未调整真实显示器排列。

### Added — 2026-10-19

- 设置页新增提示音「试听」按钮，可直接试听当前选用的完成提示音。对应提交：`a506758`。
- 新增等待用户输入提示：面板和会话显示「等待输入 / Input needed」，每个新输入请求播放一次提示音，沿用提示音开关和自定义音频；用户回复、请求取消或任务结束后退出等待状态，启动时不补播历史请求。对应提交：`c0b4a35`。
- 收起栏新增当前登录账号、本机普通 Codex 会话的未读数量，覆盖最近列表之外的旧会话；按方案三显示完整的「3 未读 / 3 unread」，替换最初的数字徽标，不再使用 `9+` 截断。零未读隐藏文字及分隔线，数据不可用时通过悬浮说明明确提示；在 Codex 中已读后随轮询更新，展开 Island 本身不会清除未读。对应提交：`c3f7729`、`732e963`。

### Fixed — 2026-10-19

- 从本地会话文件增量读取任务生命周期事件，恢复任务结束后的提示音；区分任务完成、中断和后续新轮次，避免重复提醒及启动时补播旧完成事件。对应提交：`1deb3f7`。
- 收到明确的 `task_complete` 事件后不再额外等待六秒，下一次轮询识别完成即可触发提示音；仅报告模型响应完成的兼容路径仍保留静默期确认。对应提交：`fabd3dd`。
- 修复未读数量虚高：按当前账号和本机执行环境匹配本地未读状态，排除内部子 Agent、隐藏或未知来源、已归档及已删除会话，不再把未读缓存中的全部 ID 计入。对应提交：`f37a1f7`。
- 收起栏按当前状态、语言和实际未读文字动态调整宽度，移除最长英文文字的固定预留及窗口层宽度下限；零未读时自动收窄，有未读时按内容扩展，保持居中并以短动画过渡。对应提交：`e7b1ea3`。

### Verification — 2026-10-19

- 功能提交 `e7b1ea3` 的 `swift test`：107 项测试通过，覆盖任务完成、输入请求去重、未读过滤，以及不同状态、语言和未读位数下的宽度变化。
- 该功能版本的 Release 构建、签名和安装已完成，安装后的可执行文件与打包产物 SHA-256 一致。
- 实机确认中文「运行中」、零未读时收起栏由约 196 点缩至 81 点，展开后再次收起正常；使用实际 SwiftUI 组件验证中英文、两种外观以及 0、3、21、123456 未读的显示，文字完整。
- 本次补记仅修改更新日志，按 Git 提交日期归档；文档 diff 和提交引用已核对，`git diff --check` 通过，未重复执行功能测试或重新打包。

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
