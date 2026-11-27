///|
#derive(Debug, Eq)
pub(all) enum SpinnerIndicator {
  Dots
  Timer
}

///|
/// Async spinner with 1:1 Clack frames (`◒ ◐ ◓ ◑`), dynamic width reflow
/// (absorbing upstream #645), keyboard input suppression in TTY mode,
/// accessible mode support, and static single-line degradation in non-TTY / CI.
pub struct Spinner {
  priv session : Session
  priv frames : Array[String]
  priv interval_ms : Int32
  priv indicator : SpinnerIndicator
  priv style_frame : ((String) -> String)?
  priv on_cancel : (() -> Unit)?
  priv renderer : @core.InlineDiffRenderer
  priv mut current_message : String
  priv mut frame_index : Int32
  priv mut dot_step : Int32
  priv mut start_ms : Int64
  priv mut prev_cols : Int32
  priv mut active : Bool
  priv mut cancelled : Bool
}

///|
fn strip_trailing_dots(msg : String) -> String {
  let chars = msg.to_array()
  let mut end = chars.length()
  while end > 0 && chars[end - 1] == '.' {
    end -= 1
  }
  if end == chars.length() {
    msg
  } else {
    String::from_array(chars[:end].to_owned())
  }
}

///|
fn format_elapsed_timer(elapsed_ms : Int64) -> String {
  let total_secs = if elapsed_ms > 0L { elapsed_ms / 1000L } else { 0L }
  let mins = total_secs / 60L
  let secs = total_secs % 60L
  if mins > 0L {
    "[\{mins}m \{secs}s]"
  } else {
    "[\{secs}s]"
  }
}

///|
pub fn Spinner::Spinner(
  session? : Session,
  frames? : Array[String],
  interval_ms? : Int32,
  indicator~ : SpinnerIndicator = Dots,
  show_timer~ : Bool = false,
  style_frame? : (String) -> String,
  on_cancel? : () -> Unit,
) -> Spinner {
  let s = resolve_session(session)
  let default_frames = if s.unicode {
    ["◒", "◐", "◓", "◑"]
  } else {
    ["•", "o", "O", "0"]
  }
  let resolved_frames = match frames {
    Some(f) if !f.is_empty() => f
    _ => default_frames
  }
  let resolved_interval : Int32 = match interval_ms {
    Some(ms) if ms > 0 => ms
    _ => if s.unicode { 80 } else { 120 }
  }
  let resolved_indicator = if show_timer { Timer } else { indicator }
  {
    session: s,
    frames: resolved_frames,
    interval_ms: resolved_interval,
    indicator: resolved_indicator,
    style_frame,
    on_cancel,
    renderer: @core.InlineDiffRenderer(),
    current_message: "",
    frame_index: 0,
    dot_step: 0,
    start_ms: 0L,
    prev_cols: 80,
    active: false,
    cancelled: false,
  }
}

///|
pub fn Spinner::is_cancelled(self : Spinner) -> Bool {
  self.cancelled
}

///|
pub fn Spinner::message(self : Spinner, message : StringView) -> Unit {
  self.current_message = strip_trailing_dots(message.to_owned())
}

///|
fn Spinner::is_animated(self : Spinner) -> Bool {
  self.session.is_interactive() &&
  !self.session.is_ci() &&
  !self.session.accessible
}

///|
fn Spinner::format_frame(self : Spinner, raw_frame : String) -> String {
  match self.style_frame {
    Some(f) => f(raw_frame)
    None => self.session.styler.magenta(raw_frame)
  }
}

///|
fn Spinner::format_active_lines(self : Spinner, cols : Int32) -> Array[String] {
  let frame = self.format_frame(
    self.frames[self.frame_index % self.frames.length()],
  )
  let suffix = match self.indicator {
    Timer => " " + format_elapsed_timer(@async.now() - self.start_ms)
    Dots => {
      let dots_cnt = self.dot_step / 8 % 4
      let buf = StringBuilder()
      for _ in 0..<dots_cnt {
        buf.write_char('.')
      }
      buf.to_string()
    }
  }
  let raw = frame + "  " + self.current_message + suffix
  @ansi.wrap_ansi(raw, cols)
}

///|
/// Render one spinner animation frame using live `term.size()` width (absorbing upstream #645).
pub async fn Spinner::tick(self : Spinner) -> Unit raise @term.TermError {
  if !self.active || !self.is_animated() {
    return
  }
  let (raw_cols, _) = self.session.term.size()
  let cols = if raw_cols > 0 { raw_cols } else { 80 }
  let prefix = if cols != self.prev_cols {
    self.prev_cols = cols
    self.renderer.on_resize()
  } else {
    ""
  }
  let lines = self.format_active_lines(cols)
  let patched = prefix + self.renderer.patch(lines, cols, sync_output=true)
  if patched != "" {
    self.session.term.write_str(patched)
  }
  self.frame_index = (self.frame_index + 1) % self.frames.length()
  self.dot_step = (self.dot_step + 1) % 32
}

///|
pub async fn Spinner::start(
  self : Spinner,
  message : StringView,
) -> Unit raise @term.TermError {
  self.current_message = strip_trailing_dots(message.to_owned())
  self.frame_index = 0
  self.dot_step = 0
  self.start_ms = @async.now()
  self.active = true
  self.cancelled = false
  self.renderer.reset()
  let (raw_cols, _) = self.session.term.size()
  self.prev_cols = if raw_cols > 0 { raw_cols } else { 80 }

  if self.session.accessible {
    if self.current_message != "" {
      self.session.term.write_str(self.current_message + "\n")
    }
    return
  }
  if !self.is_animated() {
    let lead = if self.session.with_guide {
      self.session.styler.gray(if self.session.unicode { "│" } else { "|" }) +
      "\n"
    } else {
      ""
    }
    let sym = self.format_frame(self.frames[0])
    self.session.term.write_str(
      lead + sym + "  " + self.current_message + "...\n",
    )
    return
  }
  if self.session.with_guide {
    let bar = self.session.styler.gray(
      if self.session.unicode {
        "│"
      } else {
        "|"
      },
    )
    self.session.term.write_str("\u{001b}[?25l" + bar + "\n")
  } else {
    self.session.term.write_str("\u{001b}[?25l")
  }
  self.tick()
}

///|
async fn Spinner::finish(
  self : Spinner,
  code : Int32,
  message : StringView?,
  silent : Bool,
) -> Unit nocancel {
  if !self.active {
    return
  }
  self.active = false
  self.cancelled = code == 1
  if self.cancelled {
    match self.on_cancel {
      Some(cb) => cb()
      None => ()
    }
  }
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
  let fallback = if code == 1 {
    self.session.cancel_message
  } else if code == 2 {
    self.session.error_message
  } else if self.session.accessible && self.current_message == "" {
    "Done"
  } else {
    self.current_message
  }
  let final_msg = match message {
    Some(m) => {
      let s = m.to_owned()
      if s == "" {
        fallback
      } else {
        s
      }
    }
    None => fallback
  }
  let timer_tail = match self.indicator {
    Timer => " " + format_elapsed_timer(@async.now() - self.start_ms)
    Dots => ""
  }
  if self.session.accessible {
    self.session.term.write_final(final_msg + timer_tail + "\n") catch {
      _ => ()
    }
    return
  }
  let step_sym = if code == 0 {
    self.session.styler.green(if self.session.unicode { "◇" } else { "o" })
  } else if code == 1 {
    self.session.styler.red(if self.session.unicode { "■" } else { "x" })
  } else {
    self.session.styler.red(if self.session.unicode { "▲" } else { "x" })
  }
  let line = step_sym + "  " + final_msg + timer_tail
  try {
    if self.is_animated() {
      let (raw_cols, _) = self.session.term.size()
      let cols = if raw_cols > 0 { raw_cols } else { 80 }
      let prefix = if cols != self.prev_cols {
        self.renderer.on_resize()
      } else {
        ""
      }
      let committed = prefix +
        self.renderer.commit(
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
pub async fn Spinner::stop(
  self : Spinner,
  message? : StringView,
) -> Unit nocancel {
  self.finish(0, message, false)
}

///|
pub async fn Spinner::cancel(
  self : Spinner,
  message? : StringView,
) -> Unit nocancel {
  self.finish(1, message, false)
}

///|
pub async fn Spinner::fail(
  self : Spinner,
  message? : StringView,
) -> Unit nocancel {
  self.finish(2, message, false)
}

///|
/// Silently stop the spinner and erase its active frame without printing a final status line.
pub async fn Spinner::clear(self : Spinner) -> Unit nocancel {
  self.finish(0, None, true)
}

///|
/// Structured-concurrency spinner wrapper:
/// - In TTY mode: runs live animation + raw-mode keyboard blocking concurrently in a `TaskGroup`,
///   silently consuming stray keypresses and cancelling cleanly on `Ctrl+C` (`0x03`)
/// - In non-TTY / CI / accessible mode: executes `task` directly with static start/end logs
pub async fn[T] with_spinner(
  message : StringView,
  task : async (Spinner) -> T,
  done_message? : StringView,
  error_message? : StringView,
  cancel_message? : StringView,
  indicator~ : SpinnerIndicator = Dots,
  show_timer~ : Bool = false,
  interval_ms? : Int32,
  style_frame? : (String) -> String,
  on_cancel? : () -> Unit,
  session? : Session,
) -> T {
  let s = resolve_session(session)
  let spin = Spinner(
    session=s,
    indicator~,
    show_timer~,
    interval_ms?,
    style_frame?,
    on_cancel?,
  )
  spin.start(message)
  let animated = spin.is_animated()
  if animated {
    s.term.enter_raw_mode() catch {
      _ => ()
    }
  }
  let mut completed_ok = false
  defer {
    if !completed_ok {
      if @async.is_being_cancelled() {
        spin.cancel(message?=cancel_message)
      } else {
        spin.fail(message?=error_message)
      }
    }
    if animated {
      try {
        s.term.write_final("\u{001b}[?25h\u{001b}[?2026l")
        s.term.leave_raw_mode()
      } catch {
        _ => ()
      }
    }
  }
  let result_ref : Ref[T?] = Ref(None)
  if animated {
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, allow_failure=true, () => {
        for ;; {
          @async.sleep(spin.interval_ms)
          spin.tick()
        }
      })
      group.spawn_bg(no_wait=true, allow_failure=true, () => {
        for ;; {
          match s.term.read_bytes() {
            Some(bytes) =>
              for i in 0..<bytes.length() {
                if bytes[i] == b'\x03' {
                  raise @term.TermError::EndOfInput
                }
              }
            None => break
          }
        }
      })
      let value = task(spin)
      result_ref.val = Some(value)
    })
  } else {
    let value = task(spin)
    result_ref.val = Some(value)
  }
  completed_ok = true
  spin.stop(message?=done_message)
  match result_ref.val {
    Some(v) => v
    None => raise @term.TermError::IoFailure("Spinner task produced no result")
  }
}
