///|
/// Skip an ANSI escape sequence (CSI, OSC, or 2-char ESC) starting at
/// `chars[index] == '\u{001b}'`, returning the next character index.
fn skip_ansi_escape(chars : Array[Char], index : Int32) -> Int32 {
  let len = chars.length()
  let mut i = index + 1
  if i >= len {
    return i
  }
  let next = chars[i]
  if next == '[' {
    // CSI sequence: ESC [ <params/intermediates> <final byte 0x40..0x7E>
    i += 1
    while i < len && !(chars[i] >= '@' && chars[i] <= '~') {
      i += 1
    }
    if i < len {
      i += 1
    }
    i
  } else if next == ']' {
    // OSC sequence: ESC ] ... (BEL 0x07 | ST ESC \)
    i += 1
    while i < len {
      if chars[i] == '\u{0007}' {
        i += 1
        break
      }
      if chars[i] == '\u{001b}' && i + 1 < len && chars[i + 1] == '\\' {
        i += 2
        break
      }
      i += 1
    }
    i
  } else if next == 'P' || next == '_' || next == '^' || next == 'X' {
    // DCS / APC / PM / SOS string terminated by ST (ESC \)
    i += 1
    while i < len {
      if chars[i] == '\u{001b}' && i + 1 < len && chars[i + 1] == '\\' {
        i += 2
        break
      }
      i += 1
    }
    i
  } else {
    // 2-byte ESC sequence (e.g. ESC M, ESC 7, ESC 8)
    i + 1
  }
}

///|
/// Strip all CSI / OSC / ESC ANSI sequences and return visible text.
pub fn strip_ansi(input : StringView) -> String {
  let chars = input.to_owned().to_array()
  let len = chars.length()
  let buf = StringBuilder()
  let mut i : Int32 = 0
  while i < len {
    if chars[i] == '\u{001b}' {
      i = skip_ansi_escape(chars, i)
    } else {
      buf.write_char(chars[i])
      i += 1
    }
  }
  buf.to_string()
}

///|
fn is_destructive_csi_final(ch : Char) -> Bool {
  ch == 'A' ||
  ch == 'B' ||
  ch == 'C' ||
  ch == 'D' ||
  ch == 'E' ||
  ch == 'F' ||
  ch == 'G' ||
  ch == 'H' ||
  ch == 'f' ||
  ch == 'J' ||
  ch == 'K' ||
  ch == 'S' ||
  ch == 'T' ||
  ch == 's' ||
  ch == 'u'
}

///|
/// Strip destructive CSI sequences (cursor move, erase, scroll, save/restore)
/// matching upstream Clack `/\x1b\[(?:\d+;)*\d*[ABCDEFGHfJKSTsu]|\x1b\[(s|u)/g`,
/// while keeping SGR color/style sequences intact.
pub fn strip_destructive_ansi(input : StringView) -> String {
  let chars = input.to_owned().to_array()
  let len = chars.length()
  let buf = StringBuilder()
  let mut i : Int32 = 0
  while i < len {
    if chars[i] == '\u{001b}' && i + 1 < len && chars[i + 1] == '[' {
      let mut j = i + 2
      let mut all_digits_or_semi = true
      while j < len && !(chars[j] >= '@' && chars[j] <= '~') {
        let c = chars[j]
        if !((c >= '0' && c <= '9') || c == ';') {
          all_digits_or_semi = false
        }
        j += 1
      }
      if j < len && all_digits_or_semi && is_destructive_csi_final(chars[j]) {
        i = j + 1
        continue
      }
    }
    buf.write_char(chars[i])
    i += 1
  }
  buf.to_string()
}
