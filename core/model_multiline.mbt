///|
fn sanitize_paste_multiline(raw : String) -> String {
  let chars = raw.to_array()
  let buf = StringBuilder()
  let mut i : Int32 = 0
  while i < chars.length() {
    let ch = chars[i]
    if ch == '\r' {
      buf.write_char('\n')
      if i + 1 < chars.length() && chars[i + 1] == '\n' {
        i += 2
      } else {
        i += 1
      }
      continue
    }
    if ch == '\n' || ch == '\t' {
      buf.write_char(ch)
    } else if ch <= '\u{001f}' || (ch >= '\u{007f}' && ch <= '\u{009f}') {
      ()
    } else {
      buf.write_char(ch)
    }
    i += 1
  }
  buf.to_string()
}

///|
/// Headless multi-line text prompt state machine (1:1 upstream `MultiLinePrompt`):
/// - Stores Unicode scalars (`Array[Char]`), keeping astral emoji/CJK intact (upstream #641)
/// - Filters control chars (upstream #638)
/// - Submits on double Enter (`show_submit=false`) or via Tab-focused `[ submit ]` (`show_submit=true`)
pub struct MultiLineModel {
  priv message : String
  priv placeholder : String?
  priv default_value : String?
  priv show_submit : Bool
  priv mut chars : Array[Char]
  priv mut cursor : Int32
  priv mut submit_focused : Bool
  priv validate : ((String) -> String?)?
  priv mut phase : PromptPhase
  priv with_guide : Bool
  priv mut final_value : String
}

///|
pub fn MultiLineModel::MultiLineModel(
  message : String,
  placeholder? : String,
  default_value? : String,
  initial_value~ : String = "",
  show_submit~ : Bool = false,
  validate? : (String) -> String?,
  with_guide~ : Bool = true,
) -> MultiLineModel {
  let chars = initial_value.to_array()
  {
    message,
    placeholder,
    default_value,
    show_submit,
    chars,
    cursor: chars.length(),
    submit_focused: false,
    validate,
    phase: Initial,
    with_guide,
    final_value: "",
  }
}

///|
pub fn MultiLineModel::value(self : MultiLineModel) -> String {
  String::from_array(self.chars)
}

///|
pub fn MultiLineModel::set_phase(
  self : MultiLineModel,
  phase : PromptPhase,
) -> Unit {
  self.phase = phase
}

///|
fn split_lines_and_cursor(
  chars : Array[Char],
  cursor : Int32,
) -> (Array[String], Int32, Int32) {
  let lines : Array[String] = []
  let buf = StringBuilder()
  let mut cur_line : Int32 = 0
  let mut cur_col : Int32 = 0
  let mut line_idx : Int32 = 0
  let mut col_idx : Int32 = 0
  for i in 0..<chars.length() {
    if i == cursor {
      cur_line = line_idx
      cur_col = col_idx
    }
    if chars[i] == '\n' {
      lines.push(buf.to_string())
      buf.reset()
      line_idx += 1
      col_idx = 0
    } else {
      buf.write_char(chars[i])
      col_idx += 1
    }
  }
  if cursor >= chars.length() {
    cur_line = line_idx
    cur_col = col_idx
  }
  lines.push(buf.to_string())
  (lines, cur_line, cur_col)
}

///|
fn line_col_to_index(
  chars : Array[Char],
  target_line : Int32,
  target_col : Int32,
) -> Int32 {
  let mut line : Int32 = 0
  let mut col : Int32 = 0
  for i in 0..<chars.length() {
    if line == target_line && col == target_col {
      return i
    }
    if chars[i] == '\n' {
      if line == target_line {
        return i
      }
      line += 1
      col = 0
    } else {
      col += 1
    }
  }
  chars.length()
}

///|
fn MultiLineModel::try_submit(
  self : MultiLineModel,
  raw : String,
) -> PromptOutcome[String]? {
  let effective = if raw == "" {
    match self.default_value {
      Some(d) => d
      None => ""
    }
  } else {
    raw
  }
  match self.validate {
    Some(vfn) =>
      match vfn(effective) {
        Some(err_msg) => {
          self.phase = Error(err_msg)
          return None
        }
        None => ()
      }
    None => ()
  }
  self.final_value = effective
  self.phase = Submitted
  Some(Submitted(effective))
}

///|
pub fn MultiLineModel::on_key(
  self : MultiLineModel,
  event : KeyEvent,
  allow_back~ : Bool = false,
) -> PromptOutcome[String]? {
  if is_cancel_event(event) {
    self.phase = Cancelled
    return Some(Cancelled)
  }
  if is_back_event(event, allow_back) {
    self.phase = Reverted
    return Some(StepBack)
  }
  if event.code == Escape {
    self.phase = Cancelled
    return Some(Cancelled)
  }
  if self.phase is (Error(_) | Warning(_) | Initial) {
    self.phase = Active
  }
  match event.code {
    Tab =>
      if self.show_submit {
        self.submit_focused = !self.submit_focused
      } else if self.chars.is_empty() {
        let fill = match self.placeholder {
          Some(ph) if ph != "" => Some(ph)
          _ => self.default_value
        }
        match fill {
          Some(s) if s != "" => {
            self.chars = s.to_array()
            self.cursor = self.chars.length()
          }
          _ => ()
        }
      }
    Enter => {
      if self.show_submit && self.submit_focused {
        return self.try_submit(self.value())
      }
      // Double-Enter submits when show_submit == false
      if !self.show_submit &&
        self.cursor == self.chars.length() &&
        self.cursor > 0 &&
        self.chars[self.cursor - 1] == '\n' {
        let trimmed = String::from_array(
          self.chars[:self.cursor - 1].to_owned(),
        )
        return self.try_submit(trimmed)
      }
      if !self.show_submit && self.chars.is_empty() {
        return self.try_submit("")
      }
      self.submit_focused = false
      let (next_chars, next_cur) = insert_chars_at(self.chars, self.cursor, [
        '\n',
      ])
      self.chars = next_chars
      self.cursor = next_cur
    }
    Left => {
      self.submit_focused = false
      if self.cursor > 0 {
        self.cursor -= 1
      }
    }
    Right => {
      self.submit_focused = false
      if self.cursor < self.chars.length() {
        self.cursor += 1
      }
    }
    Up => {
      self.submit_focused = false
      let (_, cl, cc) = split_lines_and_cursor(self.chars, self.cursor)
      if cl > 0 {
        self.cursor = line_col_to_index(self.chars, cl - 1, cc)
      }
    }
    Down => {
      self.submit_focused = false
      let (lines, cl, cc) = split_lines_and_cursor(self.chars, self.cursor)
      if cl + 1 < lines.length() {
        self.cursor = line_col_to_index(self.chars, cl + 1, cc)
      }
    }
    Home => {
      self.submit_focused = false
      let (_, cl, _) = split_lines_and_cursor(self.chars, self.cursor)
      self.cursor = line_col_to_index(self.chars, cl, 0)
    }
    End => {
      self.submit_focused = false
      let (lines, cl, _) = split_lines_and_cursor(self.chars, self.cursor)
      let line_len = lines[cl].to_array().length()
      self.cursor = line_col_to_index(self.chars, cl, line_len)
    }
    Backspace => {
      self.submit_focused = false
      if self.cursor > 0 {
        self.chars = delete_char_at(self.chars, self.cursor - 1)
        self.cursor -= 1
      }
    }
    Delete => {
      self.submit_focused = false
      if self.cursor < self.chars.length() {
        self.chars = delete_char_at(self.chars, self.cursor)
      }
    }
    Space => {
      self.submit_focused = false
      let (next_chars, next_cur) = insert_chars_at(self.chars, self.cursor, [
        ' ',
      ])
      self.chars = next_chars
      self.cursor = next_cur
    }
    Char(ch) if !event.ctrl && !event.alt =>
      if ch >= ' ' {
        self.submit_focused = false
        let (next_chars, next_cur) = insert_chars_at(self.chars, self.cursor, [
          ch,
        ])
        self.chars = next_chars
        self.cursor = next_cur
      }
    Paste(raw) => {
      self.submit_focused = false
      let cleaned = sanitize_paste_multiline(raw).to_array()
      if !cleaned.is_empty() {
        let (next_chars, next_cur) = insert_chars_at(
          self.chars,
          self.cursor,
          cleaned,
        )
        self.chars = next_chars
        self.cursor = next_cur
      }
    }
    _ => ()
  }
  None
}

///|
pub fn MultiLineModel::view(self : MultiLineModel) -> FrameSpec {
  let (lines, cursor_line, cursor_col) = split_lines_and_cursor(
    self.chars,
    self.cursor,
  )
  let summary = match self.phase {
    Submitted => Some(self.final_value)
    Cancelled => Some(self.value())
    _ => None
  }
  {
    phase: self.phase,
    message: self.message,
    body: MultiLineInput(
      lines~,
      cursor_line~,
      cursor_col~,
      placeholder=self.placeholder,
      is_empty=self.chars.is_empty(),
      show_submit=self.show_submit,
      submit_focused=self.submit_focused,
    ),
    submitted_summary: summary,
    with_guide: self.with_guide,
    max_rows: None,
  }
}

///|
pub fn MultiLineModel::as_adapter(
  self : MultiLineModel,
) -> PromptAdapter[String] {
  PromptAdapter(on_key=fn(ev, allow_back) { self.on_key(ev, allow_back~) }, view=fn() {
    self.view()
  })
}
