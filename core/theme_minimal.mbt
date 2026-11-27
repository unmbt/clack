///|
pub fn MinimalTheme::MinimalTheme(unicode~ : Bool = true) -> MinimalTheme {
  { unicode, }
}

///|
fn MinimalTheme::u(self : MinimalTheme, uni : String, ascii : String) -> String {
  if self.unicode {
    uni
  } else {
    ascii
  }
}

///|
fn MinimalTheme::prefix(
  self : MinimalTheme,
  phase : PromptPhase,
  styler : @ansi.Styler,
) -> String {
  match phase {
    Initial | Active | Validating => styler.cyan(self.u("?", "?"))
    Warning(_) | Error(_) => styler.yellow(self.u("⚠", "!"))
    Submitted => styler.green(self.u("✔", "+"))
    Cancelled => styler.red(self.u("✖", "x"))
    Reverted => styler.dim(self.u("◁", "<"))
  }
}

///|
fn MinimalTheme::sep(self : MinimalTheme, styler : @ansi.Styler) -> String {
  styler.dim(self.u("›", ">"))
}

///|
fn MinimalTheme::dot(self : MinimalTheme, styler : @ansi.Styler) -> String {
  styler.dim(self.u("·", "-"))
}

///|
pub impl Theme for MinimalTheme with fn render_frame(self, spec, styler, cols) {
  let effective_cols : Int32 = if cols > 0 { cols } else { 80 }
  let effective_rows : Int32 = match spec.max_rows {
    Some(r) if r > 0 => r
    _ => 24
  }
  let lead = self.prefix(spec.phase, styler) + " " + styler.bold(spec.message)
  let summary = match spec.submitted_summary {
    Some(s) => s
    None => ""
  }

  match spec.phase {
    Submitted =>
      return [
        if summary != "" {
          lead + " " + self.dot(styler) + " " + styler.dim(summary)
        } else {
          lead
        },
      ]
    Cancelled =>
      return [
        if summary != "" {
          lead +
          " " +
          self.dot(styler) +
          " " +
          styler.strikethrough(styler.dim(summary))
        } else {
          lead + " " + styler.dim("Cancelled")
        },
      ]
    Reverted => return [lead + " " + styler.dim("Reverted")]
    _ => ()
  }

  let lines : Array[String] = []
  let pointer = styler.cyan(self.u("❯", ">"))
  let box_on = styler.green(self.u("◼", "[x]"))
  let box_off = styler.dim(self.u("◻", "[ ]"))
  let box_cur = styler.cyan(self.u("◻", "[ ]"))

  match spec.body {
    TextInput(rendered_value~, placeholder~, is_empty~, is_password~, ..) => {
      let display = if is_empty && !is_password {
        match placeholder {
          Some(ph) if ph != "" => styler.dim(ph)
          _ => ""
        }
      } else {
        rendered_value
      }
      lines.push(lead + " " + self.sep(styler) + " " + display)
    }
    ConfirmToggle(active_yes~, yes_label~, no_label~, ..) => {
      let yes_s = if active_yes {
        styler.cyan(styler.underline(yes_label))
      } else {
        styler.dim(yes_label)
      }
      let no_s = if !active_yes {
        styler.cyan(styler.underline(no_label))
      } else {
        styler.dim(no_label)
      }
      lines.push(
        lead +
        " " +
        self.sep(styler) +
        " " +
        yes_s +
        " " +
        styler.dim("/") +
        " " +
        no_s,
      )
    }
    OptionList(
      items~,
      cursor~,
      max_items~,
      filter_query~,
      filter_placeholder~,
      is_multi~,
      ..
    ) => {
      let header_tail = match filter_query {
        Some(q) =>
          if q != "" {
            " " + self.sep(styler) + " " + q
          } else {
            match filter_placeholder {
              Some(ph) if ph != "" =>
                " " + self.sep(styler) + " " + styler.dim(ph)
              _ => " " + self.sep(styler)
            }
          }
        None => " " + self.sep(styler) + " " + styler.dim("(Use arrows)")
      }
      lines.push(lead + header_tail)
      let styled : Array[String] = []
      for it in items {
        let hint_str = match it.hint {
          Some(h) if h != "" => " " + styler.dim("(\{h})")
          _ => ""
        }
        let row_s = if is_multi {
          let cur_p = if it.is_cursor { pointer + " " } else { "  " }
          if it.is_disabled {
            cur_p +
            styler.gray(self.u("◻", "[ ]")) +
            " " +
            styler.strikethrough(styler.gray(it.label)) +
            hint_str
          } else {
            let box = if it.is_selected {
              box_on
            } else if it.is_cursor {
              box_cur
            } else {
              box_off
            }
            let lbl = if it.is_cursor { it.label } else { styler.dim(it.label) }
            cur_p + box + " " + lbl + hint_str
          }
        } else if it.is_disabled {
          "  " + styler.gray(it.label) + hint_str
        } else if it.is_cursor {
          pointer + " " + styler.cyan(it.label) + hint_str
        } else {
          "  " + it.label
        }
        styled.push(row_s)
      }
      if styled.is_empty() && filter_query is Some(q) && q != "" {
        lines.push("  " + styler.yellow("No matches found"))
      } else {
        let limited = limit_options(
          styled,
          cursor,
          effective_cols,
          effective_rows,
          max_items?,
          column_padding=0,
          row_padding=3,
          ellipsis=styler.dim("..."),
        )
        for ln in limited {
          lines.push(ln)
        }
      }
    }
    GroupOptionList(rows~, cursor~, max_items~, ..) => {
      lines.push(
        lead + " " + self.sep(styler) + " " + styler.dim("(Space to toggle)"),
      )
      let styled : Array[String] = []
      for r in rows {
        match r {
          Header(label~, is_cursor~, all_selected~, selectable~, ..) => {
            let cur_p = if is_cursor { pointer + " " } else { "  " }
            let box = if !selectable {
              ""
            } else if all_selected {
              box_on + " "
            } else if is_cursor {
              box_cur + " "
            } else {
              box_off + " "
            }
            styled.push(
              cur_p + box + (if is_cursor { styler.bold(label) } else { label }),
            )
          }
          Item(row=opt, ..) => {
            let cur_p = if opt.is_cursor { pointer + "   " } else { "    " }
            let box = if opt.is_disabled {
              styler.gray(self.u("◻", "[ ]"))
            } else if opt.is_selected {
              box_on
            } else if opt.is_cursor {
              box_cur
            } else {
              box_off
            }
            let lbl = if opt.is_disabled {
              styler.strikethrough(styler.gray(opt.label))
            } else if opt.is_cursor {
              opt.label
            } else {
              styler.dim(opt.label)
            }
            styled.push(cur_p + box + " " + lbl)
          }
        }
      }
      let limited = limit_options(
        styled,
        cursor,
        effective_cols,
        effective_rows,
        max_items?,
        column_padding=0,
        row_padding=3,
        ellipsis=styler.dim("..."),
      )
      for ln in limited {
        lines.push(ln)
      }
    }
    SelectKeyList(items~) => {
      lines.push(
        lead + " " + self.sep(styler) + " " + styler.dim("(Press key)"),
      )
      for it in items {
        let hint_str = match it.hint {
          Some(h) if h != "" => " " + styler.dim("(\{h})")
          _ => ""
        }
        if it.is_disabled {
          lines.push("  [" + it.key + "] " + styler.gray(it.label) + hint_str)
        } else if it.is_cursor {
          lines.push(
            pointer +
            " " +
            styler.cyan("[\{it.key}]") +
            " " +
            it.label +
            hint_str,
          )
        } else {
          lines.push(
            "  " + styler.dim("[\{it.key}]") + " " + it.label + hint_str,
          )
        }
      }
    }
    MultiLineInput(
      lines=ml_lines,
      placeholder~,
      is_empty~,
      show_submit~,
      submit_focused~,
      ..
    ) => {
      lines.push(lead + " " + self.sep(styler))
      if is_empty {
        match placeholder {
          Some(ph) if ph != "" => lines.push("  " + styler.dim(ph))
          _ => lines.push("  ")
        }
      } else {
        for ml in ml_lines {
          lines.push("  " + ml)
        }
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
      let rendered_segs : Array[String] = []
      for seg in segments {
        let shown = if seg.text == "" { seg.label } else { seg.text }
        if seg.is_active {
          rendered_segs.push(styler.inverse(shown))
        } else if seg.text == "" {
          rendered_segs.push(styler.dim(shown))
        } else {
          rendered_segs.push(shown)
        }
      }
      lines.push(
        lead +
        " " +
        self.sep(styler) +
        " " +
        rendered_segs.join(styler.gray(separator)),
      )
      match inline_error {
        Some(err) if err != "" => lines.push(styler.yellow(err))
        _ => ()
      }
    }
  }

  match spec.phase {
    Warning(msg) | Error(msg) if msg != "" =>
      lines.push(styler.yellow(self.u("⚠", "!") + " " + msg))
    Validating => lines.push(styler.dim("Validating..."))
    _ => ()
  }
  lines
}

///|
pub impl Theme for MinimalTheme with fn render_intro(_self, title, styler) {
  styler.bold(title)
}

///|
pub impl Theme for MinimalTheme with fn render_outro(self, message, styler) {
  styler.green(self.u("✔", "+")) + " " + message.to_owned()
}

///|
pub impl Theme for MinimalTheme with fn render_cancel(self, message, styler) {
  styler.red(self.u("✖", "x")) + " " + styler.red(message)
}

///|
pub impl Theme for MinimalTheme with fn render_note(_self, title, body, styler) {
  styler.bold(title) + "\n" + body.to_owned()
}

///|
pub impl Theme for MinimalTheme with fn render_log(self, kind, message, styler) {
  let k = kind.to_owned()
  let icon = match k {
    "info" => styler.blue(self.u("ℹ", "i"))
    "success" => styler.green(self.u("✔", "+"))
    "step" => styler.cyan(self.u("›", ">"))
    "warn" | "warning" => styler.yellow(self.u("⚠", "!"))
    "error" => styler.red(self.u("✖", "x"))
    _ => " "
  }
  icon + " " + message.to_owned()
}

///|
pub extend MinimalTheme with Theme::{
  render_frame,
  render_intro,
  render_outro,
  render_cancel,
  render_note,
  render_log,
}
