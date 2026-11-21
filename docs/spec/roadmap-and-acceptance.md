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

## Phase 3：`term` 虚拟终端桩、`CallbackTerminal` 与三后端原生适配

* **目标**：实现 `VirtualTerminal`、`CallbackTerminal` 以及 `native` / `js` / `wasm` 真实终端适配器。
* **测试先行用例（`term/term_test.mbt`）**：
  * 在 `VirtualTerminal` 中注入正常输入序列 `[b"hello", b"\r"]` 与中断序列 `[b"\x03"]`（模拟 `Ctrl+C`），断言交互结束后 `in_raw_mode() == false`，且末帧一定包含 `\x1b[?2004l\x1b[?25h\x1b[?2026l` 恢复序列。
  * **异步取消与 `Esc` 消歧测试**：在 `moonbitlang/core/async` 的 `with_timeout` / `TaskGroup` 中模拟外部超时取消正在等待输入的 `CallbackTerminal` / 虚拟输入循环，断言 `defer` + `nocancel` 清理分支 100% 触发；验证 20ms `Esc` 超时消歧工作正常。
  * **`CallbackTerminal`（`xterm.js` 模型）测试**：模拟 `push_text` 注入按键/括号粘贴、`set_size` 触发窗口缩放与 `on_write` 帧输出捕获，验证 `--target native` 与 `--target js` 均通过。
* **门禁命令**：
  * `moon test term --target native`、`moon test term --target js`、`moon test term --target wasm` 通过；
  * POSIX 与 Windows 下 `moon build --target native` 编译 `native_stub.c` 零警告，且实机验证 `core/async/stdio` 在 Raw Mode 下的可取消异步读与中文 IME 行为。

---

## Phase 4：`prompts`、`minimal` 命令式 API、`flow` 回退向导与根包门面

* **目标**：完成高层命令式组件、`group_multiselect`、`Spinner`、`Progress`、`log_*`、支持状态回退的 `run_wizard`，并在根包 `exports.mbt` 使用 `pub using` 完成 `@clack` 门面重导出。
* **测试先行用例（`prompts/prompts_test.mbt`、`minimal/minimal_test.mbt`、`flow/flow_test.mbt`、`clack_test.mbt`）**：
  * **端到端 Step-Back 向导测试**：构造 3 步脚手架向导（第 1 步输入项目名 → 第 2 步因 `when` 返回 `false` 自动跳过 → 第 3 步选择构建目标时按下 `Shift+Tab` → 断言自动跨过第 2 步直接退回第 1 步，且保留原项目名作为 `initial_value` → 修改后一路回车提交，断言最终聚合 `State` 精确无误）。
  * **粘贴防连环提交端到端测试**：向两步连续问答（`text` 接 `confirm`）的 `VirtualTerminal` 注入括号粘贴 `b"\x1b[200~demo-pkg\r\ny\r\n\x1b[201~"` 后再注入回车与 `'n'`，断言 `confirm` 未被粘贴串内的 `'y'` 提前误提交，最终结果为 `("demo-pkg y", false)`。
  * **分组多选与视图钳制测试**：验证 `group_multiselect` 整组切换、`rows = 10` 时对长列表视口高度自动钳制。
  * **CI 非交互测试**：验证 `NonInteractivePolicy::UseDefaults` 在 `tty=false` 时零阻塞返回默认值，缺失默认值时精确抛出 `TermError::NotInteractive`。
  * **Spinner 与 Progress 降级测试**：验证在 `tty=false` 下仅输出静态日志，不残留后台定时协程；在 `tty=true` 下与 `TaskGroup` 并发取消时安全停转恢复光标。
* **门禁命令**：
  * `moon test --target native`、`moon test --target js`、`moon test --target wasm` 全库通过，并回写全部 `REQ-*` 状态。

---

## Phase 5：CLI 演示程序、Web `xterm.js` Demo 导出、文档校验与发布门禁

* **目标**：编写 `cmd/demo` 全功能 CLI 交互展示程序、`cmd/web_demo` 浏览器 `xterm.js` 演示桥接模块（可被类似 `moonset/doc-web` 的 Vite + `@xterm/xterm` 前端直接导入）与 `README.mbt.md` 类型检查示例，通过全量发布级门禁。
* **Web Demo 验收要点**：
  * `moon build cmd/web_demo --target js` 产出可导入的 ES Module，导出启动/输入/Resize/取消接口，在 `CallbackTerminal` 上完整运行 `ClackTheme` & `MinimalTheme` 切换、`StepBack`、`Spinner` 与 `Progress`；
  * `moon build core --target wasm` / `--target wasm-gc` 验证 `InlineDriver[T]` 轻量纯核包可用性。
* **智能体交付前最终验收清单（必须逐条跑通）**：
  1. `moon fmt --check`（代码与 `moon.mod`/`moon.pkg` 清单格式 100% 合规）
  2. `moon info` 后对各支持目标执行 `moon check --deny-warn`（全模块零编译器警告，所有 `declare` 均已落盘实现，各包 `pkg.generated.mbti` 同步最新）
  3. `moon test --target native`、`moon test --target js`、`moon test --target wasm` 全部绿灯（且 `ansi` / `core` 额外通过 `moon test ansi --target wasm-gc` 与 `moon test core --target wasm-gc`）
  4. 使用 `moon ide doc` 检查根包 `unmbt/clack` 导出的公共 API 签名清晰、无内部实现类型意外泄漏
  5. `moon publish --dry-run`（验证零外部依赖干净打包）与 `git status --porcelain` 检查工作区干净（无 `CRLF` 行尾污染）
