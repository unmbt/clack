# 核心算法、双主题渲染与跨平台终端机制

## 1. 双主题视觉规范对照

所有边框与状态指示字符在检测到 Windows 旧版非 UTF-8 代码页或显式配置 `unicode = false` 时，自动回退为纯 ASCII 符号（`|`、`+`、`*`、`o`、`>`）：

```text
[ClackTheme 导轨风渲染示意]               [MinimalTheme 极简风渲染示意]
┌  create-moon-app                        ? Project name › my-app
│                                         ✔ Project name · my-app
◇  Project name                           ? Pick target backend › (Use arrows, Esc to go back)
│  my-app                                 ❯ Native (C / Native backend)
│                                           WebAssembly (Wasm / moonx)
◆  Pick target backend                      JavaScript (Node / Deno)
│  ● Native · 极速单文件二进制
│  ○ WebAssembly
│  ○ JavaScript
└
```

* **`GroupMultiSelect`（分组多选）导轨树形视觉规范**：参考 `moonset/cli/tui_render.mbt`，在分组标题下以 `│ ` 与 `└ ` 呈现所属子项；在分组标题按 `Space` 可整组切换勾选/取消，单条目使用 `◼` / `◻`（ASCII 回退为 `[x]` / `[ ]`）。
* **`PromptPhase::Reverted`（回退态）视觉表现**：当用户在步骤 $k$ 按下 `Esc` 或 `Shift+Tab` 触发 `StepBack` 时，渲染器将当前活动帧固化为单行暗淡撤回标记（如 Clack 导轨 `│` 保持衔接不留残影，或标记 `◁ Reverted`），随后无缝激活上一步组件并预填其历史输入值。

## 2. 行内差分重绘算法（`InlineDiffRenderer`）与宽字符规则

### 2.1 Unicode 宽字符规则（对齐 `moonset/cli/tui_render.mbt`）

1. **剥离 ANSI 序列**：忽略 CSI（`\x1b[...[\x40-\x7e]`）与 OSC（`\x1b]...\x07` 或 `\x1b]...\x1b\\`）等不可见控制串。
2. **单元格宽度判定**：
   - C0/C1 控制字符（`<= 0x1F` 或 `0x7F..0x9F`）：0 列；
   - 组合字符（`U+0300..U+036F`、`U+1AB0..U+1AFF`、`U+20D0..U+20FF` 等）、肤色修饰符（`U+1F3FB..U+1F3FF`）、变体选择符（`U+FE00..U+FE0F`）与零宽连接符 `U+200D`：0 列（`U+200D` 并抑制紧随其后的连接字符计宽）；
   - 东亚全角汉字/韩文/全角标点、Emoji Presentation（含 `🚀` 等补充平面符号及带 `U+FE0F` 的序列如 `⚠️`）、按键帽序列（`1️⃣`）：2 列；
   - 窄符号（`✓` `U+2713`、`✗` `U+2717`、框线符号 `┌ │ ◇ ◆ └`、箭头 `↑ ↓ ❯`）与标准 ASCII：1 列。

### 2.2 行内差分数学不变量与边界保护

为彻底避免使用 `\x1b[2J` 清屏导致历史输出丢失，每一帧的擦写严格遵守以下数学不变量：

1. **不变式定义**：任意时刻活动交互帧渲染完毕后，终端物理光标始终停留在**当前帧最后一行的行尾**，且 `prev_physical_rows` 记录当前活动帧在终端宽度 `cols` 下占据的总物理行数：
   $$\text{rows}(L, \text{cols}) = \sum_{i=0}^{|L|-1} \max\left(1, \left\lceil \frac{\text{display\_width}(\text{strip\_ansi}(L_i))}{\max(1, \text{cols})} \right\rceil\right)$$
   > **Delayed-Wrap 边界**：大多数现代 VT100 终端（含 xterm.js、Windows Terminal、iTerm2）在行宽**恰好等于** `cols` 时仅将光标停留在第 `cols` 列（pending wrap），直到下一个可打印字符或 `\r\n` 才换行；上述向上取整公式使宽度为 `cols` 时恰计为 1 行，与真实光标位置一致。
2. **视口高度钳制与物理行数裁剪（防 Scrollback 溢出）**：
   - 当活动列表（`select` / `multiselect` / `group_multiselect` / `autocomplete`）存在滚动选项时，参照原版 `@clack/prompts` 的 `limitOptions` 思路：不仅限制逻辑条目数 `effective_max = min(max_items, max(4, rows - 4))`，还需先按列宽计算各可见选项折行后的实际物理行数，当总物理行数超出 `rows - row_padding` 预算时从非光标侧逐步裁剪并补全 `...` 溢出指示，确保整帧高度始终小于终端可见行数 `rows`，避免上方帧滚入终端历史缓冲区导致 `\x1b[{N}A` 无法擦除。
3. **帧更新步骤（`patch`）与相等短路**：
   - **帧相等短路**：若待渲染行序列与上一帧完全一致且列宽 `cols` 未变化，直接返回空字符串并跳过 `write_str`（消除无意义重绘）；
   - 打开 `StringBuilder`；若 `sync_output == true`，先写入 `"\x1b[?2026h"`。
   - 若 `has_rendered == true`：
     - 若 `prev_physical_rows > 1`，写入向上移动光标序列 `"\x1b[\{prev_physical_rows - 1}A"`；
     - 写入回车回到首列并擦除光标至屏幕底部残留活动区：`"\r\x1b[J"`（即 `\x1b[0J` 从当前活动帧起点向下擦除，**绝不触碰上方历史滚屏**）。
   - 用 `"\r\n"` 连接新帧 `lines` 写入。
   - 更新 `prev_physical_rows = rows(lines, cols)`，`has_rendered = true`。
   - 若 `sync_output == true`，写入 `"\x1b[?2026l"`，一次性返回完整字符串交由 `Terminal::write_str` 写出。
4. **窗口尺寸变化（Resize）处理**：
   - 驱动层在每次读取或收到 `size()` 变化通知时检测 `(new_cols, new_rows)`；若 `new_cols != prev_cols` 且 `has_rendered == true`，先向当前行发 `"\r\x1b[2K"` 并调用 `renderer.reset()` 清理残余光标计数（或结合缩窄比例估算回退），再以 `new_cols` 立即重绘当前帧。
5. **帧固化步骤（`commit`）**：
   - 调用同套擦除逻辑将多行活动输入态替换为紧凑的已提交摘要行（通常 1–2 行），末尾追加 `"\r\n"` 换行落盘，并将 `prev_physical_rows` 重置为 `0`、`has_rendered = false`，使后续日志或下一个提示自然顺延。

## 3. 按键字节流状态机与括号粘贴解码（`KeyDecoder`）

终端单次 `read_bytes` 可能一次读入大段粘贴字节，也可能将单个转义序列或 UTF-8 多字节字符切分到两次读取中。`KeyDecoder::feed` 必须以零 I/O 状态机消费 `BytesView`：

### 3.1 常规控制键、CSI 序列与 20ms `Esc` 消歧

* `0x03` → `KeyEvent { code: Char('c'), ctrl: true, .. }`（外层驱动统一映射为 `PromptOutcome::Cancelled`）。
* `0x04` → `Ctrl+D`（EOF 取消）；`0x01` → `Ctrl+A`（`Home`）；`0x05` → `Ctrl+E`（`End`）。
* `0x0D` 或 `0x0A`（**非 `in_paste` 状态下**）→ `Enter`（若 `\r` 后紧随 `\n` 合并为单次 `Enter`）；`0x09` → `Tab`；`0x7F` 或 `0x08` → `Backspace`。
* **语义动作隔离原则**：`j` / `k` / `h` / `l` 导航别名与 `a` / `i` / `Space` 快捷操作仅在非文本输入组件（`Confirm`、`Select`、`MultiSelect`、`GroupMultiSelect`）中激活；`Text`、`Password`、`Autocomplete` 必须将所有可打印字母和空格原样送入输入编辑缓冲。
* `0x1B`（ESC）分支与**20ms 超时消歧**（见 [ADR-004](../decisions/004-terminal-lifecycle-and-resize.md)）：
  * 当字节流在 `0x1B` 处耗尽时，`KeyDecoder` **不立即判定为 `Escape`**，而是暂存 `0x1B` 到挂起缓冲并使 `has_pending_escape() == true`；
  * 异步驱动层看到 `has_pending_escape() == true` 时，使用 `@async.with_timeout_opt(20, ...)` 等待下一个输入切片；若 20ms 内无后续字节到达，调用 `decoder.flush_escape()` 产出 `KeyEvent { code: Escape, .. }`；若在 20ms 内收到 `[` 或 `O` 等后续字节，则与暂存的 `0x1B` 自动拼接解码：
    * `\x1b[A` / `\x1bOA` → `Up`；`\x1b[B` / `\x1bOB` → `Down`；`\x1b[C` / `\x1bOC` → `Right`；`\x1b[D` / `\x1bOD` → `Left`。
    * `\x1b[Z` → `BackTab`（`Shift+Tab`，当 `allow_back == true` 时触发 `StepBack`）。
    * `\x1b[3~` → `Delete`；`\x1b[H` / `\x1b[1~` → `Home`；`\x1b[F` / `\x1b[4~` → `End`；`\x1b[5~` → `PageUp`；`\x1b[6~` → `PageDown`。
* 其余首字节按 UTF-8 1–4 字节前导位规则解码为完整 Unicode `Char`（若当前 `chunk` 末尾存在未收齐的 UTF-8 续字节，暂存至 `pending_bytes` 等待下一帧拼接，严禁逐字节强转 `Char` 破坏中文输入）。

### 3.2 Bracketed Paste（括号粘贴）防锁死与 `CRLF` 清洗规则

当终端启用 `\x1b[?2004h` 后，用户粘贴内容会被终端包裹在 `\x1b[200~` 与 `\x1b[201~` 之间：

1. **区间聚合与安全逃生**：
   - `KeyDecoder` 匹配到 `\x1b[200~` 时切换 `in_paste = true`，此后直至匹配到 `\x1b[201~` 之前的所有字节（**包括其中的 `\r`、`\n`、`\t`**）均按 UTF-8 解码写入 `paste_buf`，绝不拆分为 `KeyCode::Enter` 或 `KeyCode::Tab`；
   - 匹配到 `\x1b[201~` 时重置 `in_paste = false` 并一次性吐出 `KeyEvent { code: Paste(raw_text), ctrl: false, alt: false, shift: false }`；
   - **安全逃生保护**：若 `paste_buf` 超过最大保护上限（`1_048_576` 字节）或流中出现 `0x03`（`Ctrl+C`），立即退出 `in_paste`，在遇到 `0x03` 时正常放出取消事件，防止异常终端丢弃闭合序列导致键盘死锁。
2. **各组件对 `KeyCode::Paste(raw)` 的清洗语义**：
   * **`TextModel` 与 `AutocompleteModel`（单行输入）**：剔除除换行/制表符外的 C0/C1 控制字符，修剪末尾多余换行并将内部连续 `\r\n`、`\r`、`\n` 折叠替换为空格 `' '`，一次性插入当前光标字符索引处，保持 `Active` 态等待用户核对后按 `Enter`。
   * **`PasswordModel`（密钥/Token 输入）**：直接剥离全部 `\r` 与 `\n`（防止复制 API Key 时混入尾部换行导致鉴权失败），不触发自动提交。
   * **`ConfirmModel`、`SelectModel`、`MultiSelectModel`、`GroupMultiSelectModel`**：对 `KeyCode::Paste(_)` 执行安全忽略（No-op），杜绝粘贴残留文本误选或误确认。

## 4. 跨平台终端适配、标准库 `core/async` 驱动与浏览器 `xterm.js` 桥接

### 4.1 异常与取消安全生命周期（基于 `moonbitlang/core/async`）

执行单个交互提示的核心驱动循环严格使用 `defer` + `nocancel` 守卫骨架，确保正常提交、抛出 `TermError`、按下 `Ctrl+C` 或遭遇 `@async.with_timeout` / `Task::cancel` 时终端状态 100% 复原：

```moonbit
async fn[T] run_prompt_loop(
  term : &@term.Terminal,
  adapter : @core.PromptAdapter[T],
  theme : &@core.Theme,
  styler : @ansi.Styler,
  allow_back~ : Bool,
) -> @core.PromptOutcome[T] raise @term.TermError {
  term.enter_raw_mode()
  // 隐藏物理光标（文本输入组件使用反色块渲染软光标）并开启 Bracketed Paste
  term.write_str("\x1b[?25l\x1b[?2004h")
  defer {
    // defer 在正常返回、raise 错误、以及 core/async 协程取消时均保证执行
    // 关闭 Bracketed Paste、恢复物理光标显示、兜底闭合 DEC 2026 同步输出，并退出原始模式
    term.write_final("\x1b[?2004l\x1b[?25h\x1b[?2026l")
    term.leave_raw_mode()
  }
  ...
}
```

> **`nocancel` 与 `protect_from_cancel` 约定**：`Terminal::leave_raw_mode` 与 `Terminal::write_final` 内部必须包裹 `@async.protect_from_cancel` 或纯同步清理逻辑，禁止直接调用可取消的异步 I/O，否则无法满足 `nocancel` 签名约束。
>
> **`Spinner` 期间键盘屏蔽（`block()` 语义）**：在真实 TTY 下运行 `Spinner` 动画时，需同步进入 raw mode 并静默丢弃除 `0x03`（`Ctrl+C`）以外的所有键盘输入字节，防止用户等待期间误敲键盘造成回显错位；退出/取消时由同一 `defer` + `nocancel` 守卫恢复原始模式与光标。

### 4.2 多后端实现细则与浏览器 `xterm.js` Demo 架构

* **`native` 后端（`native_stub.c` + `term_native.mbt` + `core/async/stdio`）**：
  * **异步可取消输入**：优先通过 `moonbitlang/core/async/stdio`（已内置事件循环调度与 `windows_console.mbt` UTF-8 ↔ UTF-16 处理）进行可取消异步读取；**严禁在主事件循环内执行阻塞式 `read()` 或 `ReadConsoleInputW()`**。若 Phase 3 Windows 实测发现裸功能键需底层 `ReadConsoleInputW` 处理，则采用“后台 C 读线程 + 匿名管道 + `core/async/raw_fd`”方式保持事件循环可取消性。
  * **POSIX（Linux / macOS）**：`native_stub.c` 负责 `isatty`、`tcgetattr`/`tcsetattr`（关闭 `ICANON | ECHO | ISIG`，保留 `OPOST`）、`ioctl(TIOCGWINSZ)` 尺寸查询与 `atexit` 兜底恢复。
  * **Windows（Win32 Console / ConPTY）**：启用 `ENABLE_VIRTUAL_TERMINAL_PROCESSING | ENABLE_PROCESSED_OUTPUT`，输入侧保留 `ENABLE_QUICK_EDIT_MODE | ENABLE_EXTENDED_FLAGS`（不破坏终端选中复制），输出优先使用 `WriteConsoleW`（不篡改用户全局代码页），并注册 `atexit` + `SetConsoleCtrlHandler` 异常恢复守卫。
* **`js` 后端（`term_js.mbt` + `callback_term.mbt` + `core/async/js_async`）**：
  * **Node.js / Deno / Bun CLI**：绑定 `process.stdin.isTTY`、`process.stdin.setRawMode`、`process.stdout.columns/rows` 与 `data` 事件流（写入 `@async.Queue[Bytes?]` 供协程消费）；退出 raw mode 时**必须移除 listener 并调用 `process.stdin.pause()`**，防止事件循环挂起无法退出。
  * **浏览器 `xterm.js` Demo（参考 `moonset/doc-web`）**：
    * **路线 A（推荐主力 — Full Async JS）**：通过 `--target js` 编译 `cmd/web_demo`（导入 `unmbt/clack` 与 `moonbitlang/core/async/js_async`）。前端在 `@xterm/xterm` 初始化后创建 `CallbackTerminal(on_write=chunk => term.write(chunk), ...)`，将 `term.onData(data => handle.push_text(data))` 与 `term.onResize(({cols, rows}) => handle.set_size(cols, rows))` 接入 `CallbackTerminal`，并用 `@js_async.Promise::from_async` 返回受 `AbortSignal` 控制的完整异步向导（真实运行 `Spinner`、`Progress`、`StepBack`、`ClackTheme`/`MinimalTheme` 切换）。
* **`wasm` 后端（`term_wasm.mbt`）与纯核 `InlineDriver[T]`（`js`/`wasm`/`wasm-gc`）**：
  * **WASI CLI**：检测到非交互管道或缺少原始模式能力时，按 `NonInteractivePolicy` 自动回退（`UseDefaults` / `Fail`）或行缓冲序号输入，确保 `moonx` 即席运行零崩溃。
  * **路线 B（轻量/纯 Wasm 浏览器体验）**：当仅需以最小包体积在浏览器 Wasm / Wasm-GC 中嵌入单步组件体验时，直接实例化 `core::InlineDriver[T]`（零异步、零 `core/async` 依赖），由 JS 宿主把 `xterm.onData` 字节喂入 `driver.feed(bytes)` 并将返回的 ANSI 字符串直接写入 `xterm.write()`。
