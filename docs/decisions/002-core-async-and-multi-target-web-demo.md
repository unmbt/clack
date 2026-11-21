# ADR-002：对齐 `moonset` 采用 `moonbitlang/core/async` 与多目标 / 浏览器 `xterm.js` Demo 架构

- 状态：Accepted
- 日期：2026-11-25
- 关联：`REQ-WIDGET-06`、`REQ-FLOW-01`、`REQ-FLOW-02`、`REQ-WEB-01`

## 背景

1. 下游主力消费者 `unmbt/moonset` 已通过 [moonset ADR-003](../../../moonset/docs/decisions/003-core-async.md) 完成向标准库 `moonbitlang/core/async` 的迁移，不再引入外部 `moonbitlang/async` 模块。若 `unmbt/clack` 依赖外部 `moonbitlang/async@0.22.x`，会为下游增加冗余甚至版本冲突的异步运行时依赖。
2. 另一方面，`unmbt/clack` 计划参考 `moonset/doc-web`（Vite + React + `@xterm/xterm`）提供在线交互文档站，需要将真实代码编译为 `js` / `wasm` 并在浏览器页面里的 `xterm.js` 中直接体验。

## 已核查的工具链能力（`moonc v0.10.22` / `moon 0.1.20261119`）

通过核查本机标准库 `lib/core/async` 源码与 `moon.pkg`：

| 标准库包 | 支持目标 | 关键能力与说明 |
| :--- | :--- | :--- |
| `moonbitlang/core/async` | `native`, `js`, `wasm` | 协程调度、`sleep`、`Timer`、`with_timeout(_opt)`、`with_task_group`、`Queue`、`Mutex`、`Semaphore`、`protect_from_cancel`、`handle_cancellation`（`js` 侧基于 `setTimeout` 调度，100% 浏览器兼容；不支持 `wasm-gc`） |
| `moonbitlang/core/async/stdio` | `native`, `wasm` | `stdin` / `stdout` / `stderr`、`fd()`，内置 `windows_console.mbt`（自动 UTF-8 ↔ UTF-16 `ReadConsoleW`/`WriteConsoleW`） |
| `moonbitlang/core/async/js_async` | `js` | `Promise::from_async`、`Promise::wait`、`run_promise`、`AbortController`、`ReadableStream` |
| `moonbitlang/core/async/raw_fd` | `native` | `RawFd` / `RawFdStream` 将原生 fd（如管道读端）接入事件循环 |

## 决策

1. **全面对齐 `moonset` ADR-003**：
   - `unmbt/clack` 的 `moon.mod` **不引入任何外部第三方依赖**，全部异步能力使用标准库 `moonbitlang/core/async` 及其子包；
   - 所有依赖 `core/async*` 的子包在 `moon.pkg` 中显式声明 `options("allow-experimental-packages": [...])`（具体列出所用包名，保持最小权限），并按平台需求使用 `#cfg(...)` 条件导入与 `targets` 文件裁剪。
2. **明确分包目标矩阵**：
   - `ansi`、`core`（零异步纯内核）：不声明 `supported_targets`，原生支持 `native` + `js` + `wasm` + `wasm-gc`。
   - `term`、`prompts`、`minimal`、`flow`、根包 `unmbt/clack`、`cmd/demo`：声明 `supported_targets = "-all+native+js+wasm"`（排除不支持 `core/async` 的 `wasm-gc`）。
3. **浏览器 `xterm.js` Demo 采用双路线架构**：
   - **路线 A（主力推荐 — Full Async JS）**：将完整 `unmbt/clack`（含 `flow`、`prompts`、`Spinner`、`Progress`）以 `--target js` 编译为浏览器 ES Module。通过 `term::CallbackTerminal`（内部以 `@async.Queue[Bytes]` 接收 `xterm.onData` UTF-8 字节、通过 `on_write` 回调写入 `xterm.write`、通过 `set_size` 同步 `FitAddon` 尺寸），并用 `core/async/js_async.Promise::from_async` 导出异步启动/取消句柄给 React 组件。浏览器里运行的是 **100% 真实的 MoonBit 异步向导**。
   - **路线 B（轻量/纯 Wasm — Pure Sync Core `InlineDriver[T]`）**：在零异步、全四目标兼容的 `core` 包提供推模式同步驱动 `InlineDriver[T]`（`start` / `feed` / `flush_escape` / `resize`），可编译为极小的 `--target wasm` / `--target wasm-gc`（或 `--target js`）模块，由 JS 宿主直接转发 `xterm.onData` 并把返回的 ANSI 字符串写入 `xterm.write`。

## 后果

- `unmbt/clack` 成为纯标准库生态的零第三方依赖包，可直接被 `unmbt/moonset`、`unmbt/moon-bump` 等工具零负担接入。
- `term/moon.pkg` 需要谨慎通过 `#cfg(any(target="native", target="wasm"))` 隔离 `core/async/stdio`、通过 `#cfg(target="js")` 隔离 `core/async/js_async`，避免在 `--target js` 上意外拉入仅支持 `native`/`wasm` 的包。
- `wasm`（WASI）后端在非交互管道或无原始模式能力时，仍按 `NonInteractivePolicy` 或行缓冲优雅降级，但纯核 `InlineDriver[T]` 可在浏览器 Wasm 中获得完整实时交互渲染能力。
