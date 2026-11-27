///|
fn fuzzy_subsequence_match(haystack : String, needle : String) -> Bool {
  let h = haystack.to_array()
  let n = needle.to_array()
  if n.is_empty() {
    return true
  }
  let mut ni : Int32 = 0
  for ch in h {
    if ch == n[ni] {
      ni += 1
      if ni == n.length() {
        return true
      }
    }
  }
  false
}

///|
fn[T] default_autocomplete_filter(
  query : String,
  opt : SelectOption[T],
) -> Bool {
  if query == "" {
    return true
  }
  let term = query.to_lower()
  let label_lower = opt.label.to_lower()
  if label_lower.contains(term) {
    return true
  }
  match opt.hint {
    Some(h) if h.to_lower().contains(term) => return true
    _ => ()
  }
  fuzzy_subsequence_match(label_lower, term)
}

///|
/// Headless searchable autocomplete single-select state machine.
/// Keeps printable keys (`j`, `k`, `a`, `i`, `Space`, etc.) bound to the search input
/// and uses Up/Down arrows for candidate navigation (1:1 upstream Clack).
pub struct AutocompleteModel[T] {
  priv message : String
  priv mut options : Array[SelectOption[T]]
  priv options_fn : ((String) -> Array[SelectOption[T]])?
  priv placeholder : String?
  priv mut query_chars : Array[Char]
  priv mut query_cursor : Int32
  priv mut filtered : Array[Int32]
  priv mut list_cursor : Int32
  priv mut is_navigating : Bool
  priv max_items : Int32?
  priv complete_on_tab : Bool
  priv filter : (String, SelectOption[T]) -> Bool
  priv validate : ((T) -> String?)?
  priv mut phase : PromptPhase
  priv with_guide : Bool
}

///|
fn[T] AutocompleteModel::recompute_filter(self : AutocompleteModel[T]) -> Unit {
  let prev_opt_idx : Int32? = if self.list_cursor >= 0 &&
    self.list_cursor < self.filtered.length() {
    Some(self.filtered[self.list_cursor])
  } else {
    None
  }
  let q = self.query()
  match self.options_fn {
    Some(provider) => self.options = provider(q)
    None => ()
  }
  let next_filtered : Array[Int32] = []
  for i in 0..<self.options.length() {
    if self.options_fn is Some(_) || (self.filter)(q, self.options[i]) {
      next_filtered.push(i)
    }
  }
  self.filtered = next_filtered
  if self.filtered.is_empty() {
    self.list_cursor = 0
    return
  }
  // Preserve previous focus if still present and enabled
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
  // Otherwise pick first enabled option in filtered list
  for j in 0..<self.filtered.length() {
    if !self.options[self.filtered[j]].disabled {
      self.list_cursor = j
      return
    }
  }
  self.list_cursor = 0
}

///|
fn[T] AutocompleteModel::move_list_cursor(
  self : AutocompleteModel[T],
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
pub fn[T] AutocompleteModel::AutocompleteModel(
  message : String,
  options : Array[SelectOption[T]],
  placeholder? : String,
  initial_user_input~ : String = "",
  max_items? : Int32,
  complete_on_tab~ : Bool = false,
  filter? : (String, SelectOption[T]) -> Bool,
  options_fn? : (String) -> Array[SelectOption[T]],
  validate? : (T) -> String?,
  with_guide~ : Bool = true,
) -> AutocompleteModel[T] {
  let query_chars = initial_user_input.to_array()
  let filter_fn = match filter {
    Some(f) => f
    None => default_autocomplete_filter
  }
  let model : AutocompleteModel[T] = {
    message,
    options,
    options_fn,
    placeholder,
    query_chars,
    query_cursor: query_chars.length(),
    filtered: [],
    list_cursor: 0,
    is_navigating: false,
    max_items,
    complete_on_tab,
    filter: filter_fn,
    validate,
    phase: Initial,
    with_guide,
  }
  model.recompute_filter()
  model
}

///|
pub fn[T] AutocompleteModel::set_phase(
  self : AutocompleteModel[T],
  phase : PromptPhase,
) -> Unit {
  self.phase = phase
}

///|
pub fn[T] AutocompleteModel::set_options(
  self : AutocompleteModel[T],
  options : Array[SelectOption[T]],
) -> Unit {
  self.options = options
  self.recompute_filter()
}

///|
pub fn[T] AutocompleteModel::query(self : AutocompleteModel[T]) -> String {
  String::from_array(self.query_chars)
}

///|
pub fn[T] AutocompleteModel::filtered_count(
  self : AutocompleteModel[T],
) -> Int32 {
  self.filtered.length()
}

///|
pub fn[T] AutocompleteModel::focused_index(
  self : AutocompleteModel[T],
) -> Int32? {
  if self.filtered.is_empty() ||
    self.list_cursor < 0 ||
    self.list_cursor >= self.filtered.length() {
    return None
  }
  let opt_idx = self.filtered[self.list_cursor]
  if self.options[opt_idx].disabled {
    None
  } else {
    Some(opt_idx)
  }
}

///|
pub fn[T] AutocompleteModel::on_key(
  self : AutocompleteModel[T],
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
    Tab => {
      // 1:1 upstream: fill placeholder if empty and placeholder matches >= 1 enabled option
      if self.query_chars.is_empty() {
        match self.placeholder {
          Some(ph) if ph != "" => {
            let matches_any = self.options.any(opt => {
              !opt.disabled && (self.filter)(ph, opt)
            })
            if matches_any {
              self.query_chars = ph.to_array()
              self.query_cursor = self.query_chars.length()
              self.recompute_filter()
              self.is_navigating = false
              return None
            }
          }
          _ => ()
        }
      }
      if self.complete_on_tab {
        match self.focused_index() {
          Some(opt_idx) => {
            let completion = self.options[opt_idx].label
            self.query_chars = completion.to_array()
            self.query_cursor = self.query_chars.length()
            self.recompute_filter()
            self.is_navigating = false
          }
          None => ()
        }
      }
    }
    Space => {
      let (next_chars, next_cur) = insert_chars_at(
        self.query_chars,
        self.query_cursor,
        [' '],
      )
      self.query_chars = next_chars
      self.query_cursor = next_cur
      self.recompute_filter()
      self.is_navigating = false
    }
    Char(ch) =>
      if !event.ctrl && !event.alt {
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
    Enter =>
      match self.focused_index() {
        Some(opt_idx) => {
          let chosen = self.options[opt_idx].value
          match self.validate {
            Some(vfn) =>
              match vfn(chosen) {
                Some(err_msg) => {
                  self.phase = Error(err_msg)
                  return None
                }
                None => ()
              }
            None => ()
          }
          self.phase = Submitted
          return Some(Submitted(chosen))
        }
        None => {
          self.phase = Error("No matching option selected")
          return None
        }
      }
    _ => ()
  }
  None
}

///|
pub fn[T] AutocompleteModel::view(self : AutocompleteModel[T]) -> FrameSpec {
  let items : Array[OptionRowView] = []
  for j in 0..<self.filtered.length() {
    let opt = self.options[self.filtered[j]]
    items.push({
      label: opt.label,
      hint: opt.hint,
      is_cursor: j == self.list_cursor && !opt.disabled,
      is_selected: false,
      is_disabled: opt.disabled,
      is_multi: false,
    })
  }
  let summary : String? = match self.phase {
    Submitted =>
      match self.focused_index() {
        Some(opt_idx) => Some(self.options[opt_idx].label)
        None => Some("")
      }
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
      complete_on_tab=self.complete_on_tab,
      show_instructions=true,
      is_multi=false,
    ),
    submitted_summary: summary,
    with_guide: self.with_guide,
    max_rows: None,
  }
}

///|
pub fn[T] AutocompleteModel::as_adapter(
  self : AutocompleteModel[T],
) -> PromptAdapter[T] {
  PromptAdapter(on_key=fn(ev, allow_back) { self.on_key(ev, allow_back~) }, view=fn() {
    self.view()
  })
}
