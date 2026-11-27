///|
fn trim_line_groups(
  groups : Array[Array[String]],
  initial_line_count : Int32,
  start_index : Int32,
  end_index : Int32,
  max_lines : Int32,
  from_end : Bool,
) -> (Int32, Int32) {
  let mut line_count = initial_line_count
  let mut removals : Int32 = 0
  if from_end {
    let mut i = end_index - 1
    while i >= start_index {
      line_count -= groups[i].length()
      removals += 1
      if line_count <= max_lines {
        break
      }
      i -= 1
    }
  } else {
    let mut i = start_index
    while i < end_index {
      line_count -= groups[i].length()
      removals += 1
      if line_count <= max_lines {
        break
      }
      i += 1
    }
  }
  (line_count, removals)
}

///|
/// 1:1 port of upstream `@clack/prompts` `limitOptions`:
/// Trims an already-styled option list to fit within `cols` and `rows` while
/// keeping `cursor` visible in a Clack-style sliding window and rendering
/// top/bottom overflow ellipses when needed.
pub fn limit_options(
  styled_items : Array[String],
  cursor : Int32,
  cols : Int32,
  rows : Int32,
  max_items? : Int32,
  column_padding~ : Int32 = 0,
  row_padding~ : Int32 = 4,
  ellipsis~ : String = "...",
) -> Array[String] {
  let total = styled_items.length()
  if total == 0 {
    return []
  }
  let safe_cursor : Int32 = if cursor < 0 {
    0
  } else if cursor >= total {
    total - 1
  } else {
    cursor
  }
  let max_width : Int32 = if cols - column_padding > 1 {
    cols - column_padding
  } else {
    1
  }
  let output_max_items : Int32 = if rows - row_padding > 0 {
    rows - row_padding
  } else {
    0
  }
  let user_max : Int32 = match max_items {
    Some(m) => if m > 0 { m } else { total }
    None => total
  }
  let min_cap : Int32 = if user_max < output_max_items {
    user_max
  } else {
    output_max_items
  }
  let computed_max_items : Int32 = if min_cap > 5 { min_cap } else { 5 }

  let mut window_start : Int32 = 0
  if safe_cursor >= computed_max_items - 3 {
    let raw_start = safe_cursor - computed_max_items + 3
    let max_start = total - computed_max_items
    let clamped = if raw_start < max_start { raw_start } else { max_start }
    window_start = if clamped > 0 { clamped } else { 0 }
  }

  let mut show_top = computed_max_items < total && window_start > 0
  let mut show_bottom = computed_max_items < total &&
    window_start + computed_max_items < total
  let window_end : Int32 = if window_start + computed_max_items < total {
    window_start + computed_max_items
  } else {
    total
  }

  let start_with_ellipsis = window_start + (if show_top { 1 } else { 0 })
  let end_with_ellipsis = window_end - (if show_bottom { 1 } else { 0 })

  let line_groups : Array[Array[String]] = []
  let mut line_count : Int32 = (if show_top { 1 } else { 0 }) +
    (if show_bottom { 1 } else { 0 })

  for i in start_with_ellipsis..<end_with_ellipsis {
    let wrapped = @ansi.wrap_ansi(styled_items[i], max_width)
    line_groups.push(wrapped)
    line_count += wrapped.length()
  }

  let mut trim_head : Int32 = 0
  let mut trim_tail : Int32 = 0
  if output_max_items > 0 && line_count > output_max_items {
    let mut new_line_count = line_count
    let cursor_group_idx = safe_cursor - start_with_ellipsis
    let mut adjusted_max = output_max_items
    let group_len = line_groups.length()
    let clamped_cur = if cursor_group_idx < 0 {
      0
    } else if cursor_group_idx >= group_len {
      group_len - 1
    } else {
      cursor_group_idx
    }

    if show_top {
      let (lc1, rem1) = trim_line_groups(
        line_groups, new_line_count, 0, clamped_cur, adjusted_max, false,
      )
      new_line_count = lc1
      trim_head = rem1
      if new_line_count > adjusted_max {
        if !show_bottom {
          adjusted_max -= 1
        }
        let (lc2, rem2) = trim_line_groups(
          line_groups,
          new_line_count,
          clamped_cur + 1,
          group_len,
          adjusted_max,
          true,
        )
        new_line_count = lc2
        trim_tail = rem2
      }
    } else {
      if !show_bottom {
        adjusted_max -= 1
      }
      let (lc1, rem1) = trim_line_groups(
        line_groups,
        new_line_count,
        clamped_cur + 1,
        group_len,
        adjusted_max,
        true,
      )
      new_line_count = lc1
      trim_tail = rem1
      if new_line_count > adjusted_max {
        adjusted_max -= 1
        let (lc2, rem2) = trim_line_groups(
          line_groups, new_line_count, 0, clamped_cur, adjusted_max, false,
        )
        new_line_count = lc2
        trim_head = rem2
      }
    }
    if trim_head > 0 {
      show_top = true
    }
    if trim_tail > 0 {
      show_bottom = true
    }
  }

  let result : Array[String] = []
  if show_top {
    result.push(ellipsis)
  }
  let keep_start = trim_head
  let keep_end = if line_groups.length() - trim_tail > keep_start {
    line_groups.length() - trim_tail
  } else {
    keep_start
  }
  for g in keep_start..<keep_end {
    for line in line_groups[g] {
      result.push(line)
    }
  }
  if show_bottom {
    result.push(ellipsis)
  }
  result
}

///|
/// Slice `lines` to fit within `max_rows` physical terminal rows (accounting
/// for ANSI-aware wrapping at `cols`) while keeping `cursor_line` centered in
/// the viewport whenever possible.
pub fn slice_viewport_lines(
  lines : Array[String],
  cursor_line : Int32,
  cols : Int32,
  max_rows : Int32,
) -> Array[String] {
  let total = lines.length()
  if total == 0 || max_rows <= 0 {
    return []
  }
  let effective_cols : Int32 = if cols > 0 { cols } else { 80 }
  let heights : Array[Int32] = []
  let mut total_rows : Int32 = 0
  for ln in lines {
    let h = @ansi.wrapped_line_count(ln, effective_cols)
    let clamped_h : Int32 = if h < 1 { 1 } else { h }
    heights.push(clamped_h)
    total_rows += clamped_h
  }
  if total_rows <= max_rows {
    return lines.copy()
  }
  let safe_cursor : Int32 = if cursor_line < 0 {
    0
  } else if cursor_line >= total {
    total - 1
  } else {
    cursor_line
  }
  let mut start = safe_cursor
  let mut end = safe_cursor + 1
  let mut used = heights[safe_cursor]
  let mut prefer_up = true
  while used < max_rows {
    let can_up = start > 0 && used + heights[start - 1] <= max_rows
    let can_down = end < total && used + heights[end] <= max_rows
    if !can_up && !can_down {
      break
    }
    if prefer_up {
      if can_up {
        start -= 1
        used += heights[start]
      } else if can_down {
        used += heights[end]
        end += 1
      }
    } else if can_down {
      used += heights[end]
      end += 1
    } else if can_up {
      start -= 1
      used += heights[start]
    }
    prefer_up = !prefer_up
  }
  let out : Array[String] = []
  for i in start..<end {
    out.push(lines[i])
  }
  out
}
