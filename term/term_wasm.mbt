///|
/// WASI / Wasm terminal using `@stdio.stdin`/`@stdio.stdout` with safe
/// non-interactive fallback when raw TTY control is unavailable.
pub struct WasmTerminal {}

///|
pub fn WasmTerminal::WasmTerminal() -> WasmTerminal {
  WasmTerminal::{ }
}

///|
pub impl Terminal for WasmTerminal with fn is_tty(_self) {
  false
}

///|
pub impl Terminal for WasmTerminal with fn size(_self) {
  (80, 24)
}

///|
pub impl Terminal for WasmTerminal with fn env_get(_self, key) {
  @env.get_env_var(key)
}

///|
pub impl Terminal for WasmTerminal with fn enter_raw_mode(_self) {
  ()
}

///|
pub impl Terminal for WasmTerminal with fn leave_raw_mode(_self) {
  ()
}

///|
pub impl Terminal for WasmTerminal with fn read_bytes(_self) {
  @stdio.stdin.read() catch {
    err => raise IoFailure("\{Repr(err)}")
  }
}

///|
pub impl Terminal for WasmTerminal with fn write_str(_self, data) {
  let encoded = @utf8.encode(data)
  if encoded.length() == 0 {
    return
  }
  @stdio.stdout.write(encoded) catch {
    err => raise IoFailure("\{Repr(err)}")
  }
}

///|
pub impl Terminal for WasmTerminal with fn write_final(_self, data) {
  let encoded = @utf8.encode(data)
  if encoded.length() == 0 {
    return
  }
  @async.protect_from_cancel(() => {
    @stdio.stdout.write(encoded) catch {
      _ => ()
    }
  })
}

///|
pub fn default_terminal() -> &Terminal {
  WasmTerminal()
}
