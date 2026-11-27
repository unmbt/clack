///|
pub fn ClackTheme::ClackTheme(
  unicode~ : Bool = true,
  with_guide~ : Bool = true,
) -> ClackTheme {
  { unicode, with_guide, }
}

///|
fn ClackTheme::u(self : ClackTheme, uni : String, ascii : String) -> String {
  if self.unicode {
    uni
  } else {
    ascii
  }
}

///|
fn ClackTheme::s_step_active(self : ClackTheme) -> String {
  self.u("◆", "*")
}

///|
fn ClackTheme::s_step_cancel(self : ClackTheme) -> String {
  self.u("■", "x")
}

///|
fn ClackTheme::s_step_error(self : ClackTheme) -> String {
  self.u("▲", "x")
}

///|
fn ClackTheme::s_step_submit(self : ClackTheme) -> String {
  self.u("◇", "o")
}

///|
fn ClackTheme::s_step_revert(self : ClackTheme) -> String {
  self.u("◁", "<")
}

///|
fn ClackTheme::s_bar_start(self : ClackTheme) -> String {
  self.u("┌", "T")
}

///|
fn ClackTheme::s_bar(self : ClackTheme) -> String {
  self.u("│", "|")
}

///|
fn ClackTheme::s_bar_end(self : ClackTheme) -> String {
  self.u("└", "—")
}

///|
fn ClackTheme::s_bar_h(self : ClackTheme) -> String {
  self.u("─", "-")
}

///|
fn ClackTheme::s_corner_top_right(self : ClackTheme) -> String {
  self.u("╮", "+")
}

///|
fn ClackTheme::s_connect_left(self : ClackTheme) -> String {
  self.u("├", "+")
}

///|
fn ClackTheme::s_corner_bottom_right(self : ClackTheme) -> String {
  self.u("╯", "+")
}

///|
fn ClackTheme::s_corner_bottom_left(self : ClackTheme) -> String {
  self.u("╰", "+")
}

///|
fn ClackTheme::s_radio_active(self : ClackTheme) -> String {
  self.u("●", ">")
}

///|
fn ClackTheme::s_radio_inactive(self : ClackTheme) -> String {
  self.u("○", " ")
}

///|
fn ClackTheme::s_checkbox_active(self : ClackTheme) -> String {
  self.u("◻", "[•]")
}

///|
fn ClackTheme::s_checkbox_selected(self : ClackTheme) -> String {
  self.u("◼", "[+]")
}

///|
fn ClackTheme::s_checkbox_inactive(self : ClackTheme) -> String {
  self.u("◻", "[ ]")
}

///|
fn ClackTheme::phase_symbol(
  self : ClackTheme,
  phase : PromptPhase,
  styler : @ansi.Styler,
) -> String {
  match phase {
    Initial | Active => styler.cyan(self.s_step_active())
    Validating => styler.dim(self.s_step_active())
    Warning(_) | Error(_) => styler.yellow(self.s_step_error())
    Submitted => styler.green(self.s_step_submit())
    Cancelled => styler.red(self.s_step_cancel())
    Reverted => styler.dim(self.s_step_revert())
  }
}

///|
fn ClackTheme::phase_bar(
  self : ClackTheme,
  phase : PromptPhase,
  styler : @ansi.Styler,
) -> String {
  match phase {
    Initial | Active | Validating => styler.cyan(self.s_bar())
    Warning(_) | Error(_) => styler.yellow(self.s_bar())
    Submitted => styler.green(self.s_bar())
    Cancelled => styler.red(self.s_bar())
    Reverted => styler.gray(self.s_bar())
  }
}

///|
fn repeat_str(s : String, n : Int32) -> String {
  if n <= 0 {
    return ""
  }
  let buf = StringBuilder()
  for _ in 0..<n {
    buf.write_string(s)
  }
  buf.to_string()
}

///|
fn ClackTheme::render_cursor_text(
  self : ClackTheme,
  rendered_value : String,
  cursor_pos : Int32,
  placeholder : String?,
  is_empty : Bool,
  is_password : Bool,
  styler : @ansi.Styler,
) -> String {
  if is_empty && !is_password {
    match placeholder {
      Some(ph) if ph != "" => {
        let chars = ph.to_array()
        let first = chars[0].to_string()
        let rest = if chars.length() > 1 {
          String::from_array(chars[1:].to_owned())
        } else {
          ""
        }
        return styler.inverse(first) + styler.dim(rest)
      }
      _ => return styler.inverse(styler.hidden("_"))
    }
  }
  let chars = rendered_value.to_array()
  let len = chars.length()
  let clamped : Int32 = if cursor_pos < 0 {
    0
  } else if cursor_pos > len {
    len
  } else {
    cursor_pos
  }
  if clamped >= len {
    if is_password {
      return rendered_value + styler.inverse(styler.hidden("_"))
    }
    return rendered_value + self.u("█", "_")
  }
  let pre = String::from_array(chars[:clamped].to_owned())
  let at = chars[clamped].to_string()
  let post = if clamped + 1 < len {
    String::from_array(chars[clamped + 1:].to_owned())
  } else {
    ""
  }
  pre + styler.inverse(at) + post
}

///|
fn ClackTheme::format_instruction_footer(
  self : ClackTheme,
  instructions : Array[String],
  has_guide : Bool,
  styler : @ansi.Styler,
  cols : Int32,
) -> Array[String] {
  let guide_prefix = if has_guide {
    styler.cyan(self.s_bar()) + "  "
  } else {
    ""
  }
  let sep = " " + self.u("•", "|") + " "
  let joined = instructions.join(sep)
  let lines = @ansi.wrap_text_with_prefix(joined, cols, guide_prefix)
  if has_guide {
    lines.push(styler.cyan(self.s_bar_end()))
  }
  lines
}

///|
fn ClackTheme::style_select_item(
  self : ClackTheme,
  row : OptionRowView,
  styler : @ansi.Styler,
) -> String {
  let hint_str = match row.hint {
    Some(h) if h != "" => " " + styler.dim("(\{h})")
    _ => ""
  }
  if row.is_disabled {
    let radio = styler.gray(self.s_radio_inactive())
    return radio + " " + styler.gray(row.label) + hint_str
  }
  if row.is_cursor {
    let radio = styler.green(self.s_radio_active())
    return radio + " " + row.label + hint_str
  }
  styler.dim(self.s_radio_inactive()) + " " + styler.dim(row.label)
}

///|
fn ClackTheme::style_multi_item(
  self : ClackTheme,
  row : OptionRowView,
  styler : @ansi.Styler,
) -> String {
  let hint_str = match row.hint {
    Some(h) if h != "" => " " + styler.dim("(\{h})")
    _ => ""
  }
  if row.is_disabled {
    let box = styler.gray(self.s_checkbox_inactive())
    return box + " " + styler.strikethrough(styler.gray(row.label)) + hint_str
  }
  if row.is_cursor && row.is_selected {
    return styler.green(self.s_checkbox_selected()) + " " + row.label + hint_str
  }
  if row.is_selected {
    return styler.green(self.s_checkbox_selected()) +
      " " +
      styler.dim(row.label) +
      hint_str
  }
  if row.is_cursor {
    return styler.cyan(self.s_checkbox_active()) + " " + row.label + hint_str
  }
  styler.dim(self.s_checkbox_inactive()) + " " + styler.dim(row.label)
}

///|
fn ClackTheme::style_group_row(
  self : ClackTheme,
  row : GroupRowView,
  styler : @ansi.Styler,
) -> String {
  match row {
    Header(label~, is_cursor~, all_selected~, selectable~, ..) => {
      let box = if !selectable {
        ""
      } else if all_selected {
        styler.green(self.s_checkbox_selected()) + " "
      } else if is_cursor {
        styler.cyan(self.s_checkbox_active()) + " "
      } else {
        styler.dim(self.s_checkbox_inactive()) + " "
      }
      let text = if is_cursor { label } else { styler.dim(label) }
      box + text
    }
    Item(row=opt, is_last_in_group~, in_active_group~, selectable_groups~) => {
      let raw_tree = if selectable_groups {
        if is_last_in_group {
          self.s_bar_end() + " "
        } else {
          self.s_bar() + " "
        }
      } else {
        "  "
      }
      let tree_prefix = if in_active_group {
        raw_tree
      } else {
        styler.dim(raw_tree)
      }
      let hint_str = match opt.hint {
        Some(h) if h != "" => " " + styler.dim("(\{h})")
        _ => ""
      }
      if opt.is_disabled {
        return tree_prefix +
          styler.gray(self.s_checkbox_inactive()) +
          " " +
          styler.strikethrough(styler.gray(opt.label)) +
          hint_str
      }
      if in_active_group {
        let box = if opt.is_selected {
          styler.green(self.s_checkbox_selected())
        } else {
          styler.cyan(self.s_checkbox_active())
        }
        return tree_prefix + box + " " + styler.dim(opt.label)
      }
      if opt.is_cursor && opt.is_selected {
        return tree_prefix +
          styler.green(self.s_checkbox_selected()) +
          " " +
          opt.label +
          hint_str
      }
      if opt.is_selected {
        return tree_prefix +
          styler.green(self.s_checkbox_selected()) +
          " " +
          styler.dim(opt.label) +
          hint_str
      }
      if opt.is_cursor {
        return tree_prefix +
          styler.cyan(self.s_checkbox_active()) +
          " " +
          opt.label +
          hint_str
      }
      tree_prefix +
      styler.dim(self.s_checkbox_inactive()) +
      " " +
      styler.dim(opt.label)
    }
  }
}

///|
pub impl Theme for ClackTheme with fn render_frame(self, spec, styler, cols) {
  let has_guide = self.with_guide && spec.with_guide
  let effective_cols : Int32 = if cols > 0 { cols } else { 80 }
  let effective_rows : Int32 = match spec.max_rows {
    Some(r) if r > 0 => r
    _ => 24
  }
  let lines : Array[String] = []
  if has_guide {
    lines.push(styler.gray(self.s_bar()))
  }
  let title_prefix = self.phase_symbol(spec.phase, styler) + "  "
  let title_bar = if has_guide {
    self.phase_bar(spec.phase, styler) + "  "
  } else {
    ""
  }
  let title_lines = @ansi.wrap_text_with_prefix(
    spec.message,
    effective_cols,
    title_bar,
    first_prefix=title_prefix,
  )
  for tl in title_lines {
    lines.push(tl)
  }

  let gray_bar = styler.gray(self.s_bar())
  let summary = match spec.submitted_summary {
    Some(s) => s
    None => ""
  }

  // Handle terminal phases (Submitted / Cancelled / Reverted) consistently across widgets
  match spec.phase {
    Submitted => {
      if summary != "" {
        let sub_prefix = if has_guide { gray_bar + "  " } else { "" }
        let wrapped = @ansi.wrap_text_with_prefix(
          styler.dim(summary),
          effective_cols,
          sub_prefix,
        )
        for wl in wrapped {
          lines.push(wl)
        }
      } else if has_guide {
        lines.push(gray_bar)
      }
      return lines
    }
    Cancelled => {
      if summary.trim() != "" {
        let cancel_prefix = if has_guide { gray_bar + "  " } else { "" }
        let wrapped = @ansi.wrap_text_with_prefix(
          styler.strikethrough(styler.dim(summary)),
          effective_cols,
          cancel_prefix,
        )
        for wl in wrapped {
          lines.push(wl)
        }
        if has_guide {
          lines.push(gray_bar)
        }
      } else if has_guide {
        lines.push(gray_bar)
      }
      return lines
    }
    Reverted => {
      let rev_prefix = if has_guide { gray_bar + "  " } else { "" }
      lines.push(rev_prefix + styler.dim("Reverted"))
      return lines
    }
    _ => ()
  }

  let is_err_or_warn = spec.phase is (Error(_) | Warning(_))
  let active_bar = if has_guide {
    (if is_err_or_warn {
      styler.yellow(self.s_bar())
    } else {
      styler.cyan(self.s_bar())
    }) +
    "  "
  } else {
    ""
  }
  let active_end = if has_guide {
    if is_err_or_warn {
      styler.yellow(self.s_bar_end())
    } else {
      styler.cyan(self.s_bar_end())
    }
  } else {
    ""
  }

  match spec.body {
    TextInput(
      rendered_value~,
      cursor_pos~,
      placeholder~,
      is_empty~,
      is_password~,
      ..
    ) => {
      let input_display = self.render_cursor_text(
        rendered_value, cursor_pos, placeholder, is_empty, is_password, styler,
      )
      match spec.phase {
        Validating => {
          lines.push(active_bar + styler.dim(input_display))
          lines.push(active_end + "  " + styler.dim("Validating..."))
        }
        Warning(msg) | Error(msg) => {
          lines.push(active_bar + input_display)
          let err_tail = if msg != "" { "  " + styler.yellow(msg) } else { "" }
          lines.push(active_end + err_tail)
        }
        _ => {
          lines.push(active_bar + input_display)
          if has_guide {
            lines.push(active_end)
          }
        }
      }
    }
    ConfirmToggle(active_yes~, yes_label~, no_label~, vertical~) => {
      let yes_text = if active_yes {
        styler.green(self.s_radio_active()) + " " + yes_label
      } else {
        styler.dim(self.s_radio_inactive()) + " " + styler.dim(yes_label)
      }
      let no_text = if !active_yes {
        styler.green(self.s_radio_active()) + " " + no_label
      } else {
        styler.dim(self.s_radio_inactive()) + " " + styler.dim(no_label)
      }
      if vertical {
        lines.push(active_bar + yes_text)
        lines.push(active_bar + no_text)
      } else {
        lines.push(
          active_bar + yes_text + " " + styler.dim("/") + " " + no_text,
        )
      }
      if has_guide {
        lines.push(active_end)
      }
    }
    OptionList(
      items~,
      cursor~,
      max_items~,
      total_count~,
      total_unfiltered~,
      filter_query~,
      filter_cursor~,
      filter_placeholder~,
      is_navigating~,
      complete_on_tab~,
      show_instructions~,
      is_multi~,
    ) =>
      match filter_query {
        Some(q) => {
          // 1:1 upstream autocomplete layout
          if has_guide {
            lines.push(
              if is_err_or_warn {
                styler.yellow(self.s_bar())
              } else {
                styler.cyan(self.s_bar())
              },
            )
          }
          let show_ph = q == "" &&
            (match filter_placeholder {
              Some(p) => p != ""
              None => false
            })
          let search_val = if is_navigating || show_ph {
            let txt = if show_ph {
              match filter_placeholder {
                Some(p) => p
                None => ""
              }
            } else {
              q
            }
            if txt != "" {
              " " + styler.dim(txt)
            } else {
              ""
            }
          } else {
            " " +
            self.render_cursor_text(
              q,
              filter_cursor,
              None,
              q == "",
              false,
              styler,
            )
          }
          let match_badge = if total_count != total_unfiltered {
            let plural = if total_count == 1 { "" } else { "es" }
            styler.dim(" (\{total_count} match\{plural})")
          } else {
            ""
          }
          lines.push(
            active_bar + styler.dim("Search:") + search_val + match_badge,
          )
          if items.is_empty() && q != "" {
            lines.push(active_bar + styler.yellow("No matches found"))
          }
          match spec.phase {
            Error(msg) | Warning(msg) if msg != "" =>
              lines.push(active_bar + styler.yellow(msg))
            _ => ()
          }
          let insts : Array[String] = if is_multi {
            let toggle_key = if is_navigating { "Space/Tab:" } else { "Tab:" }
            [
              styler.dim(self.u("↑/↓", "Up/Down")) + " to navigate",
              styler.dim(toggle_key) + " select",
              styler.dim("Enter:") + " confirm",
              styler.dim("Type:") + " to search",
            ]
          } else {
            let single_insts : Array[String] = [
              styler.dim(self.u("↑/↓", "Up/Down")) + " to select",
            ]
            if complete_on_tab {
              single_insts.push(styler.dim("Tab:") + " complete")
            }
            single_insts.push(styler.dim("Enter:") + " confirm")
            single_insts.push(styler.dim("Type:") + " to search")
            single_insts
          }
          let footer_lines = self.format_instruction_footer(
            insts, has_guide, styler, effective_cols,
          )
          let styled_opts : Array[String] = []
          for it in items {
            let row_str = if is_multi {
              self.style_multi_item(it, styler)
            } else if it.is_disabled {
              styler.gray(self.s_radio_inactive()) +
              " " +
              styler.strikethrough(styler.gray(it.label))
            } else {
              self.style_select_item(it, styler)
            }
            styled_opts.push(row_str)
          }
          let limited = limit_options(
            styled_opts,
            cursor,
            effective_cols,
            effective_rows,
            max_items?,
            column_padding=if has_guide { 3 } else { 0 },
            row_padding=lines.length() + footer_lines.length() + 1,
            ellipsis=styler.dim("..."),
          )
          for opt_line in limited {
            lines.push(active_bar + opt_line)
          }
          for fl in footer_lines {
            lines.push(fl)
          }
        }
        None => {
          let footer_lines : Array[String] = match spec.phase {
            Warning(msg) | Error(msg) => {
              let err_lines : Array[String] = []
              let parts = msg.split("\n").collect()
              for idx in 0..<parts.length() {
                let ln = parts[idx].to_owned()
                if idx == 0 {
                  let prefix = if has_guide {
                    styler.yellow(self.s_bar_end()) + "  "
                  } else {
                    ""
                  }
                  err_lines.push(prefix + styler.yellow(ln))
                } else {
                  err_lines.push("   " + ln)
                }
              }
              err_lines
            }
            _ =>
              if show_instructions {
                let insts = if is_multi {
                  [
                    styler.dim(self.u("↑/↓", "Up/Down")) + " to navigate",
                    styler.dim("Space:") + " select",
                    styler.dim("Enter:") + " confirm",
                  ]
                } else {
                  [
                    styler.dim(self.u("↑/↓", "Up/Down")) + " to navigate",
                    styler.dim("Enter:") + " confirm",
                  ]
                }
                self.format_instruction_footer(
                  insts, has_guide, styler, effective_cols,
                )
              } else if has_guide {
                [active_end]
              } else {
                []
              }
          }
          let styled_opts : Array[String] = []
          for it in items {
            let s = if is_multi {
              self.style_multi_item(it, styler)
            } else {
              self.style_select_item(it, styler)
            }
            styled_opts.push(s)
          }
          let limited = limit_options(
            styled_opts,
            cursor,
            effective_cols,
            effective_rows,
            max_items?,
            column_padding=if has_guide { 3 } else { 0 },
            row_padding=lines.length() + footer_lines.length() + 1,
            ellipsis=styler.dim("..."),
          )
          for opt_line in limited {
            lines.push(active_bar + opt_line)
          }
          for fl in footer_lines {
            lines.push(fl)
          }
        }
      }
    GroupOptionList(
      rows~,
      cursor~,
      max_items~,
      group_spacing~,
      show_instructions~,
      ..
    ) => {
      let footer_lines : Array[String] = match spec.phase {
        Warning(msg) | Error(msg) => {
          let prefix = if has_guide {
            styler.yellow(self.s_bar_end()) + "  "
          } else {
            ""
          }
          [prefix + styler.yellow(msg)]
        }
        _ =>
          if show_instructions {
            let insts = [
              styler.dim(self.u("↑/↓", "Up/Down")) + " to navigate",
              styler.dim("Space:") + " select",
              styler.dim("Enter:") + " confirm",
            ]
            self.format_instruction_footer(
              insts, has_guide, styler, effective_cols,
            )
          } else if has_guide {
            [active_end]
          } else {
            []
          }
      }
      let styled_rows : Array[String] = []
      for i in 0..<rows.length() {
        let mut s = self.style_group_row(rows[i], styler)
        if i > 0 && group_spacing > 0 && rows[i] is Header(..) {
          s = repeat_str("\n", group_spacing) + s
        }
        styled_rows.push(s)
      }
      let limited = limit_options(
        styled_rows,
        cursor,
        effective_cols,
        effective_rows,
        max_items?,
        column_padding=if has_guide { 3 } else { 0 },
        row_padding=lines.length() + footer_lines.length() + 1,
        ellipsis=styler.dim("..."),
      )
      for opt_line in limited {
        lines.push(active_bar + opt_line)
      }
      for fl in footer_lines {
        lines.push(fl)
      }
    }
    SelectKeyList(items~) => {
      for it in items {
        let hint_str = match it.hint {
          Some(h) if h != "" => " " + styler.dim("(\{h})")
          _ => ""
        }
        let badge_text = " \{it.key} "
        let rendered = if it.is_disabled {
          styler.dim(badge_text) + " " + styler.gray(it.label) + hint_str
        } else if it.is_cursor {
          styler.bg_cyan(styler.gray(badge_text)) + " " + it.label + hint_str
        } else {
          styler.gray(styler.bg_white(styler.inverse(badge_text))) +
          " " +
          it.label +
          hint_str
        }
        let wrapped = @ansi.wrap_text_with_prefix(
          rendered, effective_cols, active_bar,
        )
        for wl in wrapped {
          lines.push(wl)
        }
      }
      if has_guide {
        lines.push(active_end)
      }
    }
    MultiLineInput(
      lines=ml_lines,
      cursor_line~,
      cursor_col~,
      placeholder~,
      is_empty~,
      show_submit~,
      submit_focused~,
    ) => {
      if is_empty {
        let ph_rendered = self.render_cursor_text(
          "", 0, placeholder, true, false, styler,
        )
        lines.push(active_bar + ph_rendered)
      } else {
        for li in 0..<ml_lines.length() {
          let raw_line = ml_lines[li]
          let line_rendered = if !submit_focused && li == cursor_line {
            self.render_cursor_text(
              raw_line,
              cursor_col,
              None,
              false,
              false,
              styler,
            )
          } else {
            raw_line
          }
          let wrapped = @ansi.wrap_text_with_prefix(
            line_rendered, effective_cols, active_bar,
          )
          for wl in wrapped {
            lines.push(wl)
          }
        }
      }
      match spec.phase {
        Warning(msg) | Error(msg) => {
          let err_tail = if msg != "" { "  " + styler.yellow(msg) } else { "" }
          lines.push(active_end + err_tail)
        }
        _ => if has_guide { lines.push(active_end) }
      }
      if show_submit {
        let btn = if submit_focused {
          styler.cyan("[ submit ]")
        } else {
          styler.dim("[ submit ]")
        }
        lines.push("  " + btn)
      }
    }
    DateInput(segments~, separator~, inline_error~) => {
      let sep = styler.gray(separator)
      let seg_strs : Array[String] = []
      for seg in segments {
        let shown = if seg.text == "" { seg.label } else { seg.text }
        if seg.is_active {
          seg_strs.push(styler.inverse(shown))
        } else if seg.text == "" {
          seg_strs.push(styler.dim(shown))
        } else {
          seg_strs.push(shown)
        }
      }
      lines.push(active_bar + seg_strs.join(sep))
      match inline_error {
        Some(err) if err != "" => lines.push(active_bar + styler.yellow(err))
        _ => ()
      }
      match spec.phase {
        Warning(msg) | Error(msg) => {
          let err_tail = if msg != "" { "  " + styler.yellow(msg) } else { "" }
          lines.push(active_end + err_tail)
        }
        _ => if has_guide { lines.push(active_end) }
      }
    }
  }
  lines
}

///|
pub impl Theme for ClackTheme with fn render_intro(self, title, styler) {
  let prefix = if self.with_guide {
    styler.gray(self.s_bar_start()) + "  "
  } else {
    ""
  }
  prefix + title.to_owned()
}

///|
pub impl Theme for ClackTheme with fn render_outro(self, message, styler) {
  let prefix = if self.with_guide {
    styler.gray(self.s_bar()) + "\n" + styler.gray(self.s_bar_end()) + "  "
  } else {
    ""
  }
  prefix + message.to_owned() + "\n"
}

///|
pub impl Theme for ClackTheme with fn render_cancel(self, message, styler) {
  let prefix = if self.with_guide {
    styler.gray(self.s_bar_end()) + "  "
  } else {
    ""
  }
  prefix + styler.red(message) + "\n"
}

///|
/// Render a Clack rounded note box with terminal-width wrapping and optional per-line formatter.
pub fn ClackTheme::render_note_formatted(
  self : ClackTheme,
  title : StringView,
  body : StringView,
  styler : @ansi.Styler,
  cols~ : Int32 = 80,
  format? : (String) -> String,
) -> String {
  let title_str = title.to_owned()
  let body_str = body.to_owned()
  let fmt = match format {
    Some(f) => f
    None => fn(s) { s }
  }
  let wrap_w : Int32 = if cols - 6 > 10 { cols - 6 } else { 10 }
  let wrapped_body = @ansi.wrap_ansi(body_str, wrap_w)
  let raw_lines : Array[String] = [""]
  for ln in wrapped_body {
    raw_lines.push(fmt(ln))
  }
  raw_lines.push("")
  let title_len = @ansi.display_width(title_str)
  let mut max_w = title_len
  for ln in raw_lines {
    let w = @ansi.display_width(ln)
    if w > max_w {
      max_w = w
    }
  }
  let inner_len = max_w + 2
  let top_dashes = if inner_len - title_len - 1 > 1 {
    inner_len - title_len - 1
  } else {
    1
  }
  let out : Array[String] = []
  if self.with_guide {
    out.push(styler.gray(self.s_bar()))
  }
  out.push(
    styler.green(self.s_step_submit()) +
    "  " +
    title_str +
    " " +
    styler.gray(
      repeat_str(self.s_bar_h(), top_dashes) + self.s_corner_top_right(),
    ),
  )
  for ln in raw_lines {
    let pad = inner_len - @ansi.display_width(ln)
    out.push(
      styler.gray(self.s_bar()) +
      "  " +
      ln +
      repeat_str(" ", pad) +
      styler.gray(self.s_bar()),
    )
  }
  let bottom_left = if self.with_guide {
    self.s_connect_left()
  } else {
    self.s_corner_bottom_left()
  }
  out.push(
    styler.gray(
      bottom_left +
      repeat_str(self.s_bar_h(), inner_len + 2) +
      self.s_corner_bottom_right(),
    ),
  )
  out.join("\n")
}

///|
pub impl Theme for ClackTheme with fn render_note(self, title, body, styler) {
  self.render_note_formatted(title, body, styler)
}

///|
pub impl Theme for ClackTheme with fn render_log(self, kind, message, styler) {
  let k = kind.to_owned()
  let sym = match k {
    "info" => styler.blue(self.u("●", "•"))
    "success" => styler.green(self.u("◆", "*"))
    "step" => styler.green(self.s_step_submit())
    "warn" | "warning" => styler.yellow(self.u("▲", "!"))
    "error" => styler.red(self.u("■", "x"))
    "message" | "" => styler.gray(self.s_bar())
    _ => k
  }
  let gray_bar = styler.gray(self.s_bar())
  let parts : Array[String] = []
  if self.with_guide {
    parts.push(gray_bar)
  }
  let msg_lines = message.to_owned().split("\n").collect()
  for i in 0..<msg_lines.length() {
    let ln = msg_lines[i].to_owned()
    if i == 0 {
      if self.with_guide {
        if ln == "" {
          parts.push(sym)
        } else {
          parts.push(sym + "  " + ln)
        }
      } else {
        parts.push(ln)
      }
    } else if self.with_guide {
      if ln == "" {
        parts.push(gray_bar)
      } else {
        parts.push(gray_bar + "  " + ln)
      }
    } else {
      parts.push(ln)
    }
  }
  parts.join("\n")
}

///|
pub extend ClackTheme with Theme::{
  render_frame,
  render_intro,
  render_outro,
  render_cancel,
  render_note,
  render_log,
}
