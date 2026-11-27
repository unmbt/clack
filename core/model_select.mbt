///|
fn[T] find_enabled_cursor(
  options : Array[SelectOption[T]],
  start : Int32,
  delta : Int32,
) -> Int32? {
  let len = options.length()
  if len == 0 {
    return None
  }
  let mut idx = start
  if idx < 0 {
    idx = 0
  } else if idx >= len {
    idx = len - 1
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
/// Headless single-select prompt state machine with disabled-item skipping.
pub struct SelectModel[T] {
  priv message : String
  priv options : Array[SelectOption[T]]
  priv mut cursor : Int32
  priv all_disabled : Bool
  priv max_items : Int32?
  priv show_instructions : Bool
  priv mut phase : PromptPhase
  priv with_guide : Bool
}

///|
pub fn[T] SelectModel::SelectModel(
  message : String,
  options : Array[SelectOption[T]],
  initial_index~ : Int32 = 0,
  max_items? : Int32,
  show_instructions~ : Bool = true,
  with_guide~ : Bool = true,
) -> SelectModel[T] {
  match find_enabled_cursor(options, initial_index, 0) {
    Some(cur) =>
      {
        message,
        options,
        cursor: cur,
        all_disabled: false,
        max_items,
        show_instructions,
        phase: Initial,
        with_guide,
      }
    None =>
      {
        message,
        options,
        cursor: 0,
        all_disabled: true,
        max_items,
        show_instructions,
        phase: Error("No selectable options available"),
        with_guide,
      }
  }
}

///|
pub fn[T] SelectModel::cursor(self : SelectModel[T]) -> Int32 {
  self.cursor
}

///|
pub fn[T] SelectModel::has_selectable_options(self : SelectModel[T]) -> Bool {
  !self.all_disabled
}

///|
pub fn[T] SelectModel::on_key(
  self : SelectModel[T],
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
    self.phase = Error("No selectable options available")
    return None
  }
  if self.phase is (Initial | Warning(_) | Error(_)) {
    self.phase = Active
  }
  match event.code {
    Up | Left =>
      match find_enabled_cursor(self.options, self.cursor, -1) {
        Some(next) => self.cursor = next
        None => ()
      }
    Down | Right =>
      match find_enabled_cursor(self.options, self.cursor, 1) {
        Some(next) => self.cursor = next
        None => ()
      }
    Char('k') | Char('h') =>
      if !event.ctrl && !event.alt {
        match find_enabled_cursor(self.options, self.cursor, -1) {
          Some(next) => self.cursor = next
          None => ()
        }
      }
    Char('j') | Char('l') =>
      if !event.ctrl && !event.alt {
        match find_enabled_cursor(self.options, self.cursor, 1) {
          Some(next) => self.cursor = next
          None => ()
        }
      }
    Home =>
      match find_enabled_cursor(self.options, 0, 0) {
        Some(first) => self.cursor = first
        None => ()
      }
    End => {
      let last = self.options.length() - 1
      match find_enabled_cursor(self.options, last, 0) {
        Some(idx) => self.cursor = idx
        None => ()
      }
    }
    Enter => {
      self.phase = Submitted
      return Some(Submitted(self.options[self.cursor].value))
    }
    Paste(_) => ()
    _ => ()
  }
  None
}

///|
pub fn[T] SelectModel::view(self : SelectModel[T]) -> FrameSpec {
  let items : Array[OptionRowView] = []
  for i in 0..<self.options.length() {
    let opt = self.options[i]
    items.push({
      label: opt.label,
      hint: opt.hint,
      is_cursor: !self.all_disabled && i == self.cursor,
      is_selected: false,
      is_disabled: opt.disabled,
      is_multi: false,
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
    body: OptionList(
      items~,
      cursor=self.cursor,
      max_items=self.max_items,
      total_count=self.options.length(),
      total_unfiltered=self.options.length(),
      filter_query=None,
      filter_cursor=0,
      filter_placeholder=None,
      is_navigating=false,
      complete_on_tab=false,
      show_instructions=self.show_instructions,
      is_multi=false,
    ),
    submitted_summary: summary,
    with_guide: self.with_guide,
    max_rows: None,
  }
}

///|
pub fn[T] SelectModel::as_adapter(self : SelectModel[T]) -> PromptAdapter[T] {
  PromptAdapter(on_key=fn(ev, allow_back) { self.on_key(ev, allow_back~) }, view=fn() {
    self.view()
  })
}
