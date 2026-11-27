# unmbt/clack 文档与规范

> 状态：v0.1（Phase 0～5）全量交付完成，全部 `REQ-*` 已实现并通过 `native` / `js` / `wasm`（及纯核 `ansi`/`core` `wasm-gc`）零警告与全量测试门禁。
>
> 本目录是 `unmbt/clack` 的规格、设计决策与交付契约。实现尚未开始前，需求 ID、`declare` 契约与设计不变量优先于代码；每个阶段推进后必须回写需求状态与验证证据。

## 阅读顺序

1. [SDD 规约](sdd.md)：目标、追踪链路、需求 ID 规则、五步交付节奏与 v0.1 不可变原则。
2. [项目定位、生态辨析与需求规格矩阵](spec/requirements.md)：生态边界、Non-Goals、`REQ-*` 验收矩阵与状态追踪表。
3. [模块拓扑与 AI-Native `declare` 接口契约](spec/architecture-and-contracts.md)：子包 DAG 分层、`moon.mod` / `moon.pkg` 基线与全量强类型 `declare` 签名。
4. [核心算法、双主题渲染与跨平台终端机制](spec/algorithms-and-mechanisms.md)：视觉主题、`InlineDiffRenderer`、`KeyDecoder`、跨后端终端生命周期与浏览器 `xterm.js` 桥接。
5. [分阶段 SDD 执行路线与验收门禁](spec/roadmap-and-acceptance.md)：Phase 0～5 串行推进计划、TDD 必测用例与 `--deny-warn` 发布门禁。
6. [参考实现剖析与 MoonBit 版架构设计](references.md)：原版 `@clack` 源码级剖析、借鉴与扬弃矩阵、全景 DAG 与双驱动数据流总结。
7. [决策记录（ADR）](decisions/README.md)：关键架构选型（TTY 策略、标准库 `core/async` 与 Web Demo、`PromptAdapter`、终端生命周期防护）。

## SDD 工作规则

- **先有契约，后有代码**：所有公共 API 变更与新增组件必须先进入 `docs/spec/` 的 `declare` 契约和需求矩阵，再进入实现。
- **纯核跨四目标**：`ansi` 与 `core` 保持零 I/O、零异步纯函数，必须同时通过 `native`、`js`、`wasm`、`wasm-gc` 四目标编译与测试。
- **零第三方运行时依赖**：异步与控制流统一采用标准库 `moonbitlang/core/async`（对齐 `unmbt/moonset` [ADR-003](../../moonset/docs/decisions/003-core-async.md)），不引入外部 `moonbitlang/async` 或第三方终端 sidecar。
- **严格门禁**：提交或进入下一阶段前，必须通过 `moon fmt --check`、`moon info`、`moon check --deny-warn`（覆盖对应目标）与 `moon test`。
- **回写证据**：每个阶段验收通过后，必须在 [需求矩阵](spec/requirements.md#2-功能与非功能需求规格矩阵) 中将对应 `REQ-*` 状态更新为 `Implemented` 并记录测试文件或验证命令。

## 状态标记

| 标记 | 含义 |
| :--- | :--- |
| `Proposed` | 已提出，边界或签名尚待探针验证 |
| `Accepted` | 契约已冻结，可进入实现 |
| `Implemented` | 已实现并具备可复现的测试/命令验证证据 |
| `Deferred` | 明确延后至后续迭代 |
| `Rejected` | 不纳入产品范围（Non-Goal） |

## 当前已实证基线

- **工具链**：`moon 0.1.20261126`、`moonc v1.0.0-rc1`（核心整型规范化为 `Int32`，外部库导出使用 `pkgtype(kind: "foreign_library")` + `#export_name`，支持 `moon fix --warn-list +73` 自动清理冗余标注）。
- **异步与 I/O**：采用标准库 `moonbitlang/core/async`（`native` + `js` + `wasm` 支持调度/队列/定时器；`core/async/stdio` 支持 `native` + `wasm` 并内置 Windows 控制台编解码；`core/async/js_async` 支持 `js` `Promise`/`ReadableStream` 互操作；不支持 `wasm-gc`）。
- **目标后端矩阵**：
  - `ansi`、`core`：全四目标（`native`、`js`、`wasm`、`wasm-gc`）。
  - `term`、`prompts`、`minimal`、`flow`、根包 `unmbt/clack`、`cmd/demo`：`supported_targets = "-all+native+js+wasm"`。
- **浏览器 `xterm.js` Demo（参考 `moonset/doc-web`）**：
  - **主力路线（Full Async JS）**：将 `unmbt/clack`（含 `flow`、`prompts`、`Spinner`、`Progress`）编译为 `--target js`，通过 `term::CallbackTerminal` + `core/async/js_async` 直接驱动前端 `@xterm/xterm` 运行真实异步交互向导。
  - **轻量路线（Pure Sync Core）**：通过 `core::InlineDriver[T]` 编译至 `js` / `wasm` / `wasm-gc`，以零异步推模式驱动单步交互帧。
