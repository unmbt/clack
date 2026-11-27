///|
extern "js" fn js_is_tty() -> Bool =
  #| () => typeof process !== "undefined" && !!(process.stdin && process.stdin.isTTY && process.stdout && process.stdout.isTTY)

///|
extern "js" fn js_cols() -> Int32 =
  #| () => (typeof process !== "undefined" && process.stdout && typeof process.stdout.columns === "number" && process.stdout.columns > 0) ? (process.stdout.columns | 0) : 80

///|
extern "js" fn js_rows() -> Int32 =
  #| () => (typeof process !== "undefined" && process.stdout && typeof process.stdout.rows === "number" && process.stdout.rows > 0) ? (process.stdout.rows | 0) : 24

///|
extern "js" fn js_write_stdout(data : String) -> Unit =
  #| (data) => { if (typeof process !== "undefined" && process.stdout && typeof process.stdout.write === "function") { process.stdout.write(data); } }

///|
extern "js" fn js_attach_stdin(
  on_data : (Bytes) -> Unit,
  on_end : () -> Unit,
) -> Int32 =
  #| (on_data, on_end) => {
  #|   if (typeof process === "undefined" || !process.stdin) return -1;
  #|   const stdin = process.stdin;
  #|   if (typeof stdin.setRawMode === "function") {
  #|     try { stdin.setRawMode(true); } catch (_) {}
  #|   }
  #|   const dataHandler = (chunk) => {
  #|     let bytes;
  #|     if (typeof chunk === "string") {
  #|       bytes = new TextEncoder().encode(chunk);
  #|     } else if (chunk instanceof Uint8Array) {
  #|       bytes = new Uint8Array(chunk.buffer, chunk.byteOffset, chunk.byteLength);
  #|     } else {
  #|       bytes = new Uint8Array(0);
  #|     }
  #|     on_data(bytes);
  #|   };
  #|   const endHandler = () => on_end();
  #|   globalThis.__clack_stdin_data = dataHandler;
  #|   globalThis.__clack_stdin_end = endHandler;
  #|   stdin.on("data", dataHandler);
  #|   stdin.on("end", endHandler);
  #|   stdin.resume();
  #|   return 0;
  #| }

///|
extern "js" fn js_detach_stdin() -> Unit =
  #| () => {
  #|   if (typeof process === "undefined" || !process.stdin) return;
  #|   const stdin = process.stdin;
  #|   if (globalThis.__clack_stdin_data) {
  #|     stdin.removeListener("data", globalThis.__clack_stdin_data);
  #|     globalThis.__clack_stdin_data = undefined;
  #|   }
  #|   if (globalThis.__clack_stdin_end) {
  #|     stdin.removeListener("end", globalThis.__clack_stdin_end);
  #|     globalThis.__clack_stdin_end = undefined;
  #|   }
  #|   if (typeof stdin.setRawMode === "function") {
  #|     try { stdin.setRawMode(false); } catch (_) {}
  #|   }
  #|   if (typeof stdin.pause === "function") {
  #|     stdin.pause();
  #|   }
  #| }

///|
/// JS runtime terminal (Node.js / Deno / Bun CLI; gracefully reports non-TTY in browsers).
pub struct JsTerminal {
  priv input_queue : @aqueue.Queue[Bytes?]
  priv mut raw_active : Bool
}

///|
pub fn JsTerminal::JsTerminal() -> JsTerminal {
  { input_queue: @aqueue.Queue(kind=Unbounded), raw_active: false, }
}

///|
pub impl Terminal for JsTerminal with fn is_tty(_self) {
  js_is_tty()
}

///|
pub impl Terminal for JsTerminal with fn size(_self) {
  (js_cols(), js_rows())
}

///|
pub impl Terminal for JsTerminal with fn env_get(_self, key) {
  @env.get_env_var(key)
}

///|
pub impl Terminal for JsTerminal with fn enter_raw_mode(self) {
  if self.raw_active {
    return
  }
  let q = self.input_queue
  let rc = js_attach_stdin(
    fn(bytes) { ignore(q.try_put(Some(bytes))) catch { _ => () } },
    fn() { ignore(q.try_put(None)) catch { _ => () } },
  )
  if rc != 0 {
    raise NotInteractive("No interactive JS stdin available")
  }
  self.raw_active = true
}

///|
pub impl Terminal for JsTerminal with fn leave_raw_mode(self) {
  if self.raw_active {
    js_detach_stdin()
    self.raw_active = false
  }
}

///|
pub impl Terminal for JsTerminal with fn read_bytes(self) {
  self.input_queue.get() catch {
    _ => None
  }
}

///|
pub impl Terminal for JsTerminal with fn write_str(_self, data) {
  js_write_stdout(data.to_owned())
}

///|
pub impl Terminal for JsTerminal with fn write_final(_self, data) {
  js_write_stdout(data.to_owned())
}

///|
pub fn default_terminal() -> &Terminal {
  JsTerminal()
}
