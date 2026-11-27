# unmbt/clack 智能体工程总纲（AGENTS.md）

> **模块标识**：`unmbt/clack`（隶属 [UnMoonBit (@unmbt)](https://github.com/unmbt) 工具家族）  
> **目标编译器与工具链**：[MoonBit v1.0.0-rc1+](https://www.moonbitlang.com/updates/)（`moon 0.1.20261126+`）  
> **许可协议**：MIT  
> **目标编译后端**：`native`（主力一等公民）、`js`（Node.js / Deno / Bun CLI 与浏览器 `xterm.js` Demo）、`wasm`（基础与浏览器核心兼容）；纯状态机内核 `ansi` 与 `core` 额外兼容 `wasm-gc`  
> **文档用途**：面向 AI 编码智能体（SeekMoon / Claude Code / Codex）的顶层协作入口与语法红线。智能体在修改任何代码前，必须先阅读本总纲与 [`docs/README.md`](./docs/README.md)，再按需加载 [`docs/spec/`](./docs/spec/) 与 [`docs/decisions/`](./docs/decisions/) 下的专项规格文档。

## 1. SDD 规格文档导航索引

本项目的规格驱动开发（SDD, Spec-Driven Development）文档按治理、决策与分册规格组织，智能体必须按阶段与任务边界精准加载上下文：

| 文档路径 | 核心职责 | 必读时机 |
| :--- | :--- | :--- |
| [`docs/README.md`](./docs/README.md) | 文档总览、阅读顺序、状态标记说明与已实证工具链基线 | 初次进入仓库或核对环境基线时 |
| [`docs/sdd.md`](./docs/sdd.md) | SDD 追踪链路、五步交付节奏与 v0.1 不可变设计原则 | 新增特性、修改契约或评审设计边界时 |
| [`docs/references.md`](./docs/references.md) | 原版 Clack 源码级剖析、借鉴与扬弃矩阵、MoonBit 版全景架构总结 | 理解架构由来、组件取舍或规划后续扩展时 |
| [`docs/decisions/README.md`](./docs/decisions/README.md) | 架构决策记录（ADR-001 ~ ADR-004）：TTY 策略、`core/async` 与 Web Demo、`PromptAdapter`、终端生命周期 | 涉及异步库、FFI、浏览器接入或抽象调整时 |
| [`docs/spec/requirements.md`](./docs/spec/requirements.md) | 生态痛点、与 `sennenki/pretty_prompt` 的赛道边界辨析、Non-Goals、以及 `REQ-*` 验收与状态矩阵 | 项目初始化、评审新增特性、编写或回写验收测试时 |
| [`docs/spec/architecture-and-contracts.md`](./docs/spec/architecture-and-contracts.md) | 包分层 DAG 拓扑、`moon.mod` / `moon.pkg` 配置基线、以及各子包的 `declare` 强类型接口契约 | Phase 0 落盘桩文件、跨包调用或核对公共 API 签名时 |
| [`docs/spec/algorithms-and-mechanisms.md`](./docs/spec/algorithms-and-mechanisms.md) | 双主题视觉规范、`InlineDiffRenderer` 行内差分数学不变量、`KeyDecoder` 与括号粘贴解码、跨后端终端与 `xterm.js` 机制 | 实现 `ansi`、`core`、`term` 核心逻辑与 C/JS/Wasm 适配时 |
| [`docs/spec/roadmap-and-acceptance.md`](./docs/spec/roadmap-and-acceptance.md) | Phase 0 至 Phase 5 串行执行计划、测试先行（TDD）必测用例集、以及发布级门禁命令清单 | 推进每个开发阶段及提交前执行自检门禁时 |

## 2. MoonBit v0.10.22+ 强制编译器与语法红线

AI 智能体在编写任何 `.mbt`、`moon.mod`、`moon.pkg` 文件前，必须严格遵守以下 [MoonBit 2026 最新工具链规范](https://www.moonbitlang.com/updates/)，杜绝生成已废弃或不合法的语法：

| 规范维度 | 强制正确写法（v0.10.22+） | 严禁出现的废弃/非法写法 |
| :--- | :--- | :--- |
| **清单文件格式** | 仅使用新版 DSL：`moon.mod` 与 `moon.pkg`（顶层字段用下划线如 `preferred_target`、`supported_targets`）；可执行入口声明 `pkgtype(kind: "executable")`；导出外部库函数使用 `pkgtype(kind: "foreign_library")` + `#export_name("...")`；条件导入使用 `#cfg(...)` | 严禁创建 `moon.mod.json` 或 `moon.pkg.json`；严禁使用 `is-main: true` 或已废弃的 `link.js.exports` |
| **异步运行时依赖** | 统一使用标准库 `moonbitlang/core/async` 及其子包（对齐 `unmbt/moonset` ADR-003），在 `moon.pkg` 显式配置 `"allow-experimental-packages": [...]` | 严禁在 `moon.mod` 引入外部 `moonbitlang/async` 依赖；严禁在纯内核 `ansi`/`core` 导入任何 `core/async*` |
| **整型与基础类型** | 公开契约与长度/索引/坐标统一使用 `Int32`（配合 `moon fmt` 自动规范化）；`StringBuilder` 使用 `write_string` / `write_view` / `write_char` | 避免与 `Int` 混用引发工具链归一化 diff 抖动 |
| **Trait 与组件抽象** | `trait` 与 `impl` 内方法必须带 `fn` 关键字；需点号调用时显式声明 `pub extend Type with Trait::{m}`；多输出组件统一经 `PromptAdapter[T]` 适配器抽象 | **严禁在 `trait` 中声明关联类型**（如 `type Output` / `Self::Output`，MoonBit 不支持）；严禁省略 `fn` 关键字 |
| **属性与派生语法** | 类型上方前置属性 `#derive(Debug, Eq, Hash)`；断言快照统一用 `debug_inspect(val, content=...)` | 严禁后置 `derive(Show)`（已废弃）；仅在具备明确业务文本语义时手写 `impl Show` |
| **自定义构造器与重导出** | 统一使用 `pub fn Type::Type(...) -> Type` 构造器语法；根包门面使用 `pub using @pkg { ... }` 重导出 | 严禁使用旧版结构体内部声明 `fn new` 的双写构造语法；避免不必要的重复包装转发函数 |
| **错误定义与守卫** | 使用枚举式 `pub(all) suberror TermError { ... }`；非穷尽解构显式写 `guard ... else { ... }` | 严禁旧式单行 `type! Err Payload`、`try?` 或隐式 `Failure(..)` 构造 |
| **异步取消与资源清理** | 使用 `defer` / `errdefer` 恢复终端原始模式、括号粘贴与光标显示；清理函数必须标记 `nocancel`（内部必要时使用 `@async.protect_from_cancel`） | 严禁用 `catch` 捕获取消信号（取消为编译器原语，不可被 `catch` 吞没） |
| **黑盒测试与行尾规范** | `_test.mbt` 必须通过 `@pkg.fn_name` 显式限定被测包 API；仓库根目录必须内置 `.gitattributes` 锁定 LF | 严禁依赖黑盒测试隐式导入；严禁让 Windows `CRLF` 污染 `pkg.generated.mbti` |

## 3. 智能体工程执行纪律

1. **`declare` 契约先行与 SDD 闭环**：进入任一子包实现前，必须先按 `docs/spec/architecture-and-contracts.md` 原样落盘 `declare` 签名并通过 `moon check`，严禁私自篡改公开类型名、标签参数名或错误边界；阶段验收后必须回写 `docs/spec/requirements.md` 的状态与验证证据。
2. **ADR 约束**：修改已接受（`Accepted`）的架构决策时，必须先在 `docs/decisions/` 新建递增编号的 ADR，严禁直接篡改历史 ADR 或口头偏离规格。
3. **语义检索优先**：优先使用 `moon ide doc`、`moon ide outline`、`moon ide peek-def` 探索标准库与 `moonbitlang/core/async` 符号定义，严禁凭旧版记忆猜测 API 签名。
4. **测试驱动与零警告门禁**：按 `docs/spec/roadmap-and-acceptance.md` 从 Phase 0 至 Phase 5 串行推进；上一阶段未通过 `moon test` 与 `moon check --deny-warn` 前，严禁跨阶段编码。
