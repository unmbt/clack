# 分阶段 SDD 执行路线与验收门禁

AI 智能体必须按 **Phase 0 → Phase 5** 串行推进。每个阶段编码前须先编写对应 `_test.mbt` 测试用例，当前阶段门禁命令必须**零报错、零警告**通过，并同步回写 [`docs/spec/requirements.md`](./requirements.md) 中对应 `REQ-*` 的状态与验证证据后，方可进入下一阶段。

---

## Phase 0：工程脚手架、跨目标配置与工具链探针

* **目标**：初始化 `unmbt/clack` 仓库配置与子包 `moon.pkg`（零第三方依赖），落盘全套 `declare` 契约桩并验证四目标条件编译基线。
* **执行动作**：
  1. 创建 `.gitattributes`（写入 `* text=auto eol=lf`）与 `.moonignore`（忽略 `_build/` 与本地参考仓库目录 `clack/`）。
  2. 更新 `moon.mod`（移除外部依赖、`preferred_target = "native"`），创建根包及 `ansi`、`core`、`term`、`prompts`、`minimal`、`flow`、`cmd/demo`、`cmd/web_demo` 的 `moon.pkg`（严格遵循 `docs/spec/architecture-and-contracts.md` 第 2 节的条件导入与 `allow-experimental-packages`）。
  3. 原样写入 `docs/spec/architecture-and-contracts.md` 第 3 节定义的全部结构体、枚举、Trait、`PromptAdapter[T]` 与 `declare` 函数声明。
* **门禁命令（工具链探针）**：
  * `moon check --target native`、`moon check --target js`、`moon check --target wasm` 通过（仅允许预期的未实现 `declare` 提示，无语法、类型、条件导入或包循环依赖错误）；
  * `moon check ansi --target wasm-gc` 与 `moon check core --target wasm-gc` 通过。

---

## Phase 1：`ansi` 着色器、转义剥离与宽字符折行引擎

* **目标**：完成零外部依赖、全四目标兼容的 `unmbt/clack/ansi` 包。
* **测试先行用例（`ansi/ansi_test.mbt`）**：
  * 环境变量探测：验证 `NO_COLOR=1` 压倒默认 TTY 色彩推断；验证 `FORCE_COLOR=3` 强制开启 `TrueColor`；验证 `TERM=dumb` 关闭颜色。
  * 嵌套样式恢复：验证 `s.cyan("prefix " + s.bold("inner") + " suffix")` 精确恢复青色，且在 `ColorLevel::None` 下输出纯字符串。
  * 宽字符与折行精度：验证 `display_width("你好 clack 🚀 ✓ ⚠️")` 以及含 CSI/OSC 转义串的 `wrapped_line_count` 在 `cols = 10 / 20 / 40 / 80`（含宽度恰好等于 `cols` 的 delayed-wrap 边界）下的精确物理行数。
* **门禁命令**：
  * `moon test ansi --target native`、`moon test ansi --target js`、`moon test ansi --target wasm`、`moon test ansi --target wasm-gc` 全部通过；
  * `moon check ansi --deny-warn` 零警告，并回写 `REQ-STYLE-01`、`REQ-STYLE-02`、`REQ-RENDER-02` 状态。

---

## Phase 2：`core` 按键/粘贴解码、无头状态机、双主题、差分引擎与 `InlineDriver`

* **目标**：完成 100% 纯函数、零异步依赖的 `unmbt/clack/core` 包。
* **测试先行用例（`core/core_test.mbt`）**：
  * `KeyDecoder` 与括号粘贴：
    * 方向键、`Shift+Tab`（`\x1b[Z`）、`Ctrl+C`（`0x03`）；
    * **20ms `Esc` 消歧测试**：单独喂入 `b"\x1b"` 后断言 `has_pending_escape() == true` 且尚未吐出 `Escape`；紧接喂入 `b"[A"` 断言产出一个 `Up`；另测单独喂入 `b"\x1b"` 后调用 `flush_escape()` 准确产出 `Escape`。
    * 多字节中文 `"脚手架"` 被切分为任意 2 字节分片连续调用 `feed` 的跨批次重组测试；
    * **Bracketed Paste 测试**：喂入 `[b"\x1b[200~my-app\r\n", b"yes\r\n\x1b[201~"]` 分片流，断言仅产出单个 `KeyCode::Paste("my-app\r\nyes\r\n")`，绝不产出 `KeyCode::Enter`；另测未闭合粘贴流遇到 `0x03` 时可安全逃生。
  * 六大组件状态机（`TextModel`、`ConfirmModel`、`SelectModel`、`MultiSelectModel`、`GroupMultiSelectModel`、`AutocompleteModel`）：
    * 光标按 Unicode 字符边界移动、`TextModel` 与 `PasswordModel` 对 `Paste` 载荷的 `CRLF` 清洗验证；
    * 禁用项自动跳过、空选项/全禁用错误返回、超出 `max_items` 时的视口滑动窗口计算、`MultiSelectModel` / `GroupMultiSelectModel` 整组切换与必选告警自动消除；
    * `AutocompleteModel` 中输入 `j`/`k`/`a`/`i`/`Space` 进入搜索框而非误导航；
    * `allow_back=true` 下按 `Esc` / `BackTab` 准确返回 `PromptOutcome::StepBack`。
  * `ClackTheme` 与 `MinimalTheme`：对各 `PromptPhase`（含 `Warning`、`Submitted`、`Cancelled`、`Reverted`）生成帧执行 `debug_inspect` 快照断言（覆盖 Unicode 与 ASCII 回退模式）。
  * `InlineDiffRenderer` 与 `InlineDriver[T]`：模拟 1 行扩至 5 行、5 行缩至 2 行、40 列窄屏中文自动折行与 `resize` 后的 `\x1b[{N}A\r\x1b[J` 与 DEC 2026 同步包裹序列；验证 `InlineDriver[T]` 纯同步推模式完整走通单步交互。
* **门禁命令**：
  * `moon test core` 在 `--target wasm-gc`、`--target wasm`、`--target js`、`--target native` 下全部通过，并回写对应 `REQ-*` 状态。

---

## Phase 3：`term` 虚拟终端桩、`CallbackTerminal` 与三后端原生适配（下一里程碑）

* **目标**：实现 `VirtualTerminal`、`CallbackTerminal` 以及 `native` / `js` / `wasm` 真实终端适配器。
* **复用 `moonset/cli/tty_native.c` 与 6 大 TTY 避坑清单**：
  1. **Windows UTF-8 输出防乱码**：控制台句柄使用 `MultiByteToWideChar(CP_UTF8)` + `WriteConsoleW`，绝不调用 `SetConsoleOutputCP(65001)` 污染宿主代码页；管道输出回退 `WriteFile`。
  2. **Windows QuickEdit 与滚屏保护**：进入 Raw Mode 仅关闭 `ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT | ENABLE_WINDOW_INPUT | ENABLE_MOUSE_INPUT`，保留 `ENABLE_QUICK_EDIT_MODE | ENABLE_INSERT_MODE | ENABLE_EXTENDED_FLAGS`；恢复时显式补齐 `ENABLE_EXTENDED_FLAGS`。
  3. **Windows IME 代理对与缺失按键补齐**：保留 `g_pending_high_surrogate` 组装补充平面 UTF-16 代理对；相较 `moonset/cli/tty_native.c` 额外补齐 `Shift+Tab`（`\x1b[Z`）、`PageUp`/`PageDown`（`\x1b[5~`/`\x1b[6~`）与 `Ctrl+D`（`0x04`）。
  4. **异步可取消读探针（避免阻塞 `core/async`）**：严禁在主事件循环执行同步阻塞 `read()` / `ReadConsoleInputW()`。优先在 POSIX/Windows 实测 `moonbitlang/core/async/stdio`（Windows 侧配合 `ENABLE_VIRTUAL_TERMINAL_INPUT`）；若实测发现 `ReadConsoleW` 对裸功能键/快捷键受限，则切换为「后台 C 读线程 + 匿名管道 + `#cfg(target="native")` 导入 `moonbitlang/core/async/raw_fd`」的可取消异步桥接。
  5. **双保险终端恢复**：MoonBit 侧 `defer` + `nocancel`（内部 `@async.protect_from_cancel`），C 侧 `atexit` + Windows `SetConsoleCtrlHandler` 同步发出 `\x1b[0m\x1b[?2004l\x1b[?25h\x1b[?2026l` 并恢复模式；`term_js.mbt` 退出时必须卸载 listener 并调用 `process.stdin.pause()` 防止 Node 事件循环挂起。
  6. **孤立 `Esc` 消歧与 Resize 检测**：驱动层检测 `decoder.has_pending_escape()` 后以 `@async.with_timeout_opt(20, ...)` 等待后续字节；每次读入前检测 `term.size()` 变化并调用 `InlineDiffRenderer::on_resize`。
* **测试先行用例（`term/term_test.mbt`）**：
  * 在 `VirtualTerminal` 中注入正常输入序列 `[b"hello", b"\r"]` 与中断序列 `[b"\x03"]`（模拟 `Ctrl+C`），断言交互结束后 `in_raw_mode() == false`，且末帧一定包含 `\x1b[?2004l\x1b[?25h\x1b[?2026l` 恢复序列。
  * **异步取消与 `Esc` 消歧测试**：在 `moonbitlang/core/async` 的 `with_timeout` / `TaskGroup` 中模拟外部超时取消正在等待输入的 `CallbackTerminal` / 虚拟输入循环，断言 `defer` + `nocancel` 清理分支 100% 触发；验证 20ms `Esc` 超时消歧工作正常。
  * **`CallbackTerminal`（`xterm.js` 模型）测试**：模拟 `push_text` 注入按键/括号粘贴、`set_size` 触发窗口缩放与 `on_write` 帧输出捕获，验证 `--target native` 与 `--target js` 均通过。
* **门禁命令**：
  * `moon test term --target native`、`moon test term --target js`、`moon test term --target wasm` 通过；
  * POSIX 与 Windows 下 `moon build --target native` 编译 `native_stub.c` 零警告，且实机验证 `core/async/stdio` 在 Raw Mode 下的可取消异步读与中文 IME 行为。

---

## Phase 4：`prompts`、`minimal` 命令式 API、`flow` 回退向导与根包门面（下一里程碑）

* **目标**：完成高层命令式组件、`group_multiselect`、`Spinner`（含 `dots`/`timer` 指示器与 TTY 键盘屏蔽）、`Progress`（`light`/`heavy`/`block`）、`log_*`、`note`、支持状态回退的 `run_wizard`，并在根包 `exports.mbt` 使用 `pub using` 完成 `@clack` 门面重导出。
* **逐文件交付清单**：
  * `prompts/session.mbt`、`prompts/prompts.mbt`、`prompts/spinner.mbt`、`prompts/progress.mbt`、`prompts/log.mbt`、`prompts/prompts_test.mbt`
  * `minimal/prompts.mbt`、`minimal/minimal_test.mbt`
  * `flow/wizard.mbt`、`flow/flow_test.mbt`
  * 根包 `exports.mbt`、`moon.pkg`、`clack_test.mbt`
* **测试先行用例（`prompts/prompts_test.mbt`、`minimal/minimal_test.mbt`、`flow/flow_test.mbt`、`clack_test.mbt`）**：
  * **端到端 Step-Back 向导测试**：构造 3 步脚手架向导（第 1 步输入项目名 → 第 2 步因 `when` 返回 `false` 自动跳过 → 第 3 步选择构建目标时按下 `Shift+Tab` → 断言自动跨过第 2 步直接退回第 1 步，且保留原项目名作为 `initial_value` → 修改后一路回车提交，断言最终聚合 `State` 精确无误）。
  * **粘贴防连环提交端到端测试**：向两步连续问答（`text` 接 `confirm`）的 `VirtualTerminal` 注入括号粘贴 `b"\x1b[200~demo-pkg\r\ny\r\n\x1b[201~"` 后再注入回车与 `'n'`，断言 `confirm` 未被粘贴串内的 `'y'` 提前误提交，最终结果为 `("demo-pkg y", false)`。
  * **分组多选与视图钳制测试**：验证 `group_multiselect` 整组切换、`rows = 10` 时对长列表视口高度自动钳制。
  * **CI 非交互测试**：验证 `NonInteractivePolicy::UseDefaults` 在 `tty=false` 时零阻塞返回默认值，缺失默认值时精确抛出 `TermError::NotInteractive`。
  * **Spinner 与 Progress 降级测试**：验证在 `tty=false` 下仅输出静态日志，不残留后台定时协程；在 `tty=true` 下与 `TaskGroup` 并发取消时安全停转恢复光标，且运行期间静默吞掉非 `Ctrl+C` 按键。
* **门禁命令**：
  * `moon test --target native`、`moon test --target js`、`moon test --target wasm` 全库通过，并回写全部 `REQ-*` 状态。

---

## Phase 5：CLI 演示程序、Web `xterm.js` Demo 导出、文档校验与发布门禁（下一里程碑）

* **目标**：编写 `cmd/demo` 全功能 CLI 交互展示程序、`cmd/web_demo` 浏览器 `xterm.js` 演示桥接模块（可被类似 `moonset/doc-web` 的 Vite + `@xterm/xterm` 前端直接导入）与 `README.mbt.md` 类型检查示例，通过全量发布级门禁。
* **Web Demo 验收要点**：
  * `moon build cmd/web_demo --target js` 产出可导入的 ES Module，导出启动/输入/Resize/取消接口，在 `CallbackTerminal` 上完整运行 `ClackTheme` & `MinimalTheme` 切换、`StepBack`、`Spinner` 与 `Progress`；
  * `moon build core --target wasm` / `--target wasm-gc` 验证 `InlineDriver[T]` 轻量纯核包可用性。
* **实机终端人工核验清单（Windows Terminal / PowerShell + POSIX）**：
  * 中文/Emoji 输入、光标左右移动与退格无乱码/劈字；
  * Bracketed Paste 多行粘贴不误触连环提交；
  * `Spinner` 期间按键无回显污染、`Ctrl+C` 立即恢复光标且不破坏 QuickEdit；
  * 交互中途拖拽缩放终端宽度无残影；管道模式与 `NO_COLOR=1` 降级正常。
* **智能体交付前最终验收清单（必须逐条跑通）**：
  1. `moon fmt --check`（代码与 `moon.mod`/`moon.pkg` 清单格式 100% 合规）
  2. `moon info` 后对各支持目标执行 `moon check --deny-warn`（全模块零编译器警告，所有 `declare` 均已落盘实现，各包 `pkg.generated.mbti` 同步最新）
  3. `moon test --target native`、`moon test --target js`、`moon test --target wasm` 全部绿灯（且 `ansi` / `core` 额外通过 `moon test ansi --target wasm-gc` 与 `moon test core --target wasm-gc`）
  4. 使用 `moon ide doc` 检查根包 `unmbt/clack` 导出的公共 API 签名清晰、无内部实现类型意外泄漏
  5. `moon publish --dry-run`（验证零外部依赖干净打包）与 `git status --porcelain` 检查工作区干净（无 `CRLF` 行尾污染）

---

## 远期演进池（Phase 3+ 评估项 & v0.2 候选）

### 1. MoonBit Virtual Package 多端评估结论（Phase 3+ 可选演进）

* **基础多后端切换（`native` / `js` / `wasm`）**：不采用 Virtual Package，继续使用 `term/moon.pkg` 的 `#cfg(target = ...)` + `targets` 文件裁剪 + `Terminal` trait。原因：`#cfg`/`targets` 对下游零配置侵入，且 `Terminal` trait 支持同一进程/测试内并存 `VirtualTerminal`、`CallbackTerminal` 与真实 TTY（Virtual Package 属于链接期全局单例替换，无法满足多实例共存）。
* **`wasm-gc` 支持**：Virtual Package 无法绕过 `moonbitlang/core/async` 不支持 `wasm-gc` 的底层限制；`ansi` 与 `core`（含 `InlineDriver[T]`）通过纯同步架构已天然兼容四端。
* **潜在契合场景（Phase 3+ / v0.2）**：若未来推出外部可选终端适配包（如 ADR-001 提及的 `unmbt/clack-tty`），可评估将「默认终端构造器」拆为 `virtual(has_default: true)` 子包，允许下游可执行文件在 `moon.pkg` 中用一行 `options(overrides: ["unmbt/clack-tty"])` 全局替换默认终端后端而无需在每个提示调用透传 `session=`（前提是验证 `moon info` / `moon publish` 稳定无坑）。

### 2. v0.2 扩展组件池（对标原版 `@clack/prompts` v1.9.0 — 已全部实现并合入）

* [x] `box`（带对齐、宽度控制、圆角边框与标题的通用边框盒子）
* [x] `select_key`（单键热键速选）
* [x] `date`（分段日期输入、闰年/月份天数校验与 `min_date`/`max_date` 范围校验）
* [x] `multiline`（多行文本输入、Unicode 标量编辑、粘贴清洗与双回车/`[ submit ]` 提交）
* [x] `task_log`（含 `strip_destructive_ansi` 的可折叠流式任务日志与子组 `group`）
* [x] `tasks`（串行任务组 `Spinner` 编排与 `enabled` 条件跳过）
* [x] `autocomplete_multiselect`（可搜索多选）
* [x] `stream`（`StreamLog` 与 `stream_message`/`stream_info`/`stream_success`/`stream_step`/`stream_warn`/`stream_warning`/`stream_error`）
* [x] `path` / `path_with`（基于 `core/async/fs` 与 JS `node:fs` 的跨端路径自动补全）
* [x] 异步校验（`validate_async` 与 `Validating...` 态）、`ACCESSIBLE` 模式、`Spinner::clear`/`style_frame`/`on_cancel`、`Progress::{message, cancel, clear}`、`note(format=...)` 与 `log_warning`、`PromptOutcome` 辅助方法
