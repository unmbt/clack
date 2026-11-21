# SDD 规约

## 1. 目标

`unmbt/clack` 采用 **Specification-Driven Development（SDD）**。规格文档与 `declare` 强类型接口契约是可评审、可追踪、可编译验证的产品契约，而不是实现完成后的补写说明书。

每个需求都必须回答四个问题：

1. 输入、交互按键与环境边界在哪里？
2. 成功时可观察到的终端输出、返回值或状态快照是什么？
3. 失败、校验错误、`Ctrl+C` 中断、任务取消或非交互降级时如何恢复终端并报告结果？
4. 用哪个包下的哪个测试或门禁命令证明它成立？

## 2. 追踪关系

```text
REQ-* ID ──▶ 设计章节 (02/03) ──▶ declare 接口契约 ──▶ 测试用例 (*_test.mbt) ──▶ 门禁命令
```

需求 ID 分类规则：

- `REQ-STYLE-*`：颜色能力探测（`NO_COLOR` / `FORCE_COLOR` / `TERM=dumb`）与嵌套 SGR 着色器。
- `REQ-RENDER-*`：行内差分重绘、东亚宽字符/Emoji 折行精度、防撕裂同步输出与视口裁剪。
- `REQ-INPUT-*`：字节流状态机、ESC 消歧与 Bracketed Paste 括号粘贴防误触。
- `REQ-WIDGET-*`：交互式表单组件与静态输出/进度组件（`text`、`password`、`confirm`、`select`、`multiselect`、`group_multiselect`、`autocomplete`、`spinner`、`progress`、`log`）。
- `REQ-FLOW-*`：双主题/双范式门面、`StepBack` 历史栈回退、非交互降级与信号/取消恢复。
- `REQ-WEB-*`：面向浏览器 `xterm.js` Demo 的 `CallbackTerminal` 异步桥接与 `InlineDriver[T]` 纯同步推模式驱动。

## 3. 五步交付节奏

每个实现切片必须严格按以下顺序推进：

1. **冻结需求边界**：在 [requirements.md](spec/requirements.md) 确认 `REQ-*` 的输入边界与验收标准，将状态置为 `Accepted`。
2. **更新契约与 ADR**：同步更新 [architecture-and-contracts.md](spec/architecture-and-contracts.md) 的 `declare` 签名与 [algorithms-and-mechanisms.md](spec/algorithms-and-mechanisms.md) 机制；若变更已接受的架构决策，必须新建 [ADR](decisions/README.md)，严禁覆写历史 ADR。
3. **纯核测试先行**：优先在零 I/O 的 `ansi` 与 `core` 编写同步单元测试与 `debug_inspect` 快照测试（确保四目标兼容），再接入 `term` 与高层包。
4. **严格门禁验证**：通过对应目标的 `moon check --deny-warn`、`moon test`、`moon info` 与 `moon fmt --check`。
5. **回写证据**：在 `requirements.md` 将对应 `REQ-*` 更新为 `Implemented` 并填入测试编号或命令证据。

## 4. v0.1 不可变设计原则

以下原则属于 `unmbt/clack` 的架构不变量，任何实现或优化均不得破坏：

1. **绝不接管全屏**：严禁发送备用屏幕缓冲区切换（`\x1b[?1049h`）或清屏序列（`\x1b[2J` / `\x1b[H`），所有重绘均基于相对光标上移与 `\x1b[J` 行内差分。
2. **纯核零宿主依赖**：`ansi` 与 `core` 严禁依赖 `moonbitlang/core/async`、文件系统、环境变量全局状态或 FFI，始终兼容 `native`、`js`、`wasm`、`wasm-gc`。
3. **零外部第三方运行时依赖**：异步、队列、定时器与标准流仅依赖标准库 `moonbitlang/core` 及其 `moonbitlang/core/async` 子包，不引入外部 `moonbitlang/async` 或第三方侧车二进制。
4. **100% 终端状态恢复**：无论正常提交、校验异常、`Ctrl+C`、`core/async` 协程取消还是进程异常终止，均须通过 `defer` + `nocancel`（及 native 侧 `atexit`/信号守卫）关闭括号粘贴、恢复光标可见性并退出原始模式。
5. **颜色协议严格合规**：当 `NO_COLOR` 非空且代码未显式覆盖时，输出必须为 0 字节 SGR 转义的纯文本。
6. **异步主循环禁止阻塞**：在采用 `core/async` 的原生终端驱动中，严禁在协程调度主线程执行不可中断/不可取消的阻塞式 `read()` 或 `ReadConsoleInputW()`，确保 `with_timeout` 与 `TaskGroup` 取消可即时响应。
