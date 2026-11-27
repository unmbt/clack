///|
/// Deterministic in-memory virtual terminal for unit and integration testing.
pub struct VirtualTerminal {
  priv scripted_keys : Array[Bytes]
  priv mut cursor : Int32
  priv output_frames : Array[String]
  priv mut cols : Int32
  priv mut rows : Int32
  priv mut tty : Bool
  priv env : Map[String, String]
  priv mut in_raw_mode : Bool
}

///|
pub fn VirtualTerminal::VirtualTerminal(
  scripted_keys : Array[Bytes],
  cols~ : Int32 = 80,
  rows~ : Int32 = 24,
  tty~ : Bool = true,
  env~ : Map[String, String] = {},
) -> VirtualTerminal {
  {
    scripted_keys,
    cursor: 0,
    output_frames: [],
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
pub fn VirtualTerminal::frames(self : VirtualTerminal) -> Array[String] {
  self.output_frames.copy()
}

///|
pub fn VirtualTerminal::all_output(self : VirtualTerminal) -> String {
  self.output_frames.join("")
}

///|
pub fn VirtualTerminal::in_raw_mode(self : VirtualTerminal) -> Bool {
  self.in_raw_mode
}

///|
pub fn VirtualTerminal::set_size(
  self : VirtualTerminal,
  cols : Int32,
  rows : Int32,
) -> Unit {
  self.cols = if cols > 0 { cols } else { 1 }
  self.rows = if rows > 0 { rows } else { 1 }
}

///|
pub fn VirtualTerminal::set_tty(self : VirtualTerminal, tty : Bool) -> Unit {
  self.tty = tty
}

///|
pub impl Terminal for VirtualTerminal with fn is_tty(self) {
  self.tty
}

///|
pub impl Terminal for VirtualTerminal with fn size(self) {
  (self.cols, self.rows)
}

///|
pub impl Terminal for VirtualTerminal with fn env_get(self, key) {
  self.env.get(key)
}

///|
pub impl Terminal for VirtualTerminal with fn enter_raw_mode(self) {
  self.in_raw_mode = true
}

///|
pub impl Terminal for VirtualTerminal with fn leave_raw_mode(self) {
  self.in_raw_mode = false
}

///|
pub impl Terminal for VirtualTerminal with fn read_bytes(self) {
  if self.cursor < self.scripted_keys.length() {
    let chunk = self.scripted_keys[self.cursor]
    self.cursor += 1
    Some(chunk)
  } else {
    None
  }
}

///|
pub impl Terminal for VirtualTerminal with fn write_str(self, data) {
  self.output_frames.push(data.to_owned())
}

///|
pub impl Terminal for VirtualTerminal with fn write_final(self, data) {
  self.output_frames.push(data.to_owned())
}

///|
pub extend VirtualTerminal with Terminal::{
  is_tty,
  size,
  env_get,
  enter_raw_mode,
  leave_raw_mode,
  read_bytes,
  write_str,
  write_final,
}
