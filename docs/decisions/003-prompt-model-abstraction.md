# ADR-003：规避无关联类型限制的 `PromptAdapter[T]` 组件抽象

- 状态：Accepted
- 日期：2026-11-25
- 关联：`REQ-WIDGET-01`～`REQ-WIDGET-05`、`REQ-WEB-01`

## 背景

原 [architecture-and-contracts.md](../spec/architecture-and-contracts.md) 草案定义了如下无头组件统一契约：

```moonbit
pub(open) trait PromptModel {
  type Output
  fn on_key(Self, event : KeyEvent, allow_back~ : Bool) -> PromptOutcome[Self::Output]?
  fn view(Self) -> FrameSpec
}
```

但 MoonBit 当前语言特性（`moonc v0.10.22`）**不支持 trait 关联类型（associated types）**，`type Output` 与 `Self::Output` 无法通过 `moon check`。

## 决策

废除带关联类型的 `PromptModel` trait，改用以下两层等价且强类型的契约：

1. **具体模型保留强类型方法**：`TextModel`、`ConfirmModel`、`SelectModel[T]`、`MultiSelectModel[T]`、`GroupMultiSelectModel[T]`、`AutocompleteModel[T]` 各自直接实现具体方法：
   - `on_key(self, event : KeyEvent, allow_back~ : Bool) -> PromptOutcome[Output]?`
   - `view(self) -> FrameSpec`
   - `as_adapter(self) -> PromptAdapter[Output]`
2. **统一闭包适配器 `PromptAdapter[T]`**：
   ```moonbit
   pub struct PromptAdapter[T] {
     on_key : (KeyEvent, Bool) -> PromptOutcome[T]?
     view : () -> FrameSpec
   }
   ```
   由纯同步驱动 `core::InlineDriver[T]` 与异步驱动 `prompts::run_prompt_loop[T]`（及 `minimal`）共同消费 `PromptAdapter[T]`。

## 依据

- 完全避开 trait 关联类型限制，同时不需要在泛型函数中反复透传额外的哑类型参数或手写多层 trait wrapper。
- `PromptAdapter[T]` 是纯函数闭包记录，零堆分配开销叠加且可直接在 `core` 层同时服务同步推模式（Web Wasm Demo）与异步拉模式（CLI 终端循环）。

## 后果

- 外部用户若需自定义新题型组件，无需实现开放 trait，直接构造 `PromptAdapter::PromptAdapter(on_key=..., view=...)` 即可接入 `InlineDriver` 或终端循环。
- 所有引用 `PromptModel` 与 `Self::Output` 的文档与伪代码需同步切换为 `PromptAdapter[T]`。
