# 模块拓扑与 AI-Native `declare` 接口契约

## 1. 模块拓扑与包分层架构

仓库采用单一 MoonBit 模块（`unmbt/clack`）内含多个职责正交子包的架构，严格保持自底向上有向无环（DAG）单向依赖。为避免 `unmbt/clack/clack` 命名冗余并对齐原版 `@clack/core` + `@clack/prompts` 分层，导轨风格命令式实现位于 `prompts/` 子包，同时由根包 `unmbt/clack`（`exports.mbt`）重导出为开箱即用的 `@clack` 默认门面：

```text
unmbt/clack/
├── AGENTS.md                         # 智能体工程总纲与语法红线
├── docs/
│   ├── README.md                     # 文档总览、状态标记与已实证基线
│   ├── sdd.md                        # SDD 规约、追踪关系与不可变原则
│   ├── references.md                 # 原版 Clack 架构剖析与 MoonBit 版架构设计总结
│   ├── decisions/                    # ADR 架构决策记录（001 ~ 004）
│   └── spec/                         # SDD 活规格文档（requirements / architecture-and-contracts / algorithms-and-mechanisms / roadmap-and-acceptance）
├── .gitattributes                    # * text=auto eol=lf（强制 LF 防止 Windows CI 脏树）
├── .moonignore                       # 排除本地基准脚本、upstream 参考目录与构建物
├── moon.mod                          # 模块声明（零外部第三方依赖）
├── exports.mbt                       # [Root Facade] 使用 pub using 重导出常用入口
├── moon.pkg                          # 根包配置（supported_targets = "-all+native+js+wasm"）
├── ansi/                             # [Layer 0] 纯函数（四目标）：SGR 着色、ANSI 剥离、宽字符折行
│   ├── moon.pkg
│   ├── color_level.mbt
│   ├── styler.mbt
│   ├── width.mbt
│   ├── escape.mbt
│   └── ansi_test.mbt
├── core/                             # [Layer 1] 纯函数（四目标）：按键/粘贴解码、无头状态机、双主题、差分与推模式驱动
│   ├── moon.pkg
│   ├── key.mbt
│   ├── result.mbt
│   ├── theme.mbt
│   ├── theme_clack.mbt
│   ├── theme_minimal.mbt
│   ├── diff_renderer.mbt
│   ├── inline_driver.mbt             # 纯同步推模式驱动 InlineDriver[T]（供 Web Wasm/JS 无异步嵌入）
│   ├── model_text.mbt
│   ├── model_confirm.mbt
│   ├── model_select.mbt
│   ├── model_multiselect.mbt
│   ├── model_group_multiselect.mbt
│   ├── model_autocomplete.mbt
│   └── core_test.mbt
├── term/                             # [Layer 2] I/O 边界（native/js/wasm）：Terminal Trait、测试桩与多宿主适配
│   ├── moon.pkg
│   ├── terminal.mbt
│   ├── virtual_term.mbt              # 内存确定性按键/粘贴注入与帧捕获器
│   ├── callback_term.mbt             # 基于 @async.Queue 的回调终端（服务浏览器 xterm.js 与嵌入式宿主）
│   ├── native_stub.c                 # Native POSIX termios + Win32 Console API C FFI 胶水
│   ├── term_native.mbt               # target="native" 实现（core/async/stdio + native_stub）
│   ├── term_js.mbt                   # target="js" 实现（Node/Deno/Bun TTY + 浏览器环境回退）
│   ├── term_wasm.mbt                 # target="wasm" 实现（core/async/stdio 行缓冲/非交互降级）
│   └── term_test.mbt
├── prompts/                          # [Layer 3A] 命令式导轨风格 API + Spinner + Progress + Log
│   ├── moon.pkg
│   ├── session.mbt
│   ├── prompts.mbt
│   ├── spinner.mbt
│   ├── progress.mbt
│   ├── log.mbt
│   └── prompts_test.mbt
├── minimal/                          # [Layer 3B] 命令式极简风格 API（对标 terkelg/prompts 单步调用）
│   ├── moon.pkg
│   ├── prompts.mbt
│   └── minimal_test.mbt
├── flow/                             # [Layer 3C] 支持 Step-Back 回退与 CI 默认值策略的声明式向导编排器
│   ├── moon.pkg
│   ├── wizard.mbt
│   └── flow_test.mbt
└── cmd/
    ├── demo/                         # [Layer 4A] CLI 交互演示程序（native / js / wasm）
    │   ├── moon.pkg                  # pkgtype(kind: "executable")
    │   └── main.mbt
    └── web_demo/                     # [Layer 4B] 面向 doc-web xterm.js 的浏览器 JS/Wasm Demo 导出入口
        ├── moon.pkg                  # supported_targets = "-all+js+wasm"
        └── demo.mbt
```

## 2. `moon.mod` 与 `moon.pkg` 配置基线

### 2.1 `moon.mod`（零外部第三方依赖，对齐 `moonset` ADR-003）

```moonbit
name = "unmbt/clack"
version = "0.1.0"
readme = "README.mbt.md"
repository = "https://github.com/unmbt/clack"
license = "MIT"
keywords = ["cli", "clack", "prompt", "wizard", "terminal", "ansi"]
description = "Zero-dependency streaming CLI prompts, wizard flows, spinners, and SGR styling with dual Clack & Minimal themes for MoonBit"
preferred_target = "native"
supported_targets = "+native+js+wasm+wasm-gc"
```

### 2.2 子包后端裁剪与 `moon.pkg` 基线

* **`ansi/moon.pkg` 与 `core/moon.pkg`（零异步纯内核）**：
  * 不导入任何 `moonbitlang/core/async*` 包；
  * 省略 `supported_targets`（默认全四目标支持：`native`、`js`、`wasm`、`wasm-gc`）。
* **`term/moon.pkg`（跨平台与浏览器异步 I/O 边界）**：
  ```moonbit
  import {
    "moonbitlang/core/async",
    "moonbitlang/core/async/aqueue",
    "moonbitlang/core/encoding/utf8",
    "moonbitlang/core/env",
    "unmbt/clack/ansi",
    "unmbt/clack/core",
  }

  #cfg(any(target="native", target="wasm"))
  import {
    "moonbitlang/core/async/stdio",
  }

  #cfg(target="js")
  import {
    "moonbitlang/core/async/js_async",
  }

  supported_targets = "-all+native+js+wasm"

  options(
    "allow-experimental-packages": [
      "moonbitlang/core/async",
      "moonbitlang/core/async/aqueue",
      "moonbitlang/core/async/stdio",
      "moonbitlang/core/async/js_async",
    ],
    "native-stub": [ "native_stub.c" ],
    targets: {
      "term_native.mbt": [ "native" ],
      "term_js.mbt": [ "js" ],
      "term_wasm.mbt": [ "wasm" ],
    },
  )
  ```
  > 注：若 Phase 3 实测发现 Windows Raw Mode 需通过 C 线程 + 匿名管道将 `ReadConsoleInputW` 接入事件循环，可按 `#cfg(target="native")` 条件追加 `"moonbitlang/core/async/raw_fd"`（`raw_fd` 仅支持 `native`），严禁泄漏到 `js` 或 `wasm` 构建路径。
* **`prompts/moon.pkg`、`minimal/moon.pkg`、`flow/moon.pkg` 与根包 `moon.pkg`**：
  * 统一声明 `supported_targets = "-all+native+js+wasm"`；
  * 仅导入各自实际用到的标准库异步包（如 `prompts` 导入 `"moonbitlang/core/async"` 并声明 `"allow-experimental-packages": ["moonbitlang/core/async"]`）；
  * **严禁任何子包反向导入根包 `unmbt/clack`**。
* **`cmd/demo/moon.pkg`**：声明 `pkgtype(kind: "executable")` 与 `supported_targets = "-all+native+js+wasm"`。
* **`cmd/web_demo/moon.pkg`**：声明 `supported_targets = "-all+js+wasm"`（导出供前端 `doc-web` 加载的 JS ES Module 异步向导桥接与纯核 Wasm 体验函数，详见 [ADR-002](../decisions/002-core-async-and-multi-target-web-demo.md)）。

## 3. AI-Native `declare` 核心接口契约

在每个阶段开始编码实现前，智能体必须先在对应包内落盘以下 `declare` 规范声明（整型统一使用 `Int32`），运行 `moon check` 验证类型闭合，再逐个补齐函数体并消除未实现告警。

### 3.1 `unmbt/clack/ansi` 接口契约

```moonbit
#derive(Debug, Eq, Hash)
pub(all) enum ColorLevel {
  None
  Ansi16
  Ansi256
  TrueColor
}

#derive(Debug, Eq)
pub struct Styler {
  level : ColorLevel
}

declare pub fn detect_color_level(
  is_tty~ : Bool,
  env_lookup~ : (String) -> String?,
) -> ColorLevel

declare pub fn Styler::Styler(level? : ColorLevel) -> Styler
declare pub fn Styler::enabled(self : Styler) -> Bool
declare pub fn Styler::bold(self : Styler, text : StringView) -> String
declare pub fn Styler::dim(self : Styler, text : StringView) -> String
declare pub fn Styler::italic(self : Styler, text : StringView) -> String
declare pub fn Styler::underline(self : Styler, text : StringView) -> String
declare pub fn Styler::inverse(self : Styler, text : StringView) -> String
declare pub fn Styler::hidden(self : Styler, text : StringView) -> String
declare pub fn Styler::strikethrough(self : Styler, text : StringView) -> String
declare pub fn Styler::cyan(self : Styler, text : StringView) -> String
declare pub fn Styler::green(self : Styler, text : StringView) -> String
declare pub fn Styler::yellow(self : Styler, text : StringView) -> String
declare pub fn Styler::red(self : Styler, text : StringView) -> String
declare pub fn Styler::magenta(self : Styler, text : StringView) -> String
declare pub fn Styler::blue(self : Styler, text : StringView) -> String
declare pub fn Styler::gray(self : Styler, text : StringView) -> String
declare pub fn Styler::white(self : Styler, text : StringView) -> String
declare pub fn Styler::bg_white(self : Styler, text : StringView) -> String

/// 剥离所有 CSI / OSC ANSI 转义序列，返回纯可见文本
declare pub fn strip_ansi(input : StringView) -> String

/// 计算剥离 ANSI 后的终端显示列宽（ASCII=1，CJK/Emoji Presentation=2，控制符/结合音标/U+FE0F/ZWJ=0）
declare pub fn display_width(input : StringView) -> Int32

/// 计算单行文本在给定终端列宽 `cols`（最小按 1 保护）下占据的物理终端行数
declare pub fn wrapped_line_count(line : StringView, cols : Int32) -> Int32

/// 按最大列宽折行并保留 ANSI SGR 样式延续
declare pub fn wrap_ansi(text : StringView, max_cols : Int32) -> Array[String]

/// 带首行/续行/末行前缀的 ANSI 安全折行（对标原版 Clack wrapTextWithPrefix）
declare pub fn wrap_text_with_prefix(
  text : StringView,
  cols : Int32,
  prefix : StringView,
  first_prefix? : StringView,
  end_prefix? : StringView,
) -> Array[String]
```

### 3.2 `unmbt/clack/core` 接口契约

```moonbit
#derive(Debug, Eq, Hash)
pub(all) enum KeyCode {
  Char(Char)
  Paste(String)    // Bracketed Paste (\x1b[200~ ... \x1b[201~) 聚合后的完整粘贴载荷
  Enter
  Escape
  Backspace
  Delete
  Tab
  BackTab          // Shift + Tab（用于向导回退或反向焦点）
  Up
  Down
  Left
  Right
  Home
  End
  PageUp
  PageDown
  Space
}

#derive(Debug, Eq, Hash)
pub(all) struct KeyEvent {
  code : KeyCode
  ctrl : Bool
  alt : Bool
  shift : Bool
}

/// 流式按键与括号粘贴解码器（支持跨 read_bytes 分片拼接 UTF-8 与粘贴块）
pub struct KeyDecoder {
  priv mut in_paste : Bool
  priv paste_buf : StringBuilder
  priv pending_bytes : Array[Byte]
}

declare pub fn KeyDecoder::KeyDecoder() -> KeyDecoder
declare pub fn KeyDecoder::feed(self : KeyDecoder, chunk : BytesView) -> Array[KeyEvent]
declare pub fn KeyDecoder::has_pending_escape(self : KeyDecoder) -> Bool
declare pub fn KeyDecoder::flush_escape(self : KeyDecoder) -> KeyEvent?

/// 统一提示返回结果：原生携带 StepBack 信号以同时支撑单步调用与向导栈回退
#derive(Debug, Eq)
pub(all) enum PromptOutcome[T] {
  Submitted(T)
  Cancelled
  StepBack
}

#derive(Debug, Eq)
pub(all) enum PromptPhase {
  Initial
  Active
  Validating       // 异步/提交前校验等待态
  Warning(String)
  Error(String)
  Submitted
  Cancelled
  Reverted         // 当用户在下一步按下回退键时，标记已撤回帧
}

#derive(Debug, Eq)
pub(all) struct SelectOption[T] {
  value : T
  label : String
  hint : String?
  disabled : Bool
}

declare pub fn[T] SelectOption::SelectOption(
  value : T,
  label : String,
  hint? : String,
  disabled? : Bool,
) -> SelectOption[T]

#derive(Debug, Eq)
pub(all) struct GroupOption[T] {
  group : String
  options : Array[SelectOption[T]]
}

declare pub fn[T] GroupOption::GroupOption(
  group : String,
  options : Array[SelectOption[T]],
) -> GroupOption[T]

/// 主题渲染视图模型：彻底解耦交互逻辑与视觉符号（完整保留原版 Clack 1:1 渲染所需字段）
#derive(Debug, Eq)
pub(all) enum BodyView {
  TextInput(
    rendered_value~ : String,
    cursor_pos~ : Int32,
    placeholder~ : String?,
    is_empty~ : Bool,
    is_password~ : Bool,
    raw_text~ : String,
  )
  ConfirmToggle(
    active_yes~ : Bool,
    yes_label~ : String,
    no_label~ : String,
    vertical~ : Bool,
  )
  OptionList(
    items~ : Array[OptionRowView],
    cursor~ : Int32,
    max_items~ : Int32?,
    total_count~ : Int32,
    total_unfiltered~ : Int32,
    filter_query~ : String?,
    filter_cursor~ : Int32,
    filter_placeholder~ : String?,
    is_navigating~ : Bool,
    complete_on_tab~ : Bool,
    show_instructions~ : Bool,
    is_multi~ : Bool,
  )
  GroupOptionList(
    rows~ : Array[GroupRowView],
    cursor~ : Int32,
    max_items~ : Int32?,
    total_count~ : Int32,
    selectable_groups~ : Bool,
    group_spacing~ : Int32,
    show_instructions~ : Bool,
  )
}

#derive(Debug, Eq)
pub(all) struct OptionRowView {
  label : String
  hint : String?
  is_cursor : Bool
  is_selected : Bool
  is_disabled : Bool
  is_multi : Bool
}

#derive(Debug, Eq)
pub(all) enum GroupRowView {
  Header(
    label~ : String,
    is_cursor~ : Bool,
    all_selected~ : Bool,
    partial_selected~ : Bool,
    group_active~ : Bool,
    selectable~ : Bool,
  )
  Item(
    row~ : OptionRowView,
    is_last_in_group~ : Bool,
    in_active_group~ : Bool,
    selectable_groups~ : Bool,
  )
}

#derive(Debug, Eq)
pub(all) struct FrameSpec {
  phase : PromptPhase
  message : String
  body : BodyView
  submitted_summary : String?
  with_guide : Bool
  max_rows : Int32?
}

/// 1:1 复刻原版 Clack limitOptions 滑动窗口与物理行数裁剪算法
declare pub fn limit_options(
  styled_items : Array[String],
  cursor : Int32,
  cols : Int32,
  rows : Int32,
  max_items? : Int32,
  column_padding? : Int32,
  row_padding? : Int32,
  ellipsis? : String,
) -> Array[String]

/// 可插拔视觉主题契约
pub(open) trait Theme {
  fn render_frame(Self, spec : FrameSpec, styler : @ansi.Styler, cols : Int32) -> Array[String]
  fn render_intro(Self, title : StringView, styler : @ansi.Styler) -> String
  fn render_outro(Self, message : StringView, styler : @ansi.Styler) -> String
  fn render_cancel(Self, message : StringView, styler : @ansi.Styler) -> String
  fn render_note(Self, title : StringView, body : StringView, styler : @ansi.Styler) -> String
  fn render_log(Self, kind : StringView, message : StringView, styler : @ansi.Styler) -> String
}

pub struct ClackTheme {
  unicode : Bool
}
declare pub fn ClackTheme::ClackTheme(unicode? : Bool) -> ClackTheme
declare pub impl Theme for ClackTheme

pub struct MinimalTheme {
  unicode : Bool
}
declare pub fn MinimalTheme::MinimalTheme(unicode? : Bool) -> MinimalTheme
declare pub impl Theme for MinimalTheme

/// 无头组件统一适配器（规避 MoonBit 无 trait 关联类型限制，见 ADR-003）
pub struct PromptAdapter[T] {
  on_key : (KeyEvent, Bool) -> PromptOutcome[T]?
  view : () -> FrameSpec
}

declare pub fn[T] PromptAdapter::PromptAdapter(
  on_key~ : (KeyEvent, Bool) -> PromptOutcome[T]?,
  view~ : () -> FrameSpec,
) -> PromptAdapter[T]

/// 具体无头组件模型（Phase 2 按此统一模式落盘：TextModel / ConfirmModel / SelectModel[T] / MultiSelectModel[T] / GroupMultiSelectModel[T] / AutocompleteModel[T]）
/// 每个具体模型均实现 `on_key(self, KeyEvent, allow_back~ : Bool) -> PromptOutcome[Output]?`、`view(self) -> FrameSpec` 与 `as_adapter(self) -> PromptAdapter[Output]`

/// 行内差分重绘引擎：输入新帧行数组与终端宽度，输出最小化 ANSI 擦写字节序列
pub struct InlineDiffRenderer {
  priv mut prev_physical_rows : Int32
  priv mut has_rendered : Bool
}
declare pub fn InlineDiffRenderer::InlineDiffRenderer() -> InlineDiffRenderer
declare pub fn InlineDiffRenderer::patch(
  self : InlineDiffRenderer,
  lines : Array[String],
  cols : Int32,
  sync_output~ : Bool,
) -> String
declare pub fn InlineDiffRenderer::commit(
  self : InlineDiffRenderer,
  final_lines : Array[String],
  cols : Int32,
  sync_output~ : Bool,
) -> String
declare pub fn InlineDiffRenderer::reset(self : InlineDiffRenderer) -> Unit

/// 纯同步推模式驱动（零异步、四目标可用，专供 Web Wasm/JS 无协程嵌入或单步调试）
pub struct InlineDriver[T] {
  priv adapter : PromptAdapter[T]
  priv theme : &Theme
  priv styler : @ansi.Styler
  priv renderer : InlineDiffRenderer
  priv decoder : KeyDecoder
  priv allow_back : Bool
  priv sync_output : Bool
  priv mut cols : Int32
  priv mut rows : Int32
}

declare pub fn[T] InlineDriver::InlineDriver(
  adapter : PromptAdapter[T],
  theme? : &Theme,
  styler? : @ansi.Styler,
  cols? : Int32,
  rows? : Int32,
  allow_back? : Bool,
  sync_output? : Bool,
) -> InlineDriver[T]
declare pub fn[T] InlineDriver::start(self : InlineDriver[T]) -> String
declare pub fn[T] InlineDriver::feed(self : InlineDriver[T], chunk : BytesView) -> (String, PromptOutcome[T]?)
declare pub fn[T] InlineDriver::flush_escape(self : InlineDriver[T]) -> (String, PromptOutcome[T]?)
declare pub fn[T] InlineDriver::resize(self : InlineDriver[T], cols : Int32, rows : Int32) -> String
```

### 3.3 `unmbt/clack/term` 接口契约

```moonbit
pub(all) suberror TermError {
  IoFailure(String)
  NotInteractive(String)
  EndOfInput
}

#derive(Debug, Eq)
pub(all) enum NonInteractivePolicy {
  UseDefaults
  Fail
}

/// 终端抽象接口：隔离 OS 原生句柄、浏览器 xterm.js 回调终端与内存测试桩
pub(open) trait Terminal {
  fn is_tty(Self) -> Bool
  fn size(Self) -> (Int32, Int32)                  // (cols, rows)
  fn env_get(Self, key : String) -> String?
  async fn enter_raw_mode(Self) -> Unit raise TermError
  async fn leave_raw_mode(Self) -> Unit nocancel   // 必须 nocancel 以供 defer 安全调用
  async fn read_bytes(Self) -> Bytes? raise TermError
  async fn write_str(Self, data : StringView) -> Unit raise TermError
  async fn write_final(Self, data : StringView) -> Unit nocancel
}

/// 确定性内存虚拟终端：供单元测试直接喂入按键/括号粘贴字节序列并断言渲染快照
pub struct VirtualTerminal {
  priv scripted_keys : Array[Bytes]
  priv mut cursor : Int32
  priv output_frames : Array[String]
  priv mut cols : Int32
  priv mut rows : Int32
  priv tty : Bool
  priv env : Map[String, String]
  priv mut in_raw_mode : Bool
}

declare pub fn VirtualTerminal::VirtualTerminal(
  scripted_keys : Array[Bytes],
  cols? : Int32,
  rows? : Int32,
  tty? : Bool,
  env? : Map[String, String],
) -> VirtualTerminal
declare pub fn VirtualTerminal::frames(self : VirtualTerminal) -> Array[String]
declare pub fn VirtualTerminal::in_raw_mode(self : VirtualTerminal) -> Bool
declare pub impl Terminal for VirtualTerminal

/// 异步队列回调终端：专供浏览器 xterm.js 与外部宿主事件循环接入（native/js/wasm 全支持）
pub struct CallbackTerminal {
  priv input_queue : @aqueue.Queue[Bytes?]
  priv on_write : (StringView) -> Unit
  priv mut cols : Int32
  priv mut rows : Int32
  priv tty : Bool
  priv env : Map[String, String]
  priv mut in_raw_mode : Bool
}

declare pub fn CallbackTerminal::CallbackTerminal(
  on_write~ : (StringView) -> Unit,
  cols? : Int32,
  rows? : Int32,
  tty? : Bool,
  env? : Map[String, String],
) -> CallbackTerminal
declare pub fn CallbackTerminal::push_input(self : CallbackTerminal, chunk : Bytes) -> Unit
declare pub fn CallbackTerminal::push_text(self : CallbackTerminal, data : StringView) -> Unit
declare pub fn CallbackTerminal::set_size(self : CallbackTerminal, cols : Int32, rows : Int32) -> Unit
declare pub fn CallbackTerminal::close(self : CallbackTerminal) -> Unit
declare pub impl Terminal for CallbackTerminal
```

### 3.4 `prompts`、`minimal`、`flow` 与根包门面契约

```moonbit
// --- unmbt/clack/prompts（minimal 包保持同构签名，默认绑定 MinimalTheme）---
pub struct Session {
  term : &@term.Terminal
  theme : &@core.Theme
  styler : @ansi.Styler
  non_interactive : @term.NonInteractivePolicy
  with_guide : Bool
}

declare pub fn Session::Session(
  term? : &@term.Terminal,
  theme? : &@core.Theme,
  color_level? : @ansi.ColorLevel,
  non_interactive? : @term.NonInteractivePolicy,
  with_guide? : Bool,
) -> Session

declare pub async fn intro(title : StringView, session? : Session) -> Unit raise @term.TermError
declare pub async fn outro(message : StringView, session? : Session) -> Unit raise @term.TermError
declare pub async fn cancel(message : StringView, session? : Session) -> Unit raise @term.TermError
declare pub async fn note(title : StringView, body : StringView, session? : Session) -> Unit raise @term.TermError

declare pub async fn log_info(message : StringView, session? : Session) -> Unit raise @term.TermError
declare pub async fn log_step(message : StringView, session? : Session) -> Unit raise @term.TermError
declare pub async fn log_success(message : StringView, session? : Session) -> Unit raise @term.TermError
declare pub async fn log_warn(message : StringView, session? : Session) -> Unit raise @term.TermError
declare pub async fn log_error(message : StringView, session? : Session) -> Unit raise @term.TermError
declare pub async fn log_message(message : StringView, symbol? : StringView, session? : Session) -> Unit raise @term.TermError

declare pub async fn[T] run_prompt(
  adapter : @core.PromptAdapter[T],
  allow_back? : Bool,
  session? : Session,
) -> @core.PromptOutcome[T] raise @term.TermError

declare pub async fn text(
  message : String,
  placeholder? : String,
  default_value? : String,
  initial_value? : String,
  validate? : (String) -> String?,
  allow_back? : Bool,
  session? : Session,
) -> @core.PromptOutcome[String] raise @term.TermError

declare pub async fn password(
  message : String,
  mask? : Char?,
  validate? : (String) -> String?,
  allow_back? : Bool,
  session? : Session,
) -> @core.PromptOutcome[String] raise @term.TermError

declare pub async fn confirm(
  message : String,
  initial_value? : Bool,
  active_label? : String,
  inactive_label? : String,
  allow_back? : Bool,
  session? : Session,
) -> @core.PromptOutcome[Bool] raise @term.TermError

declare pub async fn[T] select(
  message : String,
  options : Array[@core.SelectOption[T]],
  initial_index? : Int32,
  max_items? : Int32,
  allow_back? : Bool,
  session? : Session,
) -> @core.PromptOutcome[T] raise @term.TermError

declare pub async fn[T] multiselect(
  message : String,
  options : Array[@core.SelectOption[T]],
  initial_indices? : Array[Int32],
  required? : Bool,
  max_items? : Int32,
  allow_back? : Bool,
  session? : Session,
) -> @core.PromptOutcome[Array[T]] raise @term.TermError

declare pub async fn[T] group_multiselect(
  message : String,
  groups : Array[@core.GroupOption[T]],
  initial_values? : Array[T],
  required? : Bool,
  max_items? : Int32,
  allow_back? : Bool,
  session? : Session,
) -> @core.PromptOutcome[Array[T]] raise @term.TermError

declare pub async fn[T] autocomplete(
  message : String,
  options : Array[@core.SelectOption[T]],
  placeholder? : String,
  max_items? : Int32,
  filter? : (String, @core.SelectOption[T]) -> Bool,
  allow_back? : Bool,
  session? : Session,
) -> @core.PromptOutcome[T] raise @term.TermError

/// 异步旋转加载指示器（非 TTY 时降级为静态开始/结束日志）
pub struct Spinner {
  priv session : Session
  priv frames : Array[String]
  priv interval_ms : Int32
  priv show_timer : Bool
  // 内部取消与消息同步状态
}
declare pub fn Spinner::Spinner(
  session? : Session,
  frames? : Array[String],
  interval_ms? : Int32,
  show_timer? : Bool,
) -> Spinner
declare pub async fn Spinner::start(self : Spinner, message : StringView) -> Unit raise @term.TermError
declare pub fn Spinner::message(self : Spinner, message : StringView) -> Unit
declare pub async fn Spinner::stop(self : Spinner, message? : StringView) -> Unit nocancel
declare pub async fn Spinner::fail(self : Spinner, message? : StringView) -> Unit nocancel
declare pub async fn Spinner::cancel(self : Spinner, message? : StringView) -> Unit nocancel
declare pub async fn[T] with_spinner(
  message : StringView,
  task : async (Spinner) -> T,
  done_message? : StringView,
  session? : Session,
) -> T

/// 确定性百分比进度条（非 TTY 时按里程碑输出静态日志）
pub struct Progress {
  priv session : Session
  priv total : Int32
  priv width : Int32
  priv mut current : Int32
  priv mut message : String
}
declare pub fn Progress::Progress(
  total~ : Int32,
  width? : Int32,
  session? : Session,
) -> Progress
declare pub async fn Progress::start(self : Progress, message? : StringView) -> Unit raise @term.TermError
declare pub async fn Progress::advance(self : Progress, delta? : Int32, message? : StringView) -> Unit raise @term.TermError
declare pub async fn Progress::set(self : Progress, value : Int32, message? : StringView) -> Unit raise @term.TermError
declare pub async fn Progress::stop(self : Progress, message? : StringView) -> Unit nocancel
declare pub async fn Progress::fail(self : Progress, message? : StringView) -> Unit nocancel

// --- unmbt/clack/flow（支持 Step-Back 回退的状态向导编排器）---
pub struct Step[State] {
  id : String
  when : (State) -> Bool
  run : async (State, @prompts.Session, Bool) -> @core.PromptOutcome[State] raise @term.TermError
}

declare pub fn[State] Step::Step(
  id : String,
  when? : (State) -> Bool,
  run : async (State, @prompts.Session, Bool) -> @core.PromptOutcome[State] raise @term.TermError,
) -> Step[State]

/// 运行多步向导：自动维护快照历史栈 (step_index, prior_state)
/// 当步骤返回 StepBack 时，自动弹出上一个实际执行过的步骤并传入回退前的 State 快照重跑
declare pub async fn[State] run_wizard(
  initial : State,
  steps : Array[Step[State]],
  session? : @prompts.Session,
) -> @core.PromptOutcome[State] raise @term.TermError
```

> **根包 `exports.mbt` 门面约定**：根包 `unmbt/clack` 统一使用新版 `pub using` 零样板重导出（对齐 `unmbt/moonset`）：
> - `pub using @core { type SelectOption, type GroupOption, type PromptOutcome, type PromptAdapter, type InlineDriver }`
> - `pub using @term { type TermError, type NonInteractivePolicy, type VirtualTerminal, type CallbackTerminal }`
> - `pub using @prompts { type Session, type Spinner, type Progress, intro, outro, cancel, note, log_info, log_step, log_success, log_warn, log_error, log_message, run_prompt, text, password, confirm, select, multiselect, group_multiselect, autocomplete, with_spinner }`
> - `pub using @flow { type Step, run_wizard }`
>
> 下游仅需导入 `"unmbt/clack"` 即可通过 `@clack.*` 完成 95% 的常见开发。
