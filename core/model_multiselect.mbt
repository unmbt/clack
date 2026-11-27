///|
/// Headless multi-select prompt state machine with Space/a/i/required validation.
pub struct MultiSelectModel[T] {
  priv message : String
  priv options : Array[SelectOption[T]]
  priv selected : Array[Bool]
  priv mut cursor : Int32
  priv all_disabled : Bool
  priv required : Bool
  priv max_items : Int32?
  priv show_instructions : Bool
  priv mut phase : PromptPhase
  priv with_guide : Bool
}

///|
pub fn[T] MultiSelectModel::MultiSelectModel(
  message : String,
  options : Array[SelectOption[T]],
  initial_indices~ : Array[Int32] = [],
  required~ : Bool = true,
  max_items? : Int32,
  show_instructions~ : Bool = true,
  with_guide~ : Bool = true,
) -> MultiSelectModel[T] {
  let selected = Array::make(options.length(), false)
  for idx in initial_indices {
    if idx >= 0 && idx < options.length() && !options[idx].disabled {
      selected[idx] = true
    }
  }
  match find_enabled_cursor(options, 0, 0) {
    Some(cur) =>
      {
        message,
        options,
        selected,
        cursor: cur,
        all_disabled: false,
        required,
        max_items,
        show_instructions,
        phase: Initial,
        with_guide,
      }
    None =>
      {
        message,
        options,
        selected,
        cursor: 0,
        all_disabled: true,
        required,
        max_items,
        show_instructions,
        phase: Error("No selectable options available"),
        with_guide,
      }
  }
}

///|
pub fn[T] MultiSelectModel::cursor(self : MultiSelectModel[T]) -> Int32 {
  self.cursor
}

///|
pub fn[T] MultiSelectModel::selected_indices(
  self : MultiSelectModel[T],
) -> Array[Int32] {
  let out : Array[Int32] = []
  for i in 0..<self.selected.length() {
    if self.selected[i] {
      out.push(i)
    }
  }
  out
}

///|
fn[T] MultiSelectModel::toggle_current(self : MultiSelectModel[T]) -> Unit {
  if !self.all_disabled && !self.options[self.cursor].disabled {
    self.selected[self.cursor] = !self.selected[self.cursor]
  }
}

///|
fn[T] MultiSelectModel::toggle_all(self : MultiSelectModel[T]) -> Unit {
  let mut enabled_count : Int32 = 0
  let mut selected_enabled : Int32 = 0
  for i in 0..<self.options.length() {
    if !self.options[i].disabled {
      enabled_count += 1
      if self.selected[i] {
        selected_enabled += 1
      }
    }
  }
  let target = selected_enabled < enabled_count
  for i in 0..<self.options.length() {
    if !self.options[i].disabled {
      self.selected[i] = target
    }
  }
}

///|
fn[T] MultiSelectModel::toggle_invert(self : MultiSelectModel[T]) -> Unit {
  for i in 0..<self.options.length() {
    if !self.options[i].disabled {
      self.selected[i] = !self.selected[i]
    }
  }
}

///|
pub fn[T] MultiSelectModel::on_key(
  self : MultiSelectModel[T],
  event : KeyEvent,
  allow_back~ : Bool = false,
) -> PromptOutcome[Array[T]]? {
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
    if event.code == Enter && !self.required {
      self.phase = Submitted
      return Some(Submitted([]))
    }
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
    Space => self.toggle_current()
    Char(ch) if is_ideographic_space(ch) => self.toggle_current()
    Char('a') | Char('A') => if !event.ctrl && !event.alt { self.toggle_all() }
    Char('i') | Char('I') =>
      if !event.ctrl && !event.alt {
        self.toggle_invert()
      }
    Enter => {
      let chosen : Array[T] = []
      for i in 0..<self.options.length() {
        if self.selected[i] {
          chosen.push(self.options[i].value)
        }
      }
      if self.required && chosen.is_empty() {
        self.phase = Warning("Please select at least one option.")
        return None
      }
      self.phase = Submitted
      return Some(Submitted(chosen))
    }
    Paste(_) => ()
    _ => ()
  }
  None
}

///|
pub fn[T] MultiSelectModel::view(self : MultiSelectModel[T]) -> FrameSpec {
  let items : Array[OptionRowView] = []
  let chosen_labels : Array[String] = []
  for i in 0..<self.options.length() {
    let opt = self.options[i]
    let is_sel = self.selected[i]
    if is_sel {
      chosen_labels.push(opt.label)
    }
    items.push({
      label: opt.label,
      hint: opt.hint,
      is_cursor: !self.all_disabled && i == self.cursor,
      is_selected: is_sel,
      is_disabled: opt.disabled,
      is_multi: true,
    })
  }
  let summary : String? = match self.phase {
    Submitted =>
      Some(
        if chosen_labels.is_empty() {
          "none"
        } else {
          chosen_labels.join(", ")
        },
      )
    Cancelled => Some(chosen_labels.join(", "))
    _ => None
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
      is_multi=true,
    ),
    submitted_summary: summary,
    with_guide: self.with_guide,
    max_rows: None,
  }
}

///|
pub fn[T] MultiSelectModel::as_adapter(
  self : MultiSelectModel[T],
) -> PromptAdapter[Array[T]] {
  PromptAdapter(on_key=fn(ev, allow_back) { self.on_key(ev, allow_back~) }, view=fn() {
    self.view()
  })
}
