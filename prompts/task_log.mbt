///|
priv struct TaskLogBuffer {
  header : String?
  mut value : String
  mut full : String
  mut result_status : Int32 // 0 = active, 1 = success, 2 = error
  mut result_message : String
}

///|
/// Streaming task log widget (1:1 upstream `@clack/prompts` `taskLog`):
/// - Strips destructive cursor/clear CSI via `@ansi.strip_destructive_ansi`
/// - Supports `limit`, `retain_log`, nested `group(name)`, and live TTY redraw
/// - Collapses cleanly on `success()` and retains full output on `error()`
pub struct TaskLog {
  priv session : Session
  priv title : String
  priv limit : Int32?
  priv spacing : Int32
  priv retain_log : Bool
  priv renderer : @core.InlineDiffRenderer
  priv buffers : Array[TaskLogBuffer]
  priv mut last_was_raw : Bool
  priv mut started : Bool
}

///|
pub struct TaskLogGroup {
  priv parent : TaskLog
  priv buf_idx : Int32
}

///|
pub fn TaskLog::TaskLog(
  title~ : String,
  limit? : Int32,
  spacing~ : Int32 = 1,
  retain_log~ : Bool = false,
  session? : Session,
) -> TaskLog {
  let s = resolve_session(session)
  {
    session: s,
    title,
    limit,
    spacing: if spacing >= 0 {
      spacing
    } else {
      0
    },
    retain_log,
    renderer: @core.InlineDiffRenderer(),
    buffers: [
      {
        header: None,
        value: "",
        full: "",
        result_status: 0,
        result_message: "",
      },
    ],
    last_was_raw: false,
    started: false,
  }
}

///|
fn TaskLog::is_live_tty(self : TaskLog) -> Bool {
  self.session.is_interactive() &&
  !self.session.is_ci() &&
  !self.session.accessible
}

///|
fn TaskLog::bar(self : TaskLog) -> String {
  self.session.styler.gray(if self.session.unicode { "│" } else { "|" })
}

///|
fn TaskLog::format_live_lines(self : TaskLog) -> Array[String] {
  let out : Array[String] = []
  let bar = self.bar()
  let has_guide = self.session.with_guide
  if has_guide {
    out.push(bar)
  }
  let step_sym = self.session.styler.green(
    if self.session.unicode {
      "◇"
    } else {
      "o"
    },
  )
  out.push((if has_guide { step_sym + "  " } else { "" }) + self.title)
  for _ in 0..<self.spacing {
    out.push(if has_guide { bar } else { "" })
  }
  let prefix = if has_guide { bar + "  " } else { "" }
  for b in self.buffers {
    if b.result_status == 1 {
      let sym = self.session.styler.green(
        if self.session.unicode {
          "◆"
        } else {
          "*"
        },
      )
      out.push((if has_guide { sym + "  " } else { "" }) + b.result_message)
    } else if b.result_status == 2 {
      let sym = self.session.styler.red(
        if self.session.unicode {
          "■"
        } else {
          "x"
        },
      )
      out.push((if has_guide { sym + "  " } else { "" }) + b.result_message)
    } else if b.value != "" || b.header is Some(_) {
      match b.header {
        Some(h) if h != "" =>
          for hl in h.split("\n") {
            out.push(prefix + self.session.styler.bold(hl))
          }
        _ => ()
      }
      if b.value != "" {
        for vl in b.value.split("\n") {
          out.push(prefix + self.session.styler.dim(vl))
        }
      }
    }
  }
  out
}

///|
pub async fn TaskLog::start(self : TaskLog) -> Unit raise @term.TermError {
  if self.started {
    return
  }
  self.started = true
  self.renderer.reset()
  if self.is_live_tty() {
    let (raw_cols, _) = self.session.term.size()
    let cols = if raw_cols > 0 { raw_cols } else { 80 }
    let patched = self.renderer.patch(
      self.format_live_lines(),
      cols,
      sync_output=true,
    )
    if patched != "" {
      self.session.term.write_str(patched)
    }
  } else {
    self.session.term.write_str(self.format_live_lines().join("\n") + "\n")
  }
}

///|
async fn TaskLog::push_to_buffer(
  self : TaskLog,
  buf_idx : Int32,
  msg : StringView,
  raw : Bool,
) -> Unit raise @term.TermError {
  if !self.started {
    self.start()
  }
  let buf = self.buffers[buf_idx]
  if (!raw || !self.last_was_raw) && buf.value != "" {
    buf.value = buf.value + "\n"
  }
  buf.value = buf.value + @ansi.strip_destructive_ansi(msg)
  self.last_was_raw = raw
  match self.limit {
    Some(lim) if lim > 0 => {
      let lines : Array[String] = []
      for part in buf.value.split("\n") {
        lines.push(part.to_owned())
      }
      let extra = lines.length() - lim
      if extra > 0 {
        if self.retain_log {
          let removed : Array[String] = []
          for i in 0..<extra {
            removed.push(lines[i])
          }
          let rem_str = removed.join("\n")
          buf.full = if buf.full == "" {
            rem_str
          } else {
            buf.full + "\n" + rem_str
          }
        }
        let kept : Array[String] = []
        for i in extra..<lines.length() {
          kept.push(lines[i])
        }
        buf.value = kept.join("\n")
      }
    }
    _ => ()
  }
  if self.is_live_tty() {
    let (raw_cols, _) = self.session.term.size()
    let cols = if raw_cols > 0 { raw_cols } else { 80 }
    let patched = self.renderer.patch(
      self.format_live_lines(),
      cols,
      sync_output=true,
    )
    if patched != "" {
      self.session.term.write_str(patched)
    }
  }
}

///|
pub async fn TaskLog::message(
  self : TaskLog,
  msg : StringView,
  raw~ : Bool = false,
) -> Unit raise @term.TermError {
  self.push_to_buffer(0, msg, raw)
}

///|
pub fn TaskLog::group(self : TaskLog, name : String) -> TaskLogGroup {
  let idx = self.buffers.length()
  self.buffers.push({
    header: Some(name),
    value: "",
    full: "",
    result_status: 0,
    result_message: "",
  })
  { parent: self, buf_idx: idx, }
}

///|
pub async fn TaskLogGroup::message(
  self : TaskLogGroup,
  msg : StringView,
  raw~ : Bool = false,
) -> Unit raise @term.TermError {
  self.parent.push_to_buffer(self.buf_idx, msg, raw)
}

///|
async fn TaskLogGroup::complete(
  self : TaskLogGroup,
  status : Int32,
  message : StringView,
) -> Unit raise @term.TermError {
  let buf = self.parent.buffers[self.buf_idx]
  buf.result_status = status
  buf.result_message = message.to_owned()
  if self.parent.is_live_tty() {
    let (raw_cols, _) = self.parent.session.term.size()
    let cols = if raw_cols > 0 { raw_cols } else { 80 }
    let patched = self.parent.renderer.patch(
      self.parent.format_live_lines(),
      cols,
      sync_output=true,
    )
    if patched != "" {
      self.parent.session.term.write_str(patched)
    }
  }
}

///|
pub async fn TaskLogGroup::success(
  self : TaskLogGroup,
  message : StringView,
) -> Unit raise @term.TermError {
  self.complete(1, message)
}

///|
pub async fn TaskLogGroup::error(
  self : TaskLogGroup,
  message : StringView,
) -> Unit raise @term.TermError {
  self.complete(2, message)
}

///|
async fn TaskLog::finish(
  self : TaskLog,
  is_error : Bool,
  message : StringView,
  show_log : Bool,
) -> Unit raise @term.TermError {
  let bar = self.bar()
  let has_guide = self.session.with_guide
  let final_lines : Array[String] = []
  if has_guide {
    final_lines.push(bar)
  }
  let sym = if is_error {
    self.session.styler.red(if self.session.unicode { "■" } else { "x" })
  } else {
    self.session.styler.green(if self.session.unicode { "◆" } else { "*" })
  }
  final_lines.push(
    (if has_guide { sym + "  " } else { "" }) + message.to_owned(),
  )
  if show_log {
    let prefix = if has_guide { bar + "  " } else { "" }
    for b in self.buffers {
      let combined = if self.retain_log && b.full != "" {
        if b.value == "" {
          b.full
        } else {
          b.full + "\n" + b.value
        }
      } else {
        b.value
      }
      if b.header is None && combined == "" {
        continue
      }
      match b.header {
        Some(h) if h != "" =>
          for hl in h.split("\n") {
            final_lines.push(prefix + self.session.styler.bold(hl))
          }
        _ => ()
      }
      if combined != "" {
        for vl in combined.split("\n") {
          final_lines.push(prefix + self.session.styler.dim(vl))
        }
      }
    }
  }
  if self.is_live_tty() {
    let (raw_cols, _) = self.session.term.size()
    let cols = if raw_cols > 0 { raw_cols } else { 80 }
    let committed = self.renderer.commit(final_lines, cols, sync_output=true)
    self.session.term.write_str(committed)
  } else {
    self.session.term.write_str(final_lines.join("\n") + "\n")
  }
  self.started = false
  self.buffers.clear()
  self.buffers.push({
    header: None,
    value: "",
    full: "",
    result_status: 0,
    result_message: "",
  })
}

///|
pub async fn TaskLog::success(
  self : TaskLog,
  message : StringView,
  show_log~ : Bool = false,
) -> Unit raise @term.TermError {
  self.finish(false, message, show_log)
}

///|
pub async fn TaskLog::error(
  self : TaskLog,
  message : StringView,
  show_log~ : Bool = true,
) -> Unit raise @term.TermError {
  self.finish(true, message, show_log)
}
