///|
pub fn[T] SelectKeyOption::SelectKeyOption(
  key : String,
  value : T,
  label : String,
  hint? : String,
  disabled~ : Bool = false,
) -> SelectKeyOption[T] {
  { key, value, label, hint, disabled, }
}

///|
/// Headless single-key instant selection prompt (1:1 upstream `@clack/prompts` `selectKey`).
pub struct SelectKeyModel[T] {
  priv message : String
  priv options : Array[SelectKeyOption[T]]
  priv case_sensitive : Bool
  priv mut cursor : Int32
  priv all_disabled : Bool
  priv mut phase : PromptPhase
  priv with_guide : Bool
}

///|
fn[T] find_enabled_key_cursor(
  options : Array[SelectKeyOption[T]],
  start : Int32,
  delta : Int32,
) -> Int32? {
  let len = options.length()
  if len == 0 {
    return None
  }
  let mut idx = if start < 0 {
    0
  } else if start >= len {
    len - 1
  } else {
    start
  }
  if delta == 0 {
    if !options[idx].disabled {
      return Some(idx)
    }
    for step in 1..<len {
      let cand = (idx + step) % len
      if !options[cand].disabled {
        return Some(cand)
      }
    }
    return None
  }
  for _ in 0..<len {
    idx = (idx + delta + len) % len
    if !options[idx].disabled {
      return Some(idx)
    }
  }
  None
}

///|
pub fn[T] SelectKeyModel::SelectKeyModel(
  message : String,
  options : Array[SelectKeyOption[T]],
  initial_index~ : Int32 = 0,
  case_sensitive~ : Bool = false,
  with_guide~ : Bool = true,
) -> SelectKeyModel[T] {
  match find_enabled_key_cursor(options, initial_index, 0) {
    Some(cur) =>
      {
        message,
        options,
        case_sensitive,
        cursor: cur,
        all_disabled: false,
        phase: Initial,
        with_guide,
      }
    None =>
      {
        message,
        options,
        case_sensitive,
        cursor: 0,
        all_disabled: true,
        phase: Error("No selectable options available"),
        with_guide,
      }
  }
}

///|
pub fn[T] SelectKeyModel::cursor(self : SelectKeyModel[T]) -> Int32 {
  self.cursor
}

///|
pub fn[T] SelectKeyModel::on_key(
  self : SelectKeyModel[T],
  event : KeyEvent,
  allow_back~ : Bool = false,
) -> PromptOutcome[T]? {
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
  if self.all_disabled {
    return None
  }
  if self.phase is (Initial | Warning(_) | Error(_)) {
    self.phase = Active
  }
  match event.code {
    Char(ch) if !event.ctrl && !event.alt => {
      let pressed = ch.to_string()
      let cmp_pressed = if self.case_sensitive {
        pressed
      } else {
        pressed.to_lower()
      }
      for i in 0..<self.options.length() {
        let opt = self.options[i]
        if opt.disabled {
          continue
        }
        let target = if self.case_sensitive {
          opt.key
        } else {
          opt.key.to_lower()
        }
        if target == cmp_pressed {
          self.cursor = i
          self.phase = Submitted
          return Some(Submitted(opt.value))
        }
      }
    }
    Up | Left =>
      match find_enabled_key_cursor(self.options, self.cursor, -1) {
        Some(next) => self.cursor = next
        None => ()
      }
    Down | Right =>
      match find_enabled_key_cursor(self.options, self.cursor, 1) {
        Some(next) => self.cursor = next
        None => ()
      }
    Enter => {
      self.phase = Submitted
      return Some(Submitted(self.options[self.cursor].value))
    }
    _ => ()
  }
  None
}

///|
pub fn[T] SelectKeyModel::view(self : SelectKeyModel[T]) -> FrameSpec {
  let items : Array[SelectKeyRowView] = []
  for i in 0..<self.options.length() {
    let opt = self.options[i]
    items.push({
      key: opt.key,
      label: opt.label,
      hint: opt.hint,
      is_cursor: !self.all_disabled && i == self.cursor,
      is_disabled: opt.disabled,
    })
  }
  let summary : String? = if !self.all_disabled &&
    self.cursor >= 0 &&
    self.cursor < self.options.length() {
    match self.phase {
      Submitted | Cancelled => Some(self.options[self.cursor].label)
      _ => None
    }
  } else {
    None
  }
  {
    phase: self.phase,
    message: self.message,
    body: SelectKeyList(items~),
    submitted_summary: summary,
    with_guide: self.with_guide,
    max_rows: None,
  }
}

///|
pub fn[T] SelectKeyModel::as_adapter(
  self : SelectKeyModel[T],
) -> PromptAdapter[T] {
  PromptAdapter(on_key=fn(ev, allow_back) { self.on_key(ev, allow_back~) }, view=fn() {
    self.view()
  })
}
