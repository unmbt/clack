///|
#derive(Debug, Eq)
pub(all) enum ProgressStyle {
  Light
  Heavy
  Block
}

///|
/// Deterministic progress bar matching upstream `@clack/prompts` styles
/// (`light` `─`, `heavy` `━`, `block` `█`), with static milestone fallback in non-TTY / CI.
pub struct Progress {
  priv session : Session
  priv total : Int32
  priv width : Int32
  priv style : ProgressStyle
  priv renderer : @core.InlineDiffRenderer
  priv mut current : Int32
  priv mut message : String
  priv mut active : Bool
  priv mut cancelled : Bool
  priv mut last_milestone : Int32
}

///|
pub fn Progress::Progress(
  total~ : Int32,
  width~ : Int32 = 40,
  style~ : ProgressStyle = Heavy,
  session? : Session,
) -> Progress {
  let s = resolve_session(session)
  {
    session: s,
    total: if total > 0 {
      total
    } else {
      1
    },
    width: if width > 0 {
      width
    } else {
      40
    },
    style,
    renderer: @core.InlineDiffRenderer(),
    current: 0,
    message: "",
    active: false,
    cancelled: false,
    last_milestone: -1,
  }
}

///|
pub fn Progress::is_cancelled(self : Progress) -> Bool {
  self.cancelled
}

///|
fn Progress::bar_char(self : Progress) -> String {
  match self.style {
    Light => if self.session.unicode { "─" } else { "-" }
    Heavy => if self.session.unicode { "━" } else { "=" }
    Block => if self.session.unicode { "█" } else { "#" }
  }
}

///|
fn repeat_bar(ch : String, count : Int32) -> String {
  if count <= 0 {
    return ""
  }
  let buf = StringBuilder()
  for _ in 0..<count {
    buf.write_string(ch)
  }
  buf.to_string()
}

///|
fn Progress::is_animated(self : Progress) -> Bool {
  self.session.is_interactive() &&
  !self.session.is_ci() &&
  !self.session.accessible
}

///|
fn Progress::percent(self : Progress) -> Int32 {
  let pct = self.current * 100 / self.total
  if pct < 0 {
    0
  } else if pct > 100 {
    100
  } else {
    pct
  }
}

///|
fn Progress::render_bar_line(
  self : Progress,
  status : Int32,
  msg : String,
) -> String {
  let filled = self.current * self.width / self.total
  let clamped_filled = if filled < 0 {
    0
  } else if filled > self.width {
    self.width
  } else {
    filled
  }
  let empty = self.width - clamped_filled
  let ch = self.bar_char()
  let active_str = repeat_bar(ch, clamped_filled)
  let styled_active = if status == 0 {
    self.session.styler.magenta(active_str)
  } else if status == 1 {
    self.session.styler.green(active_str)
  } else {
    self.session.styler.red(active_str)
  }
  let styled_rest = self.session.styler.dim(repeat_bar(ch, empty))
  let sym = if status == 0 {
    self.session.styler.magenta(
      if self.session.unicode {
        "◒"
      } else {
        "•"
      },
    )
  } else if status == 1 {
    self.session.styler.green(if self.session.unicode { "◇" } else { "o" })
  } else if status == 3 {
    self.session.styler.red(if self.session.unicode { "■" } else { "x" })
  } else {
    self.session.styler.red(if self.session.unicode { "▲" } else { "x" })
  }
  let pct = self.percent()
  let tail = if msg != "" { " " + msg } else { "" }
  sym + "  " + styled_active + styled_rest + " \{pct}%" + tail
}

///|
async fn Progress::render_current(
  self : Progress,
) -> Unit raise @term.TermError {
  if !self.active {
    return
  }
  if self.is_animated() {
    let (raw_cols, _) = self.session.term.size()
    let cols = if raw_cols > 0 { raw_cols } else { 80 }
    let line = self.render_bar_line(0, self.message)
    let patched = self.renderer.patch(
      @ansi.wrap_ansi(line, cols),
      cols,
      sync_output=true,
    )
    if patched != "" {
      self.session.term.write_str(patched)
    }
  } else {
    let pct = self.percent()
    let milestone = pct / 25 * 25
    if milestone > self.last_milestone {
      self.last_milestone = milestone
      let line = self.render_bar_line(0, self.message)
      self.session.term.write_str(line + "\n")
    }
  }
}

///|
pub async fn Progress::start(
  self : Progress,
  message~ : StringView = "",
) -> Unit raise @term.TermError {
  self.current = 0
  self.message = message.to_owned()
  self.active = true
  self.cancelled = false
  self.last_milestone = -1
  self.renderer.reset()
  if self.session.with_guide {
    let bar = self.session.styler.gray(
      if self.session.unicode {
        "│"
      } else {
        "|"
      },
    )
    if self.is_animated() {
      self.session.term.write_str("\u{001b}[?25l" + bar + "\n")
    } else {
      self.session.term.write_str(bar + "\n")
    }
  } else if self.is_animated() {
    self.session.term.write_str("\u{001b}[?25l")
  }
  self.render_current()
}

///|
pub async fn Progress::advance(
  self : Progress,
  delta~ : Int32 = 1,
  message? : StringView,
) -> Unit raise @term.TermError {
  let next = self.current + delta
  self.current = if next > self.total {
    self.total
  } else if next < 0 {
    0
  } else {
    next
  }
  match message {
    Some(m) => self.message = m.to_owned()
    None => ()
  }
  self.render_current()
}

///|
pub async fn Progress::message(
  self : Progress,
  msg : StringView,
) -> Unit raise @term.TermError {
  self.advance(delta=0, message=msg)
}

///|
pub async fn Progress::set(
  self : Progress,
  value : Int32,
  message? : StringView,
) -> Unit raise @term.TermError {
  self.current = if value > self.total {
    self.total
  } else if value < 0 {
    0
  } else {
    value
  }
  match message {
    Some(m) => self.message = m.to_owned()
    None => ()
  }
  self.render_current()
}

///|
async fn Progress::finish(
  self : Progress,
  status : Int32,
  message : StringView?,
  silent : Bool,
) -> Unit nocancel {
  if !self.active {
    return
  }
  self.active = false
  self.cancelled = status == 3
  if silent {
    try {
      if self.is_animated() {
        let clear_seq = self.renderer.on_resize()
        self.session.term.write_final(
          clear_seq + "\u{001b}[?25h\u{001b}[?2026l",
        )
      }
    } catch {
      _ => ()
    }
    return
  }
  if status == 1 {
    self.current = self.total
  }
  let msg = match message {
    Some(m) => m.to_owned()
    None => if status == 3 { self.session.cancel_message } else { self.message }
  }
  let line = self.render_bar_line(status, msg)
  try {
    if self.is_animated() {
      let (raw_cols, _) = self.session.term.size()
      let cols = if raw_cols > 0 { raw_cols } else { 80 }
      let committed = self.renderer.commit(
        @ansi.wrap_ansi(line, cols),
        cols,
        sync_output=true,
      )
      self.session.term.write_final(committed + "\u{001b}[?25h\u{001b}[?2026l")
    } else {
      self.session.term.write_final(line + "\n")
    }
  } catch {
    _ => ()
  }
}

///|
pub async fn Progress::stop(
  self : Progress,
  message? : StringView,
) -> Unit nocancel {
  self.finish(1, message, false)
}

///|
pub async fn Progress::fail(
  self : Progress,
  message? : StringView,
) -> Unit nocancel {
  self.finish(2, message, false)
}

///|
pub async fn Progress::cancel(
  self : Progress,
  message? : StringView,
) -> Unit nocancel {
  self.finish(3, message, false)
}

///|
pub async fn Progress::clear(self : Progress) -> Unit nocancel {
  self.finish(1, None, true)
}
