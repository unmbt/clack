# 项目定位、生态辨析与需求规格矩阵

## 1. 项目背景、核心定位与生态边界

### 1.1 生态痛点与项目定位

当前 MoonBit 终端交互生态在“轻量 CLI 向导”层存在明显空白：底层原语库 [moonbit-community/tty](https://github.com/moonbit-community/tonyfettes-tty) 仅负责原始模式与终端控制序列且不包含交互组件（同时携带 ~9.89 MB 嵌入式 sidecar 二进制并排除 `js` 后端，详见 [ADR-001](../decisions/001-tty-backend-strategy.md)），而上层框架 [mizchi/tui](https://mooncakes.io/docs/mizchi/tui) 引入了完整 CSS 布局引擎与虚拟 DOM，对于脚手架初始化、发版确认等流式 CLI 场景过于厚重。

`unmbt/clack` 旨在提供一套**零外部第三方依赖、零布局引擎、保留终端滚屏历史、支持双调用范式与双视觉主题**的流式 CLI 交互表单与终端美化套件，直接服务 [unmbt/moonset](https://mooncakes.io/docs/unmbt/moonset@0.2.0)、[unmbt/moon-bump](https://mooncakes.io/docs/unmbt/moon-bump)、`unmbt/moon-taze`、社区 CLI 工具以及面向文档站的浏览器 `xterm.js` 在线体验 Demo：

1. **视觉双主题解耦**：同一套状态机同时内置导轨向导主题（对标 [@clack/prompts](https://github.com/bombshell-dev/clack) 的 `┌ / │ / ◆ / └` 竖向时间轴风格）与极简问答主题（对标 [terkelg/prompts](https://github.com/terkelg/prompts) 的 `? / ✔ / ›` 单行紧凑风格）。
2. **调用双范式共存**：同时提供强类型命令式逐步调用 API（根包 `@clack` / `@prompts` 与 `@minimal`）以及带状态栈的声明式向导编排 API（`@flow`），后者原生支持**快捷键退回上一步重填（Step-Back）**，直接解决原版 Clack 与 `create-vite` 长期存在的无法回退痛点（参见 [vitejs/vite#21828](https://github.com/vitejs/vite/issues/21828)）。
3. **吸收 `moonset` 实战经验与分组多选**：结合 [moonset/cli](../../../moonset/cli/) 内联 TUI 的落地经验（Windows `WriteConsoleW` UTF-8 输出、QuickEdit 保留、视口高度钳制与宽字符/Emoji 宽度算法），并将 `group_multiselect[T]` 纳入一级题型，使 `moonset` 等下游工具可直接平滑迁移。
4. **无头纯内核 + 跨端适配（含浏览器 `xterm.js` Demo）**：90% 以上的逻辑（按键与括号粘贴解码、组件状态转移、行宽折行计算、行内差分重绘指令生成）收敛于零 I/O 的纯函数内核，可在无真实 TTY 的 CI 环境中通过 `VirtualTerminal` 实现 100% 确定性单测；并支持编译为 `js` / `wasm` 产物直接驱动文档站（参考 `moonset/doc-web`）中的 `xterm.js` 实时交互体验。

### 1.2 生态边界辨析：与 `sennenki/pretty_prompt` 的本质区别

在终端工程领域，英文“Prompt”对应两个截然不同的软件品类。Mooncakes 现有的 [`sennenki/pretty_prompt@0.1.2`](https://mooncakes.io/docs/sennenki/pretty_prompt@0.1.2)（源码仓库 [`zvmsbackend/pretty_prompt`](https://github.com/zvmsbackend/pretty_prompt)）移植自 C# `.NET` 生态的 **REPL 代码行编辑器**（同类产品为 GNU `readline`、Rust `rustyline`/`reedline`），而本项目 `unmbt/clack` 属于 **CLI 表单与脚手架问答向导库**（同类产品为 `@clack/prompts`、`terkelg/prompts`、Rust `inquire`）。两者赛道正交、零功能冲突：

| 对比维度 | [`sennenki/pretty_prompt`](https://mooncakes.io/docs/sennenki/pretty_prompt@0.1.2) | 本项目 `unmbt/clack` |
| :--- | :--- | :--- |
| **核心定位与对标** | **REPL 命令提示符行编辑器**（对标 C# PrettyPrompt / Rust `reedline`），服务交互式 Shell 与解释器代码输入 | **CLI 交互表单与脚手架向导套件**（对标 `@clack/prompts` + `terkelg/prompts` / Rust `inquire`），服务项目生成与工作流问答 |
| **交互入口形态** | 唯一入口 [`Prompt::read_line()`](https://mooncakes.io/docs/sennenki/pretty_prompt@0.1.2/core)，在提示符后编辑一段支持语法高亮的代码文本 | 多题型组件：`text`、`password`、`confirm`、`select[T]`、`multiselect[T]`、`group_multiselect[T]`、`autocomplete[T]`、`spinner`、`progress`、`log`、`run_wizard` |
| **核心内部模块** | [`editing` 子包](https://mooncakes.io/docs/sennenki/pretty_prompt@0.1.2/editing)聚焦历史文件持久化、`Ctrl+R` 反向搜索、Emacs `KillRing`、Undo/Redo、函数重载签名弹窗与系统剪贴板依赖 | 聚焦多题型选择状态机、导轨/极简双主题渲染、`StepBack` 上一步回退历史栈、`NO_COLOR` SGR 着色、CI 非交互降级与 Web `xterm.js` 演示桥接 |
| **维护与工具链状态** | 停更于较早周期，仓库仍使用已在 [MoonBit v0.10.19](https://www.moonbitlang.com/updates/) 移除支持的 `moon.mod.json`，锁定旧版 `async@0.17.1`，无法在现代工具链直接编译 | 原生面向 `v0.10.22+` 的 `moon.mod` DSL、标准库 `moonbitlang/core/async` 编译器级取消原语，零第三方运行时依赖，支持 `native` / `js` / `wasm`（及纯核 `wasm-gc`） |

**命名与设计吸收决策**：
* **定名 `unmbt/clack`**：既然生态中已有包将 `prompt` 语境用于 REPL 命令提示符，本项目直接命名为 `unmbt/clack`，使寻找 `create-vite` 式脚手架交互向导的开发者在 `mooncakes.io` 一眼识别，彻底消除概念混淆。
* **吸收粘贴防误触经验**：借鉴行编辑器对多行粘贴与 `CRLF` 清洗的防护思路，`unmbt/clack` 在 `term` 与 `core` 层原生引入终端 **Bracketed Paste（`\x1b[?2004h` 括号粘贴模式）**，防止用户向 `text` / `password` 输入框粘贴含换行符的文本时，换行符被误判为 `Enter` 而一路连环自动提交后续的 `select` / `confirm` 步骤。

### 1.3 明确非目标（Non-Goals — 智能体严禁越界实现）

* **不做 REPL 代码编辑器**：不实现命令历史文件落盘、`Ctrl+R` 历史搜索、语法高亮词法器、多行代码缩进编辑或系统剪贴板外部依赖。
* **不做全屏接管 TUI 框架**：严禁切换到终端备用屏幕缓冲区（`\x1b[?1049h`），严禁发送清屏序列（`\x1b[2J\x1b[H`）污染用户滚屏历史，不实现二维 Flexbox/Grid 窗口分割。
* **不发布面向 Node.js 用户的 N-API `.node` 原生扩展包**：本模块的 `js` 与 `wasm` 后端用于保证 MoonBit CLI 在 `moon build --target js` / `wasm` 下的可用性，以及为类似 `moonset/doc-web` 的文档站提供浏览器 `xterm.js` 实时交互 Demo 产物，不为 JavaScript 生态额外封装 npm C++ 原生二进制分发包。
* **不引入重型或外部第三方运行期依赖**：对齐 `unmbt/moonset` [ADR-003](../../../moonset/docs/decisions/003-core-async.md)，运行期依赖仅限官方标准库 `moonbitlang/core` 及其实验性异步子包 `moonbitlang/core/async`（`ansi` 与 `core` 层甚至零异步依赖）；严禁引入外部 `moonbitlang/async`、CSS/DOM 布局引擎或嵌入式 sidecar 二进制包。

## 2. 功能与非功能需求规格矩阵

> **追踪说明**：所有 `REQ-*` 需随各阶段交付同步更新 `状态`（`Proposed` / `Accepted` / `Implemented` / `Deferred` / `Rejected`）与 `验证证据`（见 [SDD 规约](../sdd.md)）。

| 需求编号 | 模块域 | 规格描述 | 验收标准（Acceptance Criteria） | 状态 | 验证证据 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **REQ-STYLE-01** | 颜色与能力探测 | 自动解析 `NO_COLOR`、`FORCE_COLOR`、`TERM=dumb`、`CI` 环境变量及输出流 TTY 状态，推导 `ColorLevel`（`None`、`Ansi16`、`Ansi256`、`TrueColor`） | 当 `NO_COLOR` 非空（任意值）且未显式传入代码级覆盖时，所有输出必须为 0 字节 SGR 转义序列的纯文本 | Accepted | 待 Phase 1 落地 |
| **REQ-STYLE-02** | 链式 SGR 着色 | 提供零全局状态的 `Styler`（基于 `ColorLevel` 实例），支持 16 基础色、粗体、暗淡、斜体、下划线、删除线、反色与按需嵌套重置 | 嵌套着色如 `s.cyan("a " + s.bold("b") + " c")` 在 `"b"` 结束后必须精确恢复外层青色而非重置整段 `0m` | Accepted | 待 Phase 1 落地 |
| **REQ-RENDER-01** | 行内差分重绘 | 渲染器仅在当前光标位置向下绘制活动帧，记录上一帧在当前终端列宽 `cols` 下占据的**实际物理折行行数**，下一帧用相对上移 `\x1b[{N}A\r\x1b[J` 重写，并处理窗口 `resize` 与视口高度钳制 | 连续触发 100 次按键重绘后，交互上方的历史终端输出保持零位移、零清屏闪烁、零残影 | Accepted | 待 Phase 2 落地 |
| **REQ-RENDER-02** | 宽字符折行精度 | 计算物理行数时必须剥离 CSI/OSC ANSI 转义序列，并按 Unicode 宽度规则计算列宽（ASCII=1、CJK/Emoji Presentation=2、`✓`/`✗`=1、结合音标/`U+FE0F`/ZWJ/控制符=0） | 在 40 列窄终端下渲染含中文与 Emoji（如 `🚀`）的长提示与长输入值，多行自动折行后的光标回退行数误差必须为 0 | Accepted | 待 Phase 1 落地 |
| **REQ-RENDER-03** | 防撕裂同步输出 | 在真实 TTY 输出时，整帧擦除与重绘字节流合并为单次写入，并包裹 DEC Mode 2026 同步更新序列（`\x1b[?2026h` ... `\x1b[?2026l`） | 单帧 `write` 调用次数严格等于 1，消除 Windows Terminal、iTerm2、Kitty、WezTerm 下的光标跳变 | Accepted | 待 Phase 2 落地 |
| **REQ-INPUT-01** | 括号粘贴与 Esc 消歧 | 交互期间开启 `\x1b[?2004h`，`KeyDecoder` 识别 `\x1b[200~...\x1b[201~`（跨分片拼接 + 1 MiB 上限 + `0x03` 逃生）并清洗 `CRLF`；驱动层配合 20ms 超时窗口调用 `flush_escape()` 区分裸 `Esc` 与拆包 CSI 序列 | 向 `text` 或 `password` 粘贴 `"my-app\r\ny\r\n"` 时，内部换行不会触发 `Enter` 提交，更不会泄露至下一步确认；拆包的 `\x1b[A` 不会误判为 `Escape` | Accepted | 待 Phase 2/3 落地 |
| **REQ-WIDGET-01** | 文本与密码输入 | 实现 `text` 与 `password`（支持 `*` 掩码与完全隐藏两种模式）：支持左右方向键、`Home`/`End`、按字符退格/删除、`Tab` 补全默认值或占位符、即时/提交校验函数 | 输入或粘贴中文多字节 UTF-8 字符并移动光标、在中间插入与退格时，不会截断 UTF-8 字节或 UTF-16 代理对 | Accepted | 待 Phase 2/4 落地 |
| **REQ-WIDGET-02** | 布尔确认 | 实现 `confirm`：支持左右切换、`y`/`Y`/`n`/`N` 快捷选择、默认值 `Enter` 提交与自定义激活/非激活文案 | 提交后当前交互帧自动折叠为单行已提交摘要（如 `◇ 是否立即发布？ · 是` 或 `✔ 是否立即发布？ › 是`） | Accepted | 待 Phase 2/4 落地 |
| **REQ-WIDGET-03** | 单选与视口滚动 | 实现泛型 `select[T]`：支持上下键、`j`/`k` 循环跳转、自动跳过 `disabled: true` 项、当前选中项旁展示 `hint` 说明，以及选项超出 `max_items`（受终端 `rows` 钳制）时的滑动窗口分页 | 传入 30 个选项且 `max_items=6` 时，帧高度恒定且上下滚动指示平顺；空列表或全禁用列表直接返回明确校验错误而非死循环 | Accepted | 待 Phase 2/4 落地 |
| **REQ-WIDGET-04** | 多选与全选控制 | 实现泛型 `multiselect[T]`：支持空格切换选中、`a` 全选/全取消、`i` 反选、`required: true` 必选最少一项拦截提示 | 未选任何项按下 `Enter` 且 `required=true` 时，状态切换为 `Warning` 并在底部显示校验提示，按任意导航键自动清除告警 | Accepted | 待 Phase 2/4 落地 |
| **REQ-WIDGET-04B** | 分组多选 | 实现泛型 `group_multiselect[T]`：支持按分组标题折叠树形展示（如 `moonset` 的 `changed`/`unchanged` 包分组）、按 `Space` 对分组标题一键整组切换勾选/取消及单条目微调、`required` 校验与视口分页 | 在分组头按 `Space` 可准确全选/全取消该组全部未禁用条目；提交后保留全部分组已选值 | Accepted | 待 Phase 2/4 落地 |
| **REQ-WIDGET-05** | 模糊搜索单选 | 实现 `autocomplete[T]`（过滤单选）：结合实时文本输入与候选列表动态筛选（默认大小写不敏感子串 + 顺序字符匹配，支持注入自定义 `filter` 闭包） | 输入 `j`/`k`/`a`/`i`/`Space` 等字符时写入搜索框而非误触发列表导航，上下方向键可在剩余匹配项间移动，无匹配项时展示可配置的空状态文案 | Accepted | 待 Phase 2/4 落地 |
| **REQ-WIDGET-06** | 异步加载与日志 | 实现 `Spinner`（动画帧循环任务包装器）、`Progress`（确定性百分比进度条）以及静态块 `intro`、`outro`、`note`、`log_{info,step,success,warn,error,message}` | 在非 TTY / CI 管道环境下，`Spinner` 与 `Progress` 自动降级为单行静态开始与结束日志，不启动后台定时刷新协程 | Accepted | 待 Phase 4 落地 |
| **REQ-FLOW-01** | 双 API 与回退栈 | 提供 `@clack`（导轨）与 `@minimal`（极简）命令式函数，以及 `@flow` 多步状态编排器；在 `flow` 中按 `Esc` 或 `Shift+Tab` 退回上一个实际执行过的步骤 | 若步骤 2 因 `when` 条件返回 `false` 被跳过，在步骤 3 按下回退键必须直接回到步骤 1，并将步骤 1 上次填写的值作为 `initial` 回填 | Accepted | 待 Phase 4 落地 |
| **REQ-FLOW-02** | 非交互与信号安全 | 支持 `NonInteractivePolicy`（`UseDefaults` 自动填充默认值、`Fail` 立即返回 `NotInteractive`）；收到 `Ctrl+C` 或异步取消时 100% 恢复终端状态（含 C 侧 `atexit`/`SetConsoleCtrlHandler` 兜底） | 模拟 `Ctrl+C`（字节 `0x03`）或外部 `core/async` `with_timeout` / `Task::cancel` 时，括号粘贴关闭（`\x1b[?2004l`）、终端回显模式恢复、光标重新可见（`\x1b[?25h`），并输出取消收尾行 | Accepted | 待 Phase 3/4 落地 |
| **REQ-WEB-01** | 浏览器 `xterm.js` Demo 桥接 | 提供两条前端接入路径：`term::CallbackTerminal`（`--target js` 结合 `core/async/js_async` 驱动完整异步向导、`Spinner` 与 `Progress`）与 `core::InlineDriver[T]`（纯同步推模式，支持 `js`/`wasm`/`wasm-gc`） | `cmd/web_demo` 可编译为浏览器可加载的 `--target js` 模块并接入 React + `@xterm/xterm` 画布响应键盘、粘贴与容器 resize；`InlineDriver` 可在四目标通过单测 | Accepted | 待 Phase 2/3/5 落地 |

## 3. 参考规范与决策索引

* **本项目 SDD 规约与决策记录**：[SDD 规约](../sdd.md)、[参考实现剖析与 MoonBit 架构设计](../references.md)、[ADR-001 TTY 策略](../decisions/001-tty-backend-strategy.md)、[ADR-002 `core/async` 与 Web Demo](../decisions/002-core-async-and-multi-target-web-demo.md)、[ADR-003 `PromptAdapter` 抽象](../decisions/003-prompt-model-abstraction.md)、[ADR-004 终端生命周期与 Resize](../decisions/004-terminal-lifecycle-and-resize.md)
* **MoonBit 语言与工具链更新规范**：[MoonBit Updates (v0.8.0 – v0.10.22)](https://www.moonbitlang.com/updates/)（`declare` SDD 规范、新版 `moon.mod`/`moon.pkg` DSL、`defer`/`nocancel` 语义与 `.mbti` 接口生成）
* **MoonBit 标准库异步基座**：`moonbitlang/core/async`（参考 `unmbt/moonset` [ADR-003](../../../moonset/docs/decisions/003-core-async.md)）
* **导轨向导视觉与组件对标**：[bombshell-dev/clack (@clack/core & @clack/prompts)](https://github.com/bombshell-dev/clack)
* **极简行内交互视觉对标**：[terkelg/prompts](https://github.com/terkelg/prompts)
* **向导回退需求来源**：[vitejs/vite#21828 (create-vite return to previous step)](https://github.com/vitejs/vite/issues/21828)
* **生态异构品类对照（REPL 行编辑器）**：[sennenki/pretty_prompt@0.1.2](https://mooncakes.io/docs/sennenki/pretty_prompt@0.1.2)（[`zvmsbackend/pretty_prompt`](https://github.com/zvmsbackend/pretty_prompt)）
* **UnMBT 实战参考与下游**：[unmbt/moonset](../../../moonset/)（含 [cli/tty_native.c](../../../moonset/cli/tty_native.c)、[cli/tui_render.mbt](../../../moonset/cli/tui_render.mbt)、[doc-web](../../../moonset/doc-web/)）与 [unmbt/moon-bump](../../../moon-bump/)
