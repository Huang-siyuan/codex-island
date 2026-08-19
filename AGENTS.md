# Codex Island 开发约束

## 提交规则

- 用户每次提出的独立修改要求，都必须形成一次独立 commit，不得把多次要求混在同一个 commit 中。
- commit message 必须准确概括本次修改，优先使用 Conventional Commits，例如 `fix: ...`、`feat: ...`、`refactor: ...`、`docs: ...`。
- 提交前检查实际 diff，只暂存本次要求涉及的文件，不得顺带提交无关修改。
- 完成后向用户明确说明分支名、commit hash、commit message 和验证结果。

## Bug 修复流程

- 每次修复 Bug 前，先同步最新 `main`，再从 `main` 创建独立的 `fix/<short-description>` 分支；不得直接在 `main` 上开发或提交 Bug 修复。
- Bug 修复必须包含与风险匹配的验证；可自动化覆盖时，应增加或更新回归测试。
- 验证通过后，将修复 commit 推送到远端分支并创建 Pull Request。
- 确认修复有效且 PR 可合并后，才可合并到 `main`；合并完成后同步本地 `main`。
- 不得在未验证、测试失败或存在未确认阻塞时合并。

## 修改完成标准

- 代码修改、测试、commit、远端分支、Pull Request 和合并状态必须保持一致。
- 如果用户只要求诊断，不修改代码、不创建 commit，也不创建分支或 Pull Request。
