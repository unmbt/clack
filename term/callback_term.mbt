///|
/// Async queue-backed callback terminal designed for browser `xterm.js` demos,
/// embedded host event loops, and async cancellation tests.
pub struct CallbackTerminal {
  priv input_queue : @aqueue.Queue[Bytes?]
  priv on_write : (StringView) -> Unit
  priv mut cols : Int32
  priv mut rows : Int32
  priv tty : Bool
  priv env : Map[String, String]
  priv mut in_raw_mode : Bool
}

///|
pub fn CallbackTerminal::CallbackTerminal(
  on_write~ : (StringView) -> Unit,
  cols~ : Int32 = 80,
  rows~ : Int32 = 24,
  tty~ : Bool = true,
  env~ : Map[String, String] = {},
) -> CallbackTerminal {
  {
    input_queue: @aqueue.Queue(kind=Unbounded),
    on_write,
    cols: if cols > 0 {
      cols
    } else {
      80
    },
    rows: if rows > 0 {
      rows
    } else {
      24
    },
    tty,
    env,
    in_raw_mode: false,
  }
}

///|
pub fn CallbackTerminal::push_input(
  self : CallbackTerminal,
  chunk : Bytes,
) -> Unit {
  ignore(self.input_queue.try_put(Some(chunk))) catch {
    _ => ()
  }
}

///|
pub fn CallbackTerminal::push_text(
  self : CallbackTerminal,
  data : StringView,
) -> Unit {
  self.push_input(@utf8.encode(data))
}

///|
pub fn CallbackTerminal::set_size(
  self : CallbackTerminal,
  cols : Int32,
  rows : Int32,
) -> Unit {
  self.cols = if cols > 0 { cols } else { 1 }
  self.rows = if rows > 0 { rows } else { 1 }
}

///|
pub fn CallbackTerminal::close(self : CallbackTerminal) -> Unit {
  ignore(self.input_queue.try_put(None)) catch {
    _ => ()
  }
}

///|
pub fn CallbackTerminal::in_raw_mode(self : CallbackTerminal) -> Bool {
  self.in_raw_mode
}

///|
pub impl Terminal for CallbackTerminal with fn is_tty(self) {
  self.tty
}

///|
pub impl Terminal for CallbackTerminal with fn size(self) {
  (self.cols, self.rows)
}

///|
pub impl Terminal for CallbackTerminal with fn env_get(self, key) {
  self.env.get(key)
}

///|
pub impl Terminal for CallbackTerminal with fn enter_raw_mode(self) {
  self.in_raw_mode = true
}

///|
pub impl Terminal for CallbackTerminal with fn leave_raw_mode(self) {
  self.in_raw_mode = false
}

///|
pub impl Terminal for CallbackTerminal with fn read_bytes(self) {
  self.input_queue.get() catch {
    _ => None
  }
}

///|
pub impl Terminal for CallbackTerminal with fn write_str(self, data) {
  (self.on_write)(data)
}

///|
pub impl Terminal for CallbackTerminal with fn write_final(self, data) {
  (self.on_write)(data)
}

///|
pub extend CallbackTerminal with Terminal::{
  is_tty,
  size,
  env_get,
  enter_raw_mode,
  leave_raw_mode,
  read_bytes,
  write_str,
  write_final,
}
