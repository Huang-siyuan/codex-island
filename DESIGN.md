# Codex Island 设计语言

Codex Island 是常驻屏幕顶部的轻量浮动面板。会话、用量和设置共用一套视觉语言：深色半透明表面、清晰的文字层级、胶囊控件和克制的绿色强调。设置在原面板内切换。

## 颜色与材质

颜色的唯一入口是 `Sources/CodexIslandApp/IslandDesign.swift` 中的 `IslandPalette`。

| 语义 | 使用位置 |
| --- | --- |
| `title` | 标题、正文、选中项文字，白色 95% |
| `subtitle` | 次要信息、未选中控件，白色 72% |
| `muted` | 时间、说明、图表注释，白色 56% |
| `accent` | 选中状态、勾选框、图表主色、完成状态，RGB 0.28 / 0.86 / 0.55 |
| `surface` / `emphasizedSurface` | 普通卡片 / 当前会话，白色 5% / 10% |
| `border` / `separator` | 卡片描边 / 分隔线，白色 9% / 10% |
| `selectedSurface` / `selectedBorder` | 所有单选项和导航的选中背景 / 描边 |
| `hoverSurface` / `pressedSurface` | 悬停 / 按下反馈 |
| `tool` / `running` / `completed` / `passive` / `error` | 业务状态；同时保留文字，不能只靠颜色传达状态 |

经典深色使用 `classicBackground`；macOS 玻璃使用原生 `NSVisualEffectView` 的 HUD 材质与统一的 `glassTint` / `glassHighlight`。二者共用前景色、卡片、按钮和选择状态。根视图统一使用深色环境，避免系统浅色模式把个别控件绘制成另一套配色。玻璃的实际底色随桌面背景变化。

## 排版与布局

- 使用系统字体。`IslandTypography` 提供页面标题 14 semibold、分组标题 12 semibold、正文 12、控件 11 semibold、说明 11 medium。
- 用量大数字、图表微型标签和会话代码预览允许保留其专用字号与等宽字体。
- `IslandLayout`：区块间距 12、卡片内边距 14、卡片圆角 16、面板圆角 28、控件最小高度 28。
- 卡片使用连续圆角。操作和导航使用胶囊；勾选框保留可辨认的方形轮廓。紧凑菜单项和图表标记可以采用更小圆角。
- 通过空间和文字层级分组，避免增加独立的不透明底色或装饰阴影。

## 共用组件

`Sources/CodexIslandApp/IslandControls.swift` 定义交互控件；`IslandDesign.swift` 定义表面与材质。

| 组件 | 使用方式 |
| --- | --- |
| `IslandSurface` | 卡片背景与描边；`emphasized` 标识当前会话，`highlighted` 标识数据卡片悬停 |
| `IslandButtonStyle` | 导航、设置动作、刷新和筛选入口；`isSelected` 统一选中效果，包含悬停、按下和禁用反馈 |
| `IslandChoiceGroup` | 语言、外观、统计指标、排序等单选组；保留分组名称和选中辅助功能语义 |
| `IslandCheckboxStyle` | 自启动、提示音等布尔配置；统一勾选颜色，保留原生 checkbox 的辅助功能角色、值和操作 |
| `IslandSeparator` | 统一细分隔线，避免系统 Divider 与额外遮罩叠加 |
| `IslandOverlayBackground` | 用量菜单和图表提示的背景，与面板外观同步 |

设置持久化、系统授权和数据刷新仍由原有 model/store 管理；视觉组件只负责展示与绑定。按钮保留 SwiftUI 的键盘激活与焦点行为，不用 tap 手势替代控件。图表的悬停详情和面板展开收起沿用现有行为。

## 后续修改与验收

新增页面先复用以上语义色和组件；确有新的视觉语义时，在共用定义中补充并更新本文件，避免在页面中再次定义一套调色板。同种状态必须使用相同反馈。

交付界面改动时至少检查：

1. 经典深色与 macOS 玻璃中的会话、用量、设置，文字和选择状态均清晰。
2. 中文与英文布局、长标题、条件出现的错误或授权提示没有截断关键操作。
3. 默认、选中、悬停、按下、禁用状态；勾选框与单选组的辅助功能值正确。
4. 设置仍在同一个浮动面板内，切换后尺寸和悬停收起正常；打包安装后的实际应用与源码一致。
