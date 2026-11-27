# unmbt/clack

Zero-dependency streaming CLI prompts, multi-step wizard flows with `StepBack`, spinners, progress bars, and SGR styling for MoonBit (`v1.0.0-rc1+`) — featuring 1:1 `@clack/prompts` v1.9.0 visual & interactive parity, an optional `MinimalTheme`, Bracketed Paste protection, and multi-target support (`native`, `js`, `wasm`, plus `wasm-gc` for pure `ansi` & `core`).

## Features

- **1:1 `@clack/prompts` v1.9.0 Parity**: Guide rails (`┌ / │ / ◆ / ◇ / └`), ASCII fallback, `ACCESSIBLE` mode, `text`, `password`, `multiline`, `confirm`, `select`, `select_key`, `multiselect`, `group_multiselect`, `autocomplete`, `autocomplete_multiselect`, `date`, `path` / `path_with`, `Spinner` (`dots`/`timer`, `clear`, `on_cancel`, `style_frame`), `Progress` (`light`/`heavy`/`block`, `message`/`cancel`/`clear`), `tasks`, `TaskLog` (`strip_destructive_ansi`, `limit`, `retain_log`, `group`), `StreamLog` / `stream_*`, `box`, `note` (with `format` & width wrapping), `intro`, `outro`, `cancel`, `log_*` (`log_warning`, `spacing`, `secondary_symbol`), and async `validate_async` (`Validating...` phase).
- **Dual Themes**: Switch seamlessly between `ClackTheme` (guide-rail timeline) and `MinimalTheme` (compact single-line prompts).
- **Step-Back Wizard (`@clack.run_wizard`)**: Press `Shift+Tab` or `Esc` to return to the previous actually executed step (automatically jumping over skipped `when` steps) with prior input preserved.
- **Zero External Dependencies**: Built solely on `moonbitlang/core` + `moonbitlang/core/async`.
- **Cross-Platform & Browser `xterm.js` Ready**: Native Win32 (`WriteConsoleW` + QuickEdit preservation) / POSIX `termios`, Node/Deno/Bun JS, WASI Wasm, `CallbackTerminal` for browser `xterm.js`, and deterministic `VirtualTerminal` for CI tests.

## Quick Example (Tested)

```mbt check
///|
async test "README quick wizard example" {
  let vt = @clack.VirtualTerminal([b"demo-app", b"\r", b"\x1b[B", b"\r"])
  let session = @clack.Session(term=vt, color_level=None)
  @clack.intro("create-moon-app", session~)
  let name = @clack.text("Project name", placeholder="my-app", session~)
  let target = @clack.select(
    "Target backend",
    [
      @clack.SelectOption("native", "Native", hint="fast binary"),
      @clack.SelectOption("js", "JavaScript", hint="Node / browser"),
    ],
    session~,
  )
  @clack.outro("Done!", session~)
  debug_inspect(name, content="Submitted(\"demo-app\")")
  debug_inspect(target, content="Submitted(\"js\")")
  inspect(vt.in_raw_mode(), content="false")
}
```

## Run Interactive Demo

```bash
moon run --target native cmd/demo
```
