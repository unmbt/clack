# 决策记录（ADR）

ADR 文件记录影响多个包或开发阶段的关键架构决策。修改已接受（`Accepted`）决策时必须新建编号递增的 ADR 替代或补充，严禁直接覆写历史 ADR 的既有决策结论。

| 编号 | 决策主题 | 状态 |
| :--- | :--- | :--- |
| [ADR-001](001-tty-backend-strategy.md) | 终端底层接入策略：自研轻量原生 Stub 与 `moonbit-community/tty` 取舍 | Accepted |
| [ADR-002](002-core-async-and-multi-target-web-demo.md) | 对齐 `moonset` 采用 `moonbitlang/core/async` 与多目标 / 浏览器 `xterm.js` Demo 架构 | Accepted |
| [ADR-003](003-prompt-model-abstraction.md) | 规避无关联类型限制的 `PromptAdapter[T]` 组件抽象 | Accepted |
| [ADR-004](004-terminal-lifecycle-and-resize.md) | 终端安全生命周期、异步可取消读、Esc 消歧与 Resize / 视口保护 | Accepted |
