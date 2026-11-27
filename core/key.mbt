///|
const MAX_PASTE_BYTES : Int32 = 1048576

///|
let paste_start_seq : FixedArray[Byte] = [b'\x1b', b'[', b'2', b'0', b'0', b'~']

///|
let paste_end_seq : FixedArray[Byte] = [b'\x1b', b'[', b'2', b'0', b'1', b'~']

///|
pub fn KeyDecoder::KeyDecoder() -> KeyDecoder {
  {
    in_paste: false,
    paste_buf: StringBuilder(),
    paste_bytes: 0,
    pending_bytes: [],
    swallow_lf: false,
  }
}

///|
fn plain_key(code : KeyCode) -> KeyEvent {
  { code, ctrl: false, alt: false, shift: false, }
}

///|
fn match_seq_prefix(
  buf : Array[Byte],
  idx : Int32,
  seq : FixedArray[Byte],
) -> Int32 {
  // Returns: 1 = full match, 0 = partial prefix at end of buf, -1 = mismatch
  let rem = buf.length() - idx
  let slen = seq.length()
  let check_len = if rem < slen { rem } else { slen }
  for i in 0..<check_len {
    if buf[idx + i] != seq[i] {
      return -1
    }
  }
  if rem >= slen {
    1
  } else {
    0
  }
}

///|
/// Decode a single UTF-8 scalar from `buf` starting at `idx`.
/// Returns: (Some(ch), next_idx) on success;
///          (None, -1) if truncated at end of buffer (wait for more bytes);
///          (None, idx + 1) on invalid byte (skip).
fn decode_utf8_at(buf : Array[Byte], idx : Int32) -> (Char?, Int32) {
  let len = buf.length()
  if idx >= len {
    return (None, -1)
  }
  let b0 = buf[idx].to_int()
  if b0 < 0x80 {
    return (b0.to_char(), idx + 1)
  }
  let (expected, cp0, min_cp) : (Int32, Int32, Int32) = if (b0 & 0xE0) == 0xC0 {
    (2, b0 & 0x1F, 0x80)
  } else if (b0 & 0xF0) == 0xE0 {
    (3, b0 & 0x0F, 0x800)
  } else if (b0 & 0xF8) == 0xF0 {
    (4, b0 & 0x07, 0x10000)
  } else {
    return (None, idx + 1)
  }
  let avail = len - idx
  let check_len = if avail < expected { avail } else { expected }
  let mut cp = cp0
  for i in 1..<check_len {
    let bx = buf[idx + i].to_int()
    if (bx & 0xC0) != 0x80 {
      return (None, idx + 1)
    }
    cp = (cp << 6) | (bx & 0x3F)
  }
  if avail < expected {
    return (None, -1)
  }
  if cp < min_cp || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF) {
    return (None, idx + 1)
  }
  (cp.to_char(), idx + expected)
}

///|
fn decode_csi_sequence(
  buf : Array[Byte],
  start : Int32,
  end : Int32,
) -> KeyEvent? {
  // buf[start] == 0x1b, buf[start+1] == '[', buf[end-1] is final byte
  let final_b = buf[end - 1].to_int()
  let param_buf = StringBuilder()
  for i in (start + 2)..<(end - 1) {
    match buf[i].to_int().to_char() {
      Some(c) => param_buf.write_char(c)
      None => ()
    }
  }
  let params = param_buf.to_string()
  let mut shift = false
  let mut alt = false
  let mut ctrl = false
  // Parse optional xterm modifier `;M` (e.g. `1;2A`, `1;5C`)
  let parts = params.split(";").collect()
  let first_param = if parts.length() > 0 { parts[0].to_owned() } else { "" }
  if parts.length() >= 2 {
    let mod_str = parts[1].to_owned()
    let mod_val : Int32 = match mod_str {
      "2" => 2
      "3" => 3
      "4" => 4
      "5" => 5
      "6" => 6
      "7" => 7
      "8" => 8
      _ => 1
    }
    let bits = mod_val - 1
    if (bits & 1) != 0 {
      shift = true
    }
    if (bits & 2) != 0 {
      alt = true
    }
    if (bits & 4) != 0 {
      ctrl = true
    }
  }
  match final_b {
    0x41 => Some({ code: Up, ctrl, alt, shift, }) // A
    0x42 => Some({ code: Down, ctrl, alt, shift, }) // B
    0x43 => Some({ code: Right, ctrl, alt, shift, }) // C
    0x44 => Some({ code: Left, ctrl, alt, shift, }) // D
    0x48 => Some({ code: Home, ctrl, alt, shift, }) // H
    0x46 => Some({ code: End, ctrl, alt, shift, }) // F
    0x5A => Some({ code: BackTab, ctrl, alt, shift: true, }) // Z
    0x7E =>
      match first_param {
        "1" | "7" => Some({ code: Home, ctrl, alt, shift, })
        "3" => Some({ code: Delete, ctrl, alt, shift, })
        "4" | "8" => Some({ code: End, ctrl, alt, shift, })
        "5" => Some({ code: PageUp, ctrl, alt, shift, })
        "6" => Some({ code: PageDown, ctrl, alt, shift, })
        _ => None
      }
    _ => None
  }
}

///|
fn compact_pending(pending : Array[Byte], consumed : Int32) -> Unit {
  if consumed <= 0 {
    return
  }
  let len = pending.length()
  if consumed >= len {
    pending.clear()
    return
  }
  let rest : Array[Byte] = []
  for i in consumed..<len {
    rest.push(pending[i])
  }
  pending.clear()
  for b in rest {
    pending.push(b)
  }
}

///|
pub fn KeyDecoder::feed(
  self : KeyDecoder,
  chunk : BytesView,
) -> Array[KeyEvent] {
  for i in 0..<chunk.length() {
    self.pending_bytes.push(chunk[i])
  }
  let events : Array[KeyEvent] = []
  let len = self.pending_bytes.length()
  let mut idx : Int32 = 0
  while idx < len {
    if self.in_paste {
      let b = self.pending_bytes[idx]
      if b == b'\x03' {
        // Safety escape: abort unclosed paste on Ctrl+C so keyboard never deadlocks
        self.in_paste = false
        self.paste_buf.reset()
        self.paste_bytes = 0
        events.push({ code: Char('c'), ctrl: true, alt: false, shift: false, })
        idx += 1
        continue
      }
      if b == b'\x1b' {
        let m = match_seq_prefix(self.pending_bytes, idx, paste_end_seq)
        if m == 1 {
          let payload = self.paste_buf.to_string()
          self.in_paste = false
          self.paste_buf.reset()
          self.paste_bytes = 0
          events.push(plain_key(Paste(payload)))
          idx += paste_end_seq.length()
          continue
        }
        if m == 0 {
          break
        }
      }
      let (ch_opt, next_idx) = decode_utf8_at(self.pending_bytes, idx)
      if next_idx < 0 {
        break
      }
      let byte_count = next_idx - idx
      match ch_opt {
        Some(ch) => self.paste_buf.write_char(ch)
        None => ()
      }
      self.paste_bytes += byte_count
      idx = next_idx
      if self.paste_bytes >= MAX_PASTE_BYTES {
        let payload = self.paste_buf.to_string()
        self.in_paste = false
        self.paste_buf.reset()
        self.paste_bytes = 0
        events.push(plain_key(Paste(payload)))
      }
      continue
    }

    let b = self.pending_bytes[idx]
    if self.swallow_lf {
      self.swallow_lf = false
      if b == b'\n' {
        idx += 1
        continue
      }
    }

    if b == b'\x03' {
      events.push({ code: Char('c'), ctrl: true, alt: false, shift: false, })
      idx += 1
      continue
    }
    if b == b'\x04' {
      events.push({ code: Char('d'), ctrl: true, alt: false, shift: false, })
      idx += 1
      continue
    }
    if b == b'\x01' {
      events.push({ code: Home, ctrl: true, alt: false, shift: false, })
      idx += 1
      continue
    }
    if b == b'\x05' {
      events.push({ code: End, ctrl: true, alt: false, shift: false, })
      idx += 1
      continue
    }
    if b == b'\r' {
      events.push(plain_key(Enter))
      self.swallow_lf = true
      idx += 1
      continue
    }
    if b == b'\n' {
      events.push(plain_key(Enter))
      idx += 1
      continue
    }
    if b == b'\t' {
      events.push(plain_key(Tab))
      idx += 1
      continue
    }
    if b == b'\x7f' || b == b'\x08' {
      events.push(plain_key(Backspace))
      idx += 1
      continue
    }
    if b == b' ' {
      events.push(plain_key(Space))
      idx += 1
      continue
    }

    if b == b'\x1b' {
      let rem = len - idx
      if rem == 1 {
        // Hold bare ESC for 20ms disambiguation via flush_escape()
        break
      }
      let b1 = self.pending_bytes[idx + 1]
      if b1 == b'[' {
        let pm = match_seq_prefix(self.pending_bytes, idx, paste_start_seq)
        if pm == 1 {
          self.in_paste = true
          self.paste_buf.reset()
          self.paste_bytes = 0
          idx += paste_start_seq.length()
          continue
        }
        if pm == 0 {
          break
        }
        // Scan CSI until final byte 0x40..0x7E
        let mut scan = idx + 2
        let mut found_end : Int32 = -1
        while scan < len {
          let sb = self.pending_bytes[scan].to_int()
          if sb >= 0x40 && sb <= 0x7E {
            found_end = scan + 1
            break
          }
          if scan - idx > 32 {
            found_end = scan + 1
            break
          }
          scan += 1
        }
        if found_end < 0 {
          // Incomplete CSI sequence; wait for next chunk
          break
        }
        match decode_csi_sequence(self.pending_bytes, idx, found_end) {
          Some(ev) => events.push(ev)
          None => ()
        }
        idx = found_end
        continue
      }
      if b1 == b'O' {
        if rem < 3 {
          break
        }
        let b2 = self.pending_bytes[idx + 2]
        let ev_opt : KeyEvent? = match b2 {
          b'A' => Some(plain_key(Up))
          b'B' => Some(plain_key(Down))
          b'C' => Some(plain_key(Right))
          b'D' => Some(plain_key(Left))
          b'H' => Some(plain_key(Home))
          b'F' => Some(plain_key(End))
          _ => None
        }
        match ev_opt {
          Some(ev) => events.push(ev)
          None => ()
        }
        idx += 3
        continue
      }
      if b1 == b'\x1b' {
        events.push(plain_key(Escape))
        idx += 1
        continue
      }
      // Alt + UTF-8 char
      let (ch_opt, next_idx) = decode_utf8_at(self.pending_bytes, idx + 1)
      if next_idx < 0 {
        break
      }
      match ch_opt {
        Some(ch) =>
          events.push({ code: Char(ch), ctrl: false, alt: true, shift: false, })
        None => ()
      }
      idx = next_idx
      continue
    }

    // Other C0 control bytes (e.g. Ctrl+U, Ctrl+W, etc.) -> emit ctrl char or skip
    let bi = b.to_int()
    if bi < 0x20 {
      let letter_cp = bi + 0x60 // 0x01 -> 'a', ..., 0x1A -> 'z'
      match letter_cp.to_char() {
        Some(ch) =>
          if ch >= 'a' && ch <= 'z' {
            events.push({
              code: Char(ch),
              ctrl: true,
              alt: false,
              shift: false,
            })
          }
        None => ()
      }
      idx += 1
      continue
    }

    // Regular UTF-8 scalar
    let (ch_opt, next_idx) = decode_utf8_at(self.pending_bytes, idx)
    if next_idx < 0 {
      break
    }
    match ch_opt {
      Some(ch) => events.push(plain_key(Char(ch)))
      None => ()
    }
    idx = next_idx
  }

  compact_pending(self.pending_bytes, idx)
  events
}

///|
pub fn KeyDecoder::has_pending_escape(self : KeyDecoder) -> Bool {
  !self.in_paste &&
  self.pending_bytes.length() == 1 &&
  self.pending_bytes[0] == b'\x1b'
}

///|
pub fn KeyDecoder::flush_escape(self : KeyDecoder) -> KeyEvent? {
  if self.has_pending_escape() {
    self.pending_bytes.clear()
    Some(plain_key(Escape))
  } else {
    None
  }
}
