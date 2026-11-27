///|
const SYNC_START : String = "\u{001b}[?2026h"

///|
const SYNC_END : String = "\u{001b}[?2026l"

///|
pub fn InlineDiffRenderer::InlineDiffRenderer() -> InlineDiffRenderer {
  { prev_physical_rows: 0, prev_lines: [], prev_cols: 0, has_rendered: false, }
}

///|
fn total_physical_rows(lines : Array[String], cols : Int32) -> Int32 {
  if lines.is_empty() {
    return 1
  }
  let mut sum : Int32 = 0
  for line in lines {
    sum += @ansi.wrapped_line_count(line, cols)
  }
  if sum < 1 {
    1
  } else {
    sum
  }
}

///|
fn write_erase_previous(
  buf : StringBuilder,
  has_rendered : Bool,
  prev_physical_rows : Int32,
) -> Unit {
  if !has_rendered {
    return
  }
  if prev_physical_rows > 1 {
    let up = prev_physical_rows - 1
    buf.write_string("\u{001b}[\{up}A")
  }
  buf.write_string("\r\u{001b}[J")
}

///|
pub fn InlineDiffRenderer::patch(
  self : InlineDiffRenderer,
  lines : Array[String],
  cols : Int32,
  sync_output~ : Bool,
) -> String {
  let effective_cols : Int32 = if cols < 1 { 1 } else { cols }
  // Frame-equality short-circuit eliminates redundant writes and flicker
  if self.has_rendered &&
    self.prev_cols == effective_cols &&
    self.prev_lines == lines {
    return ""
  }
  let buf = StringBuilder()
  if sync_output {
    buf.write_string(SYNC_START)
  }
  write_erase_previous(buf, self.has_rendered, self.prev_physical_rows)
  for i in 0..<lines.length() {
    if i > 0 {
      buf.write_string("\r\n")
    }
    buf.write_string(lines[i])
  }
  if sync_output {
    buf.write_string(SYNC_END)
  }
  self.prev_physical_rows = total_physical_rows(lines, effective_cols)
  self.prev_lines = lines.copy()
  self.prev_cols = effective_cols
  self.has_rendered = true
  buf.to_string()
}

///|
pub fn InlineDiffRenderer::commit(
  self : InlineDiffRenderer,
  final_lines : Array[String],
  cols : Int32,
  sync_output~ : Bool,
) -> String {
  let _ = cols
  let buf = StringBuilder()
  if sync_output {
    buf.write_string(SYNC_START)
  }
  write_erase_previous(buf, self.has_rendered, self.prev_physical_rows)
  for i in 0..<final_lines.length() {
    if i > 0 {
      buf.write_string("\r\n")
    }
    buf.write_string(final_lines[i])
  }
  buf.write_string("\r\n")
  if sync_output {
    buf.write_string(SYNC_END)
  }
  self.reset()
  buf.to_string()
}

///|
pub fn InlineDiffRenderer::on_resize(self : InlineDiffRenderer) -> String {
  if !self.has_rendered {
    return ""
  }
  self.reset()
  "\r\u{001b}[2K"
}

///|
pub fn InlineDiffRenderer::reset(self : InlineDiffRenderer) -> Unit {
  self.prev_physical_rows = 0
  self.prev_lines = []
  self.prev_cols = 0
  self.has_rendered = false
}
