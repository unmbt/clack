///|
fn char_is_combining(ch : Char) -> Bool {
  (ch >= '\u{0300}' && ch <= '\u{036f}') ||
  (ch >= '\u{0483}' && ch <= '\u{0489}') ||
  (ch >= '\u{0591}' && ch <= '\u{05bd}') ||
  ch == '\u{05bf}' ||
  (ch >= '\u{05c1}' && ch <= '\u{05c2}') ||
  (ch >= '\u{0610}' && ch <= '\u{061a}') ||
  (ch >= '\u{064b}' && ch <= '\u{065f}') ||
  (ch >= '\u{06d6}' && ch <= '\u{06ed}') ||
  (ch >= '\u{1ab0}' && ch <= '\u{1aff}') ||
  (ch >= '\u{1dc0}' && ch <= '\u{1dff}') ||
  (ch >= '\u{20d0}' && ch <= '\u{20ff}') ||
  (ch >= '\u{1f3fb}' && ch <= '\u{1f3ff}') ||
  (ch >= '\u{fe00}' && ch <= '\u{fe0f}') ||
  (ch >= '\u{fe20}' && ch <= '\u{fe2f}') ||
  ch == '\u{200d}'
}

///|
/// Unicode Emoji_Presentation symbols in U+2300..U+27BF (excludes narrow
/// symbols like `✓` U+2713, `✗` U+2717, arrows, and box-drawing glyphs).
fn char_is_emoji_presentation_bmp(ch : Char) -> Bool {
  (ch >= '\u{231a}' && ch <= '\u{231b}') ||
  (ch >= '\u{23e9}' && ch <= '\u{23ec}') ||
  ch == '\u{23f0}' ||
  ch == '\u{23f3}' ||
  (ch >= '\u{25fd}' && ch <= '\u{25fe}') ||
  (ch >= '\u{2614}' && ch <= '\u{2615}') ||
  (ch >= '\u{2648}' && ch <= '\u{2653}') ||
  ch == '\u{267f}' ||
  ch == '\u{2693}' ||
  ch == '\u{26a1}' ||
  (ch >= '\u{26aa}' && ch <= '\u{26ab}') ||
  (ch >= '\u{26bd}' && ch <= '\u{26be}') ||
  (ch >= '\u{26c4}' && ch <= '\u{26c5}') ||
  ch == '\u{26ce}' ||
  ch == '\u{26d4}' ||
  ch == '\u{26ea}' ||
  (ch >= '\u{26f2}' && ch <= '\u{26f3}') ||
  ch == '\u{26f5}' ||
  ch == '\u{26fa}' ||
  ch == '\u{26fd}' ||
  ch == '\u{2705}' ||
  (ch >= '\u{270a}' && ch <= '\u{270b}') ||
  ch == '\u{2728}' ||
  ch == '\u{274c}' ||
  ch == '\u{274e}' ||
  (ch >= '\u{2753}' && ch <= '\u{2755}') ||
  ch == '\u{2757}' ||
  (ch >= '\u{2795}' && ch <= '\u{2797}') ||
  ch == '\u{27b0}' ||
  ch == '\u{27bf}'
}

///|
fn char_is_wide(ch : Char) -> Bool {
  (ch >= '\u{1100}' && ch <= '\u{115f}') ||
  ch == '\u{2329}' ||
  ch == '\u{232a}' ||
  (ch >= '\u{2e80}' && ch <= '\u{a4cf}') ||
  (ch >= '\u{ac00}' && ch <= '\u{d7a3}') ||
  (ch >= '\u{f900}' && ch <= '\u{faff}') ||
  (ch >= '\u{fe10}' && ch <= '\u{fe19}') ||
  (ch >= '\u{fe30}' && ch <= '\u{fe6f}') ||
  (ch >= '\u{ff01}' && ch <= '\u{ff60}') ||
  (ch >= '\u{ffe0}' && ch <= '\u{ffe6}') ||
  char_is_emoji_presentation_bmp(ch) ||
  (ch >= '\u{1f000}' && ch <= '\u{1faff}') ||
  (ch >= '\u{20000}' && ch <= '\u{3fffd}')
}

///|
fn char_is_regional_indicator(ch : Char) -> Bool {
  ch >= '\u{1f1e6}' && ch <= '\u{1f1ff}'
}

///|
fn has_emoji_variation_selector(chars : Array[Char], index : Int32) -> Bool {
  index + 1 < chars.length() && chars[index + 1] == '\u{fe0f}'
}

///|
fn is_keycap_emoji(chars : Array[Char], index : Int32) -> Bool {
  let base = chars[index]
  let is_keycap_base = base == '#' ||
    base == '*' ||
    (base >= '0' && base <= '9')
  if !is_keycap_base {
    return false
  }
  let suffix = if has_emoji_variation_selector(chars, index) {
    index + 2
  } else {
    index + 1
  }
  suffix < chars.length() && chars[suffix] == '\u{20e3}'
}

///|
/// Compute terminal cell width of `chars[index]` and update grapheme state.
fn step_cell_width(
  chars : Array[Char],
  index : Int32,
  column : Int32,
  join_next : Bool,
  previous_was_regional : Bool,
) -> (Int32, Bool, Bool) {
  let ch = chars[index]
  if ch == '\t' {
    return (8 - column % 8, false, false)
  }
  if ch <= '\u{001f}' || (ch >= '\u{007f}' && ch <= '\u{009f}') {
    return (0, false, false)
  }
  if ch == '\u{200d}' {
    return (0, true, previous_was_regional)
  }
  if char_is_combining(ch) {
    return (0, join_next, previous_was_regional)
  }
  if char_is_regional_indicator(ch) {
    if previous_was_regional {
      return (0, false, false)
    }
    return (if join_next { 0 } else { 2 }, false, true)
  }
  let cell_width : Int32 = if join_next {
    0
  } else if char_is_wide(ch) ||
    is_keycap_emoji(chars, index) ||
    has_emoji_variation_selector(chars, index) {
    2
  } else {
    1
  }
  (cell_width, false, false)
}

///|
/// Compute display width of a string in terminal cells, ignoring ANSI escape sequences.
pub fn display_width(input : StringView) -> Int32 {
  let chars = input.to_owned().to_array()
  let len = chars.length()
  let mut width : Int32 = 0
  let mut i : Int32 = 0
  let mut join_next = false
  let mut previous_was_regional = false
  while i < len {
    if chars[i] == '\u{001b}' {
      i = skip_ansi_escape(chars, i)
      previous_was_regional = false
      continue
    }
    let (cell, next_join, next_regional) = step_cell_width(
      chars, i, width, join_next, previous_was_regional,
    )
    width += cell
    join_next = next_join
    previous_was_regional = next_regional
    i += 1
  }
  width
}

///|
/// Compute physical terminal rows occupied by a single line under terminal width `cols`
/// (respecting VT100 delayed-wrap: width == cols occupies exactly 1 row).
pub fn wrapped_line_count(line : StringView, cols : Int32) -> Int32 {
  let effective_cols : Int32 = if cols < 1 { 1 } else { cols }
  let w = display_width(line)
  if w <= effective_cols {
    1
  } else {
    (w + effective_cols - 1) / effective_cols
  }
}

///|
fn is_sgr_sequence(chars : Array[Char], start : Int32, end : Int32) -> Bool {
  end - start >= 3 &&
  chars[start] == '\u{001b}' &&
  chars[start + 1] == '[' &&
  chars[end - 1] == 'm'
}

///|
fn slice_to_string(chars : Array[Char], start : Int32, end : Int32) -> String {
  let buf = StringBuilder()
  for i in start..<end {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
fn update_active_sgr(active : Array[String], seq : String) -> Unit {
  if seq == "\u{001b}[0m" || seq == "\u{001b}[m" {
    active.clear()
  } else {
    active.push(seq)
  }
}

///|
fn wrap_single_line_hard(line : String, max_cols : Int32) -> Array[String] {
  let limit : Int32 = if max_cols < 1 { 1 } else { max_cols }
  if line == "" || display_width(line) <= limit {
    return [line]
  }
  let chars = line.to_array()
  let len = chars.length()
  let out : Array[String] = []
  let active_sgr : Array[String] = []
  let buf = StringBuilder()
  let mut col : Int32 = 0
  let mut i : Int32 = 0
  let mut join_next = false
  let mut prev_reg = false
  while i < len {
    if chars[i] == '\u{001b}' {
      let next_i = skip_ansi_escape(chars, i)
      let seq = slice_to_string(chars, i, next_i)
      buf.write_string(seq)
      if is_sgr_sequence(chars, i, next_i) {
        update_active_sgr(active_sgr, seq)
      }
      i = next_i
      prev_reg = false
      continue
    }
    let (cw, nj, pr) = step_cell_width(chars, i, col, join_next, prev_reg)
    if cw > 0 && col > 0 && col + cw > limit {
      if !active_sgr.is_empty() {
        buf.write_string("\u{001b}[0m")
      }
      out.push(buf.to_string())
      buf.reset()
      for seq in active_sgr {
        buf.write_string(seq)
      }
      col = 0
    }
    buf.write_char(chars[i])
    col += cw
    join_next = nj
    prev_reg = pr
    i += 1
  }
  out.push(buf.to_string())
  out
}

///|
/// Hard-wrap text (which may contain newlines and ANSI sequences) to `max_cols`.
pub fn wrap_ansi(text : StringView, max_cols : Int32) -> Array[String] {
  let limit : Int32 = if max_cols < 1 { 1 } else { max_cols }
  let raw = text.to_owned()
  let out : Array[String] = []
  for part in raw.split("\n") {
    let segs = wrap_single_line_hard(part.to_owned(), limit)
    for seg in segs {
      out.push(seg)
    }
  }
  if out.is_empty() {
    [""]
  } else {
    out
  }
}

///|
/// Wrap text to fit `cols` accounting for prefix widths, applying `first_prefix`
/// on the first line, `prefix` on middle lines, and `end_prefix` on the last line
/// (when there are multiple lines).
pub fn wrap_text_with_prefix(
  text : StringView,
  cols : Int32,
  prefix : StringView,
  first_prefix? : StringView,
  end_prefix? : StringView,
) -> Array[String] {
  let mid_p = prefix.to_owned()
  let first_p = match first_prefix {
    Some(fp) => fp.to_owned()
    None => mid_p
  }
  let end_p = match end_prefix {
    Some(ep) => ep.to_owned()
    None => mid_p
  }
  let p_width = {
    let w1 = display_width(first_p)
    let w2 = display_width(mid_p)
    let w3 = display_width(end_p)
    let m12 = if w1 > w2 { w1 } else { w2 }
    if m12 > w3 {
      m12
    } else {
      w3
    }
  }
  let avail = if cols - p_width > 1 { cols - p_width } else { 1 }
  let wrapped = wrap_ansi(text, avail)
  let total = wrapped.length()
  let out : Array[String] = []
  for i in 0..<total {
    let line_prefix = if i == 0 {
      first_p
    } else if i == total - 1 {
      end_p
    } else {
      mid_p
    }
    out.push(line_prefix + wrapped[i])
  }
  out
}
