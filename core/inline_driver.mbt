///|
pub fn[T] InlineDriver::InlineDriver(
  adapter : PromptAdapter[T],
  theme~ : &Theme = ClackTheme(),
  styler~ : @ansi.Styler = @ansi.Styler(),
  cols~ : Int32 = 80,
  rows~ : Int32 = 24,
  allow_back~ : Bool = false,
  sync_output~ : Bool = true,
) -> InlineDriver[T] {
  {
    adapter,
    theme,
    styler,
    renderer: InlineDiffRenderer(),
    decoder: KeyDecoder(),
    allow_back,
    sync_output,
    cols: if cols > 0 {
      cols
    } else {
      80
    },
    rows: if rows > 0 {
      rows
    } else {
      24
    },
    finished: false,
  }
}

///|
fn[T] InlineDriver::render_frame_lines(self : InlineDriver[T]) -> Array[String] {
  let spec = (self.adapter.view)()
  let spec_with_rows = match spec.max_rows {
    Some(_) => spec
    None => { ..spec, max_rows: Some(self.rows), }
  }
  self.theme.render_frame(spec_with_rows, self.styler, self.cols)
}

///|
pub fn[T] InlineDriver::start(self : InlineDriver[T]) -> String {
  if self.finished {
    return ""
  }
  let lines = self.render_frame_lines()
  self.renderer.patch(lines, self.cols, sync_output=self.sync_output)
}

///|
fn[T] InlineDriver::process_events(
  self : InlineDriver[T],
  events : Array[KeyEvent],
) -> (String, PromptOutcome[T]?) {
  if self.finished || events.is_empty() {
    return ("", None)
  }
  let mut outcome : PromptOutcome[T]? = None
  for ev in events {
    match (self.adapter.on_key)(ev, self.allow_back) {
      Some(res) => {
        outcome = Some(res)
        break
      }
      None => ()
    }
  }
  let lines = self.render_frame_lines()
  match outcome {
    Some(res) => {
      self.finished = true
      let out = self.renderer.commit(
        lines,
        self.cols,
        sync_output=self.sync_output,
      )
      (out, Some(res))
    }
    None => {
      let out = self.renderer.patch(
        lines,
        self.cols,
        sync_output=self.sync_output,
      )
      (out, None)
    }
  }
}

///|
pub fn[T] InlineDriver::feed(
  self : InlineDriver[T],
  chunk : BytesView,
) -> (String, PromptOutcome[T]?) {
  if self.finished {
    return ("", None)
  }
  let events = self.decoder.feed(chunk)
  self.process_events(events)
}

///|
pub fn[T] InlineDriver::flush_escape(
  self : InlineDriver[T],
) -> (String, PromptOutcome[T]?) {
  if self.finished {
    return ("", None)
  }
  match self.decoder.flush_escape() {
    Some(ev) => self.process_events([ev])
    None => ("", None)
  }
}

///|
pub fn[T] InlineDriver::resize(
  self : InlineDriver[T],
  cols : Int32,
  rows : Int32,
) -> String {
  self.cols = if cols > 0 { cols } else { 1 }
  self.rows = if rows > 0 { rows } else { 1 }
  if self.finished {
    return ""
  }
  let clear = self.renderer.on_resize()
  let lines = self.render_frame_lines()
  clear + self.renderer.patch(lines, self.cols, sync_output=self.sync_output)
}

///|
pub fn[T] InlineDriver::has_pending_escape(self : InlineDriver[T]) -> Bool {
  self.decoder.has_pending_escape()
}
