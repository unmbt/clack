# ADR-001：终端底层接入策略（自研轻量原生 Stub 与 `moonbit-community/tty` 取舍）

- 状态：Accepted
- 日期：2026-11-25
- 关联：`REQ-INPUT-01`、`REQ-FLOW-02`、`REQ-WEB-01`

## 背景

`unmbt/clack` 需要为 `native`、`js` 与 `wasm` 提供终端原始模式、窗口尺寸查询、非阻塞异步输入及控制序列输出，同时直接服务 `unmbt/moonset`、`unmbt/moon-bump` 等单文件 CLI 工具与浏览器端 `xterm.js` Demo。社区已有低层终端原语库 `moonbit-community/tty`（`moonbit-community/tonyfettes-tty@0.6.2`），需要评估是直接将其作为核心依赖，还是维持 `Terminal` trait 抽象并默认自研轻量原生胶水。

## 核查事实（基于 `moonbit-community/tty@0.6.2` 源码与 `.mbti`）

1. **目标后端限制**：`moonbit-community/tty` 的 `moon.pkg` 声明 `supported_targets = "-all+native+wasm"`，**不支持 `js` 后端**。
2. **Sidecar 体积与运行时释放机制**：`Tty::open()` 依赖 `internal/sidecar/sidecars.generated.mbt`（单文件约 **9.89 MB**，内嵌各 OS/架构预编译 C sidecar 二进制）。运行时每次 `Tty::open()` 需将对应可执行文件解压写入临时目录并启动子进程通信（可由 `TTY_SIDECAR` 覆盖）。
3. **异步生态与接口成熟度**：绑定外部 `moonbitlang/async@0.22.4`（与 `unmbt/moonset` ADR-003 迁移至标准库 `moonbitlang/core/async` 的路线冲突）；仓库声明尚处早期，且 `Tty::stdio()` 调用 `enter_raw_mode` / `window_size` 会抛出 `OSError(ENOTSUP)`，`leave_raw_mode` / `close` 在公开签名中尚未标注 `nocancel`。
4. **能力重叠**：`clack/ansi` 与 `clack/core` 已经自建零依赖 SGR 样式器、`KeyDecoder`（含 Bracketed Paste）和 `InlineDiffRenderer`，不需要再引入第二套 VT 序列层与输入事件树。

## 决策

1. **不将 `moonbit-community/tty` 作为 `unmbt/clack` 的默认底层依赖**。
2. 在 `unmbt/clack/term` 层保持 `@term.Terminal` trait 作为唯一 I/O 边界，默认提供：
   - `native`：轻量 `native_stub.c`（参考 `moonset/cli/tty_native.c` 实战经验）配合 `moonbitlang/core/async/stdio`；
   - `js`：Node.js / Deno / Bun CLI 适配器，以及面向浏览器 `xterm.js` 的 `CallbackTerminal`；
   - `wasm`：基于 `core/async/stdio` 与非交互/行缓冲优雅降级；
   - 测试桩：`VirtualTerminal` 内存确定性终端。
3. 将 `moonbit-community/tty` 保留为**未来的独立可选适配包**（例如 `unmbt/clack-tty`），实现 `@term.Terminal` trait，供明确需要 `moonrun` Wasm 交互或 Kitty 键盘增强协议的下游按需引入。

## 依据

- 保持核心零第三方依赖、极小单文件分发体积，并彻底规避“运行时往 `/tmp` 释放可执行文件”引发的 Windows Defender / EDR 拦截及 Linux `noexec` 挂载失效问题。
- 同时打通 `native` CLI（`moonset`）与 `js`（Node/浏览器 `xterm.js` Demo）全链路。

## 后果

- `unmbt/clack/term` 需自行维护约 300～400 行跨平台 `native_stub.c`（termios + Win32 Console API）及异步输入桥接，并独立覆盖 Windows / Linux / macOS 实机验证。
- 核心库在 `native` 之外的 `wasm`（如 `moonrun`）默认走非交互策略或行缓冲回退，不内置 sidecar 子进程。
