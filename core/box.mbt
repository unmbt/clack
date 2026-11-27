///|
fn box_pad_for_line(
  line_len : Int32,
  inner_width : Int32,
  padding : Int32,
  align : BoxAlign,
) -> (Int32, Int32) {
  let mut left_pad = padding
  match align {
    Center => left_pad = (inner_width - line_len) / 2
    Right => left_pad = inner_width - line_len - padding
    Left => ()
  }
  if left_pad < 0 {
    left_pad = 0
  }
  let mut right_pad = inner_width - left_pad - line_len
  if right_pad < 0 {
    right_pad = 0
  }
  (left_pad, right_pad)
}

///|
fn truncate_box_title(title : String, max_len : Int32) -> String {
  if max_len <= 0 {
    return ""
  }
  if @ansi.display_width(title) <= max_len {
    return title
  }
  if max_len <= 3 {
    return repeat_str(".", max_len)
  }
  let target = max_len - 3
  let chars = title.to_array()
  let buf = StringBuilder()
  let mut w : Int32 = 0
  for ch in chars {
    let cw = @ansi.display_width(ch.to_string())
    if w + cw > target {
      break
    }
    buf.write_char(ch)
    w += cw
  }
  buf.to_string() + "..."
}

///|
/// 1:1 port of upstream `@clack/prompts` `box()` layout renderer.
pub fn render_box(
  message : StringView,
  title~ : StringView = "",
  cols~ : Int32 = 80,
  styler~ : @ansi.Styler = Styler(),
  unicode~ : Bool = true,
  with_guide~ : Bool = true,
  content_align~ : BoxAlign = Left,
  title_align~ : BoxAlign = Left,
  width~ : BoxWidth = Auto,
  title_padding~ : Int32 = 1,
  content_padding~ : Int32 = 2,
  rounded~ : Bool = true,
  format_border? : (String) -> String,
) -> String {
  let effective_cols : Int32 = if cols > 4 { cols } else { 80 }
  let border_fn = match format_border {
    Some(f) => f
    None => fn(s) { s }
  }
  let s_bar = if unicode { "│" } else { "|" }
  let s_bar_h = if unicode { "─" } else { "-" }
  let (tl_raw, tr_raw, bl_raw, br_raw) = if rounded {
    if unicode {
      ("╭", "╮", "╰", "╯")
    } else {
      ("+", "+", "+", "+")
    }
  } else if unicode {
    ("┌", "┐", "└", "┘")
  } else {
    ("T", "T", "—", "—")
  }
  let tl = border_fn(tl_raw)
  let tr = border_fn(tr_raw)
  let bl = border_fn(bl_raw)
  let br = border_fn(br_raw)
  let h_sym = border_fn(s_bar_h)
  let v_sym = border_fn(s_bar)
  let line_prefix = if with_guide { styler.gray(s_bar) + " " } else { "" }
  let line_prefix_width = @ansi.display_width(line_prefix)
  let max_box_width = effective_cols - line_prefix_width
  let title_str = title.to_owned()
  let msg_str = message.to_owned()
  let title_w = @ansi.display_width(title_str)

  let ratio : Double = match width {
    Auto => 1.0
    Ratio(r) => if r > 1.0 { 1.0 } else if r < 0.1 { 0.1 } else { r }
  }
  let mut box_width : Int32 = (effective_cols.to_double() * ratio).to_int() -
    line_prefix_width
  if width is Auto {
    let mut longest = title_w + title_padding * 2
    for part in msg_str.split("\n") {
      let lw = @ansi.display_width(part) + content_padding * 2
      if lw > longest {
        longest = lw
      }
    }
    let desired = longest + 2
    if desired < box_width {
      box_width = desired
    }
  }
  if box_width < 4 {
    box_width = 4
  }
  if box_width % 2 != 0 {
    if box_width < max_box_width {
      box_width += 1
    } else {
      box_width -= 1
    }
  }
  let inner_width = if box_width - 2 > 2 { box_width - 2 } else { 2 }
  let max_title_len = inner_width - title_padding * 2
  let shown_title = truncate_box_title(title_str, max_title_len)
  let (t_left, t_right) = box_pad_for_line(
    @ansi.display_width(shown_title),
    inner_width,
    title_padding,
    title_align,
  )

  let content_avail = if inner_width - content_padding * 2 > 1 {
    inner_width - content_padding * 2
  } else {
    1
  }
  let wrapped_lines = @ansi.wrap_ansi(msg_str, content_avail)

  let out : Array[String] = []
  out.push(
    line_prefix +
    tl +
    repeat_str(h_sym, t_left) +
    shown_title +
    repeat_str(h_sym, t_right) +
    tr,
  )
  for ln in wrapped_lines {
    let (l_pad, r_pad) = box_pad_for_line(
      @ansi.display_width(ln),
      inner_width,
      content_padding,
      content_align,
    )
    out.push(
      line_prefix +
      v_sym +
      repeat_str(" ", l_pad) +
      ln +
      repeat_str(" ", r_pad) +
      v_sym,
    )
  }
  out.push(line_prefix + bl + repeat_str(h_sym, inner_width) + br)
  out.join("\n")
}
