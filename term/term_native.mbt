///|
extern "C" fn clack_tty_is_tty_ffi() -> Int32 = "clack_tty_is_tty"

///|
extern "C" fn clack_tty_enter_raw_ffi() -> Int32 = "clack_tty_enter_raw"

///|
extern "C" fn clack_tty_leave_raw_ffi() -> Int32 = "clack_tty_leave_raw"

///|
extern "C" fn clack_tty_cols_ffi() -> Int32 = "clack_tty_cols"

///|
extern "C" fn clack_tty_rows_ffi() -> Int32 = "clack_tty_rows"

///|
#borrow(buf)
extern "C" fn clack_tty_write_utf8_ffi(buf : FixedArray[Byte], len : Int32) = "clack_tty_write_utf8"

///|
fn native_write_sync(data : StringView) -> Unit {
  let encoded = @utf8.encode(data)
  let len = encoded.length()
  if len == 0 {
    return
  }
  let buf : FixedArray[Byte] = FixedArray::make(len, b'\x00')
  for i in 0..<len {
    buf[i] = encoded[i]
  }
  clack_tty_write_utf8_ffi(buf, len)
}

///|
/// Native OS terminal (Win32 Console / POSIX termios + cancellable `@stdio.stdin`).
pub struct NativeTerminal {
  priv mut raw_active : Bool
}

///|
pub fn NativeTerminal::NativeTerminal() -> NativeTerminal {
  { raw_active: false, }
}

///|
pub impl Terminal for NativeTerminal with fn is_tty(_self) {
  clack_tty_is_tty_ffi() != 0
}

///|
pub impl Terminal for NativeTerminal with fn size(_self) {
  (clack_tty_cols_ffi(), clack_tty_rows_ffi())
}

///|
pub impl Terminal for NativeTerminal with fn env_get(_self, key) {
  @env.get_env_var(key)
}

///|
pub impl Terminal for NativeTerminal with fn enter_raw_mode(self) {
  if !self.raw_active {
    if clack_tty_enter_raw_ffi() != 0 {
      raise IoFailure("Failed to enter raw mode")
    }
    self.raw_active = true
  }
}

///|
pub impl Terminal for NativeTerminal with fn leave_raw_mode(self) {
  if self.raw_active {
    ignore(clack_tty_leave_raw_ffi())
    self.raw_active = false
  }
}

///|
pub impl Terminal for NativeTerminal with fn read_bytes(_self) {
  @stdio.stdin.read() catch {
    err => raise IoFailure("\{Repr(err)}")
  }
}

///|
pub impl Terminal for NativeTerminal with fn write_str(_self, data) {
  let encoded = @utf8.encode(data)
  if encoded.length() == 0 {
    return
  }
  @stdio.stdout.write(encoded) catch {
    err => raise IoFailure("\{Repr(err)}")
  }
}

///|
pub impl Terminal for NativeTerminal with fn write_final(_self, data) {
  // Synchronous C write guarantees cleanup completes even during task cancellation
  native_write_sync(data)
}

///|
pub fn default_terminal() -> &Terminal {
  NativeTerminal()
}
