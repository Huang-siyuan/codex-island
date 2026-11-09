# DeepSeek Harness 集成

## 适配基线

本机验证对象：DeepSeek Harness Desktop `0.1.0-rc.6`，内置 `@deepseek-ai/dsh 0.2.2-rc.1`。
这是本地 Harness 协议适配，不是把 DeepSeek 模型配置到 Codex。

启动 Harness 后启动 Codex Island，无需填写模型 API Key。客户端从桌面启动日志发现 loopback HTTP 入口，使用临时内存 Cookie；不读取 `.dsh/.credentials.yaml`，不保存或展示启动 Token，也不修改会话存储。

## 功能

- 读取会话列表、工作目录、标题、最近用户消息和助手正文；不展示 reasoning 内容。
- 监控最近六个会话，以及列表中其他运行或等待问题的会话。区分运行、工具执行、等待输入、完成与停止。
- 只有明确的 `turn/end` 完成事件触发完成提醒。启动、重连不补播历史提醒；新一轮开始不能沿用上一轮完成状态。
- 输入请求复用现有提示音设置。权限审批显示等待状态，并交给 Harness 原生界面；不会自动批准。
- 单选、多选、自由文本回答。实时问题走 `$events` / `$events/result`，超时后保留的问题走 `userQuestions/answer`。提交后确认问题从权威投影消失；失败保留草稿，不自动重发。
- 展示本机会话累计 Token 汇总和账号余额／赠送余额，不逐条列出会话与上下文进度。累计 Token 不是日用量，也不是订阅额度；余额按币种保留两位小数展示，内部仍使用服务端精度。账号信息每分钟刷新，也可通过用量页刷新入口更新。
- 连接失败时清除可操作问题和活动会话，保留有缓存标识的用量。账号查询失败显示不可用，不显示为零余额。

## 当前协议边界

- 本机版本未提供已验证的指定会话深链。点击会话卡片激活 Harness 应用，不承诺选中指定会话。
- 精确聚焦会话的智能静默与未读计数仍仅支持 Codex；不会用“整个 Harness 在前台”代替会话身份判断。
- DeepSeek 余额没有映射成 Codex 的订阅额度百分比，也不按未知阈值推送低额度告警。
- 未迁移的旧格式会话不会被 Island 自动迁移。接口或鉴权不兼容时，按连接不可用处理。
- 模型回复和工具结束不是整轮完成；中断不发送完成音。
- 事件字段按容错解析：`turn/end` 的 `reason` 接受 `{kind}` 对象或字符串，未知类型的事件字段与缺失 `data` 按缺省值处理。单条事件的字段类型变化不会中断会话刷新。

## 验证

常规：`swift test`。协议测试使用合成数据与本地 URLProtocol fixture，不操作真实会话。

本机只读联调（需要运行 Harness 且至少一个非空会话）：

```sh
ISLAND_DEEPSEEK_LIVE_TEST=1 swift test --filter deepSeekLivePassiveConnection
```

覆盖 HTTP 鉴权、会话读取、WebSocket 就绪／持续连接和账号读取，不提交真实回答、不调用模型。

中英文／经典深色／macOS 玻璃组件渲染：

```sh
ISLAND_RENDER_DEEPSEEK=1 swift test --filter deepSeekPresentation
```

PNG 输出至系统 `/tmp/deepseek-*.png`。合成问题回答协议已测试，真实用户正在等待的问题未作为联调测试材料提交。

打包沿用 `Scripts/package-app.sh`，无需额外依赖。
