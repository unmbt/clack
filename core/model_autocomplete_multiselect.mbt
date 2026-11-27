///|
/// Headless searchable multi-select prompt state machine
/// (1:1 upstream `@clack/prompts` `autocompleteMultiselect`).
pub struct AutocompleteMultiSelectModel[T] {
  priv message : String
  priv options : Array[SelectOption[T]]
  priv selected : Array[Bool]
  priv placeholder : String?
  priv mut query_chars : Array[Char]
  priv mut query_cursor : Int32
  priv mut filtered : Array[Int32]
  priv mut list_cursor : Int32
  priv mut is_navigating : Bool
  priv required : Bool
  priv max_items : Int32?
  priv filter : (String, SelectOption[T]) -> Bool
  priv validate : ((Array[T]) -> String?)?
  priv mut phase : PromptPhase
  priv with_guide : Bool
}

///|
fn[T] AutocompleteMultiSelectModel::recompute_filter(
  self : AutocompleteMultiSelectModel[T],
) -> Unit {
  let prev_opt_idx : Int32? = if self.list_cursor >= 0 &&
    self.list_cursor < self.filtered.length() {
    Some(self.filtered[self.list_cursor])
  } else {
    None
  }
  let q = self.query()
  let next_filtered : Array[Int32] = []
  for i in 0..<self.options.length() {
    if (self.filter)(q, self.options[i]) {
      next_filtered.push(i)
    }
  }
  self.filtered = next_filtered
  if self.filtered.is_empty() {
    self.list_cursor = 0
    return
  }
  match prev_opt_idx {
    Some(prev) =>
      for j in 0..<self.filtered.length() {
        if self.filtered[j] == prev && !self.options[prev].disabled {
          self.list_cursor = j
          return
        }
      }
    None => ()
  }
  for j in 0..<self.filtered.length() {
    if !self.options[self.filtered[j]].disabled {
      self.list_cursor = j
      return
    }
  }
  self.list_cursor = 0
}

///|
fn[T] AutocompleteMultiSelectModel::move_list_cursor(
  self : AutocompleteMultiSelectModel[T],
  delta : Int32,
) -> Unit {
  let len = self.filtered.length()
  if len == 0 {
    return
  }
  let mut idx = self.list_cursor
  for _ in 0..<len {
    idx = (idx + delta + len) % len
    if !self.options[self.filtered[idx]].disabled {
      self.list_cursor = idx
      return
    }
  }
}

///|
pub fn[T] AutocompleteMultiSelectModel::AutocompleteMultiSelectModel(
  message : String,
  options : Array[SelectOption[T]],
  initial_indices~ : Array[Int32] = [],
  placeholder? : String,
  required~ : Bool = false,
  max_items? : Int32,
  filter? : (String, SelectOption[T]) -> Bool,
  validate? : (Array[T]) -> String?,
  with_guide~ : Bool = true,
) -> AutocompleteMultiSelectModel[T] {
  let selected = Array::make(options.length(), false)
  for idx in initial_indices {
    if idx >= 0 && idx < options.length() && !options[idx].disabled {
      selected[idx] = true
    }
  }
  let filter_fn = match filter {
    Some(f) => f
    None => default_autocomplete_filter
  }
  let model : AutocompleteMultiSelectModel[T] = {
    message,
    options,
    selected,
    placeholder,
    query_chars: [],
    query_cursor: 0,
    filtered: [],
    list_cursor: 0,
    is_navigating: false,
    required,
    max_items,
    filter: filter_fn,
    validate,
    phase: Initial,
    with_guide,
  }
  model.recompute_filter()
  model
}

///|
pub fn[T] AutocompleteMultiSelectModel::query(
  self : AutocompleteMultiSelectModel[T],
) -> String {
  String::from_array(self.query_chars)
}

///|
pub fn[T] AutocompleteMultiSelectModel::selected_indices(
  self : AutocompleteMultiSelectModel[T],
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
fn[T] AutocompleteMultiSelectModel::toggle_focused(
  self : AutocompleteMultiSelectModel[T],
) -> Unit {
  if self.filtered.is_empty() ||
    self.list_cursor < 0 ||
    self.list_cursor >= self.filtered.length() {
    return
  }
  let opt_idx = self.filtered[self.list_cursor]
  if !self.options[opt_idx].disabled {
    self.selected[opt_idx] = !self.selected[opt_idx]
  }
}

///|
pub fn[T] AutocompleteMultiSelectModel::on_key(
  self : AutocompleteMultiSelectModel[T],
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
  if self.phase is (Initial | Warning(_) | Error(_)) {
    self.phase = Active
  }
  match event.code {
    Up => {
      self.move_list_cursor(-1)
      self.is_navigating = true
    }
    Down => {
      self.move_list_cursor(1)
      self.is_navigating = true
    }
    Tab => self.toggle_focused()
    Space =>
      if self.is_navigating {
        self.toggle_focused()
      } else {
        let (next_chars, next_cur) = insert_chars_at(
          self.query_chars,
          self.query_cursor,
          [' '],
        )
        self.query_chars = next_chars
        self.query_cursor = next_cur
        self.recompute_filter()
      }
    Left => {
      if self.query_cursor > 0 {
        self.query_cursor -= 1
      }
      self.is_navigating = false
    }
    Right => {
      if self.query_cursor < self.query_chars.length() {
        self.query_cursor += 1
      }
      self.is_navigating = false
    }
    Home => {
      self.query_cursor = 0
      self.is_navigating = false
    }
    End => {
      self.query_cursor = self.query_chars.length()
      self.is_navigating = false
    }
    Backspace => {
      if self.query_cursor > 0 {
        self.query_chars = delete_char_at(
          self.query_chars,
          self.query_cursor - 1,
        )
        self.query_cursor -= 1
        self.recompute_filter()
      }
      self.is_navigating = false
    }
    Delete => {
      if self.query_cursor < self.query_chars.length() {
        self.query_chars = delete_char_at(self.query_chars, self.query_cursor)
        self.recompute_filter()
      }
      self.is_navigating = false
    }
    Char(ch) if !event.ctrl && !event.alt => {
      let (next_chars, next_cur) = insert_chars_at(
        self.query_chars,
        self.query_cursor,
        [ch],
      )
      self.query_chars = next_chars
      self.query_cursor = next_cur
      self.recompute_filter()
      self.is_navigating = false
    }
    Paste(raw) => {
      let cleaned = sanitize_paste_single_line(raw)
      let inserted = cleaned.to_array()
      if !inserted.is_empty() {
        let (next_chars, next_cur) = insert_chars_at(
          self.query_chars,
          self.query_cursor,
          inserted,
        )
        self.query_chars = next_chars
        self.query_cursor = next_cur
        self.recompute_filter()
        self.is_navigating = false
      }
    }
    Enter => {
      let chosen : Array[T] = []
      for i in 0..<self.options.length() {
        if self.selected[i] {
          chosen.push(self.options[i].value)
        }
      }
      if self.required && chosen.is_empty() {
        self.phase = Error("Please select at least one item")
        return None
      }
      match self.validate {
        Some(vfn) =>
          match vfn(chosen) {
            Some(err) => {
              self.phase = Error(err)
              return None
            }
            None => ()
          }
        None => ()
      }
      self.phase = Submitted
      return Some(Submitted(chosen))
    }
    _ => ()
  }
  None
}

///|
pub fn[T] AutocompleteMultiSelectModel::view(
  self : AutocompleteMultiSelectModel[T],
) -> FrameSpec {
  let items : Array[OptionRowView] = []
  for j in 0..<self.filtered.length() {
    let opt_idx = self.filtered[j]
    let opt = self.options[opt_idx]
    items.push({
      label: opt.label,
      hint: opt.hint,
      is_cursor: j == self.list_cursor && !opt.disabled,
      is_selected: self.selected[opt_idx],
      is_disabled: opt.disabled,
      is_multi: true,
    })
  }
  let mut selected_count : Int32 = 0
  for sel in self.selected {
    if sel {
      selected_count += 1
    }
  }
  let summary : String? = match self.phase {
    Submitted => Some("\{selected_count} items selected")
    Cancelled => Some(self.query())
    _ => None
  }
  {
    phase: self.phase,
    message: self.message,
    body: OptionList(
      items~,
      cursor=self.list_cursor,
      max_items=self.max_items,
      total_count=items.length(),
      total_unfiltered=self.options.length(),
      filter_query=Some(self.query()),
      filter_cursor=self.query_cursor,
      filter_placeholder=self.placeholder,
      is_navigating=self.is_navigating,
      complete_on_tab=false,
      show_instructions=true,
      is_multi=true,
    ),
    submitted_summary: summary,
    with_guide: self.with_guide,
    max_rows: None,
  }
}

///|
pub fn[T] AutocompleteMultiSelectModel::as_adapter(
  self : AutocompleteMultiSelectModel[T],
) -> PromptAdapter[Array[T]] {
  PromptAdapter(on_key=fn(ev, allow_back) { self.on_key(ev, allow_back~) }, view=fn() {
    self.view()
  })
}
