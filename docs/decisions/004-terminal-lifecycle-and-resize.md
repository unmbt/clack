# ADR-004：终端安全生命周期、异步可取消读、Esc 消歧与 Resize / 视口保护

- 状态：Accepted
- 日期：2026-11-25
- 关联：`REQ-RENDER-01`、`REQ-RENDER-02`、`REQ-INPUT-01`、`REQ-FLOW-02`

## 背景

在复盘 `unmbt/moonset` 的终端实现（`moonset/cli/tty_native.c` 与 `tui_common.mbt` / `tui_render.mbt`）及对照本项目的异步取消、浏览器 `xterm.js`、窄屏中文折行等需求后，识别出 6 类极易引发生产故障的边缘场景：

1. **阻塞读卡死协程调度**：若在 C FFI 中直接对 `STDIN_FILENO` 或 `ReadConsoleInputW` 同步阻塞等待，MoonBit 单线程协作式事件循环会被完全锁死，导致 `core/async` 的 `with_timeout`、`TaskGroup` 取消与 `Spinner` 动画并发刷新全部失效。
2. **Windows 代码页篡改与 IME 乱码**：直接调用 `SetConsoleOutputCP(65001)` 若进程被 `TerminateProcess` 强杀会污染用户原控制台代码页；而禁用 `ENABLE_EXTENDED_FLAGS` 会误伤 Windows Terminal QuickEdit 选区。
3. **孤立 `Esc` 与 CSI 序列拆包混淆**：SSH 或分片读取时，`\x1b[A` 的首字节 `0x1B` 若单独先到，简单按“批次长度为 1 即 `Escape`”会误触发 `StepBack`。
4. **未闭合 Bracketed Paste 锁死键盘**：若终端异常发送 `\x1b[200~` 后丢失 `\x1b[201~`，解码器停留在 `in_paste = true` 会吞掉包括 `Ctrl+C` 在内的所有按键。
5. **超屏高度与窗口 `resize` 错位**：当选项或文本折行超出终端可见行数 `rows`，或交互中途用户调整窗口宽度 `cols` 时，固定按旧 `prev_physical_rows` 上移擦除会产生残影或卷入 scrollback。
6. **宽字符边界与 JS 事件循环挂起**：Emoji（如 `🚀`、`⚠️`）和 `✓` 的列宽差异会导致行数估算偏差；Node.js 监听 `process.stdin` 后若只恢复 raw mode 而不 `pause()` / 清理 listener，进程会挂起不退出。

## 决策

1. **Native 异步可取消输入**：
   - 优先基于 `moonbitlang/core/async/stdio`（已集成事件循环并内置 `windows_console.mbt` UTF-8 ↔ UTF-16 Console 处理）进行可取消异步读取；
   - `native_stub.c` 聚焦于 `isatty`、termios/Win32 `ConsoleMode` 切换与保存恢复、`GetConsoleScreenBufferInfo`/`ioctl(TIOCGWINSZ)` 窗口尺寸查询、`WriteConsoleW`（或检测是否需要独立读线程 + `raw_fd` 管道以支持更精细的控制键）；**严禁在主事件循环线程内执行不可取消的阻塞读**。
   - Phase 3 必须实测 `core/async/stdio` 在 Windows Raw Mode（含 `ENABLE_VIRTUAL_TERMINAL_INPUT`）下方向键、汉字 IME 与 `with_timeout` 取消的真实表现；如发现 `ReadConsoleW` 对裸功能键的限制，则采用“后台 C 读线程 + 匿名管道（`core/async/raw_fd`）”将 `ReadConsoleInputW` 转写为非阻塞 VT 字节流。
2. **Windows 输出与 OS 级恢复兜底**：
   - 优先使用 `WriteConsoleW`（UTF-8 转 UTF-16）输出，避免修改宿主进程全局代码页；修改输入模式时保留 `ENABLE_QUICK_EDIT_MODE` 与 `ENABLE_EXTENDED_FLAGS`；
   - C stub 注册 `atexit` 与 Windows `SetConsoleCtrlHandler` 作为进程意外终止时的幂等终端恢复兜底，与 MoonBit 侧 `defer` + `nocancel` 形成双保险。
3. **20ms `Esc` 消歧机制**：
   - `KeyDecoder::feed` 遇到末尾孤立 `0x1B` 时保留在挂起缓冲而不立刻吐出 `Escape`；
   - 驱动层（异步循环或 JS 定时回调）在检测到存在挂起孤立 `0x1B` 时，通过 `with_timeout_opt(20, ...)` 等待后续字节，超时无新输入则调用 `KeyDecoder::flush_escape()` 产出一个 `KeyCode::Escape`。
4. **Bracketed Paste 安全逃生**：
   - `KeyDecoder` 限制单次 `paste_buf` 上限（默认 `1_048_576` 字节 / 1 MiB），超出或遇到裸 `0x03`（`Ctrl+C`）时立即终止粘贴态：先丢弃/提交缓冲再释放 `Ctrl+C` 中断信号，保证永远不会卡死用户终端。
5. **视口钳制、Delayed-Wrap 与 `resize` 处理**：
   - 物理行数计算公式需考虑 VT100 delayed-wrap（可见宽恰好等于 `cols` 且非空时占 `cols` 对应整行但不立即换行，精确模型：$\max(1, \lceil w / \max(1, \text{cols}) \rceil)$，并在末尾不额外多算空折行）；
   - 高级组件渲染时根据 `term.size()` 的 `rows` 自动钳制 `max_items`（例如不超过 `rows - 4`），防止单帧高度超越可视屏幕进入 scrollback；
   - 检测到 `cols` 变化时，若变化前帧已渲染，驱动层先发 `\r\x1b[2K` 尽量归位再重新计算新列宽下的折行，并将 `InlineDiffRenderer` 重置为新高度基准（提供 `InlineDiffRenderer::on_resize` / `reset`）。
6. **宽字符与 Node.js 退出清理**：
   - `ansi::display_width` 完整处理控制符（0 列）、结合音标/变体选择符 `U+FE00..U+FE0F`/ZWJ `U+200D`（0 列）、东亚全角与 Emoji Presentation（2 列）及窄符号如 `✓`/`✗`/`◆`/`◇`（1 列），直接对齐 `moonset/cli/tui_render.mbt` 已验证实现；
   - `term_js.mbt` 在 Node/Deno/Bun CLI 退出原始模式时，除 `setRawMode(false)` 外必须卸载 `data`/`resize` 监听器并调用 `process.stdin.pause()`，防止脚本主逻辑结束后进程无法自然退出。

## 后果

- Phase 3 需包含 Windows/POSIX 双端验证以及 `with_timeout` 取消、20ms `Esc` 消歧、`Ctrl+C` 逃生与 `CallbackTerminal` 模拟 `resize` 的自动化测试。
- 相较直接阻塞读增加了少量驱动状态机复杂度，但换取了协程取消 100% 可靠与零僵尸进程。
