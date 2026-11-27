///|
fn insert_chars_at(
  chars : Array[Char],
  cursor : Int32,
  inserted : Array[Char],
) -> (Array[Char], Int32) {
  let out : Array[Char] = []
  for i in 0..<cursor {
    out.push(chars[i])
  }
  for ch in inserted {
    out.push(ch)
  }
  for i in cursor..<chars.length() {
    out.push(chars[i])
  }
  (out, cursor + inserted.length())
}

///|
fn delete_char_at(chars : Array[Char], idx : Int32) -> Array[Char] {
  let out : Array[Char] = []
  for i in 0..<chars.length() {
    if i != idx {
      out.push(chars[i])
    }
  }
  out
}

///|
/// Headless single-line text input prompt state machine.
pub struct TextModel {
  priv message : String
  priv placeholder : String?
  priv default_value : String?
  priv mut chars : Array[Char]
  priv mut cursor : Int32
  priv validate : ((String) -> String?)?
  priv mut phase : PromptPhase
  priv with_guide : Bool
  priv mut final_value : String
}

///|
pub fn TextModel::TextModel(
  message : String,
  placeholder? : String,
  default_value? : String,
  initial_value~ : String = "",
  validate? : (String) -> String?,
  with_guide~ : Bool = true,
) -> TextModel {
  let chars = initial_value.to_array()
  {
    message,
    placeholder,
    default_value,
    chars,
    cursor: chars.length(),
    validate,
    phase: Initial,
    with_guide,
    final_value: "",
  }
}

///|
pub fn TextModel::value(self : TextModel) -> String {
  String::from_array(self.chars)
}

///|
pub fn TextModel::cursor(self : TextModel) -> Int32 {
  self.cursor
}

///|
pub fn TextModel::set_phase(self : TextModel, phase : PromptPhase) -> Unit {
  self.phase = phase
}

///|
pub fn TextModel::on_key(
  self : TextModel,
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
    Left => if self.cursor > 0 { self.cursor -= 1 }
    Right => if self.cursor < self.chars.length() { self.cursor += 1 }
    Home => self.cursor = 0
    End => self.cursor = self.chars.length()
    Backspace =>
      if self.cursor > 0 {
        self.chars = delete_char_at(self.chars, self.cursor - 1)
        self.cursor -= 1
      }
    Delete =>
      if self.cursor < self.chars.length() {
        self.chars = delete_char_at(self.chars, self.cursor)
      }
    Tab =>
      if self.chars.is_empty() {
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
    Space => {
      let (next_chars, next_cur) = insert_chars_at(self.chars, self.cursor, [
        ' ',
      ])
      self.chars = next_chars
      self.cursor = next_cur
    }
    Char(ch) =>
      if !event.ctrl && !event.alt {
        let (next_chars, next_cur) = insert_chars_at(self.chars, self.cursor, [
          ch,
        ])
        self.chars = next_chars
        self.cursor = next_cur
      }
    Paste(raw) => {
      let cleaned = sanitize_paste_single_line(raw)
      let inserted = cleaned.to_array()
      if !inserted.is_empty() {
        let (next_chars, next_cur) = insert_chars_at(
          self.chars,
          self.cursor,
          inserted,
        )
        self.chars = next_chars
        self.cursor = next_cur
      }
    }
    Enter => {
      let raw = self.value()
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
      return Some(Submitted(effective))
    }
    _ => ()
  }
  None
}

///|
pub fn TextModel::view(self : TextModel) -> FrameSpec {
  let text = self.value()
  let summary = match self.phase {
    Submitted => Some(self.final_value)
    Cancelled => Some(text)
    _ => None
  }
  {
    phase: self.phase,
    message: self.message,
    body: TextInput(
      rendered_value=text,
      cursor_pos=self.cursor,
      placeholder=self.placeholder,
      is_empty=self.chars.is_empty(),
      is_password=false,
      raw_text=text,
    ),
    submitted_summary: summary,
    with_guide: self.with_guide,
    max_rows: None,
  }
}

///|
pub fn TextModel::as_adapter(self : TextModel) -> PromptAdapter[String] {
  PromptAdapter(on_key=fn(ev, allow_back) { self.on_key(ev, allow_back~) }, view=fn() {
    self.view()
  })
}

///|
/// Headless masked/hidden password input prompt state machine.
pub struct PasswordModel {
  priv message : String
  priv mask : Char?
  priv clear_on_error : Bool
  priv mut chars : Array[Char]
  priv mut cursor : Int32
  priv validate : ((String) -> String?)?
  priv mut phase : PromptPhase
  priv with_guide : Bool
}

///|
pub fn PasswordModel::PasswordModel(
  message : String,
  mask~ : Char? = Some('▪'),
  clear_on_error~ : Bool = false,
  validate? : (String) -> String?,
  with_guide~ : Bool = true,
) -> PasswordModel {
  {
    message,
    mask,
    clear_on_error,
    chars: [],
    cursor: 0,
    validate,
    phase: Initial,
    with_guide,
  }
}

///|
pub fn PasswordModel::value(self : PasswordModel) -> String {
  String::from_array(self.chars)
}

///|
pub fn PasswordModel::set_phase(
  self : PasswordModel,
  phase : PromptPhase,
) -> Unit {
  self.phase = phase
}

///|
pub fn PasswordModel::masked(self : PasswordModel) -> String {
  match self.mask {
    None => ""
    Some(ch) => {
      let buf = StringBuilder()
      for _ in 0..<self.chars.length() {
        buf.write_char(ch)
      }
      buf.to_string()
    }
  }
}

///|
pub fn PasswordModel::on_key(
  self : PasswordModel,
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
    Left => if self.cursor > 0 { self.cursor -= 1 }
    Right => if self.cursor < self.chars.length() { self.cursor += 1 }
    Home => self.cursor = 0
    End => self.cursor = self.chars.length()
    Backspace =>
      if self.cursor > 0 {
        self.chars = delete_char_at(self.chars, self.cursor - 1)
        self.cursor -= 1
      }
    Delete =>
      if self.cursor < self.chars.length() {
        self.chars = delete_char_at(self.chars, self.cursor)
      }
    Space => {
      let (next_chars, next_cur) = insert_chars_at(self.chars, self.cursor, [
        ' ',
      ])
      self.chars = next_chars
      self.cursor = next_cur
    }
    Char(ch) =>
      if !event.ctrl && !event.alt {
        let (next_chars, next_cur) = insert_chars_at(self.chars, self.cursor, [
          ch,
        ])
        self.chars = next_chars
        self.cursor = next_cur
      }
    Paste(raw) => {
      let cleaned = sanitize_paste_password(raw)
      let inserted = cleaned.to_array()
      if !inserted.is_empty() {
        let (next_chars, next_cur) = insert_chars_at(
          self.chars,
          self.cursor,
          inserted,
        )
        self.chars = next_chars
        self.cursor = next_cur
      }
    }
    Enter => {
      let val = self.value()
      match self.validate {
        Some(vfn) =>
          match vfn(val) {
            Some(err_msg) => {
              self.phase = Error(err_msg)
              if self.clear_on_error {
                self.chars = []
                self.cursor = 0
              }
              return None
            }
            None => ()
          }
        None => ()
      }
      self.phase = Submitted
      return Some(Submitted(val))
    }
    _ => ()
  }
  None
}

///|
pub fn PasswordModel::view(self : PasswordModel) -> FrameSpec {
  let masked_str = self.masked()
  let masked_cur : Int32 = match self.mask {
    None => 0
    Some(_) => self.cursor
  }
  let summary = match self.phase {
    Submitted | Cancelled => Some(masked_str)
    _ => None
  }
  {
    phase: self.phase,
    message: self.message,
    body: TextInput(
      rendered_value=masked_str,
      cursor_pos=masked_cur,
      placeholder=None,
      is_empty=self.chars.is_empty(),
      is_password=true,
      raw_text=masked_str,
    ),
    submitted_summary: summary,
    with_guide: self.with_guide,
    max_rows: None,
  }
}

///|
pub fn PasswordModel::as_adapter(self : PasswordModel) -> PromptAdapter[String] {
  PromptAdapter(on_key=fn(ev, allow_back) { self.on_key(ev, allow_back~) }, view=fn() {
    self.view()
  })
}
