///|
priv enum GroupFlatRow {
  GroupHeaderRow(group_idx~ : Int32, label~ : String, members~ : Array[Int32])
  GroupItemRow(group_idx~ : Int32, flat_idx~ : Int32, is_last~ : Bool)
}

///|
/// Headless grouped multi-select prompt state machine (1:1 upstream Clack + moonset tree).
pub struct GroupMultiSelectModel[T] {
  priv message : String
  priv flat_options : Array[SelectOption[T]]
  priv rows : Array[GroupFlatRow]
  priv selected : Array[Bool]
  priv mut cursor : Int32
  priv all_disabled : Bool
  priv required : Bool
  priv max_items : Int32?
  priv selectable_groups : Bool
  priv group_spacing : Int32
  priv show_instructions : Bool
  priv mut phase : PromptPhase
  priv with_guide : Bool
}

///|
fn[T] row_is_navigable(
  rows : Array[GroupFlatRow],
  flat_options : Array[SelectOption[T]],
  selectable_groups : Bool,
  row_idx : Int32,
) -> Bool {
  match rows[row_idx] {
    GroupHeaderRow(..) => selectable_groups
    GroupItemRow(flat_idx~, ..) => !flat_options[flat_idx].disabled
  }
}

///|
fn[T] find_group_cursor(
  rows : Array[GroupFlatRow],
  flat_options : Array[SelectOption[T]],
  selectable_groups : Bool,
  start : Int32,
  delta : Int32,
) -> Int32? {
  let len = rows.length()
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
    if row_is_navigable(rows, flat_options, selectable_groups, idx) {
      return Some(idx)
    }
    for step in 1..<len {
      let cand = (idx + step) % len
      if row_is_navigable(rows, flat_options, selectable_groups, cand) {
        return Some(cand)
      }
    }
    return None
  }
  for _ in 0..<len {
    idx = (idx + delta + len) % len
    if row_is_navigable(rows, flat_options, selectable_groups, idx) {
      return Some(idx)
    }
  }
  None
}

///|
pub fn[T] GroupMultiSelectModel::GroupMultiSelectModel(
  message : String,
  groups : Array[GroupOption[T]],
  initial_indices~ : Array[Int32] = [],
  required~ : Bool = true,
  max_items? : Int32,
  selectable_groups~ : Bool = true,
  group_spacing~ : Int32 = 0,
  show_instructions~ : Bool = true,
  with_guide~ : Bool = true,
) -> GroupMultiSelectModel[T] {
  let flat_options : Array[SelectOption[T]] = []
  let rows : Array[GroupFlatRow] = []
  for g_idx in 0..<groups.length() {
    let grp = groups[g_idx]
    let members : Array[Int32] = []
    let start_flat = flat_options.length()
    for opt in grp.options {
      let idx = flat_options.length()
      flat_options.push(opt)
      members.push(idx)
    }
    rows.push(GroupHeaderRow(group_idx=g_idx, label=grp.group, members~))
    let count = grp.options.length()
    for j in 0..<count {
      rows.push(
        GroupItemRow(
          group_idx=g_idx,
          flat_idx=start_flat + j,
          is_last=j == count - 1,
        ),
      )
    }
  }
  let selected = Array::make(flat_options.length(), false)
  for idx in initial_indices {
    if idx >= 0 && idx < flat_options.length() && !flat_options[idx].disabled {
      selected[idx] = true
    }
  }
  let has_any_enabled = flat_options.any(o => !o.disabled)
  match find_group_cursor(rows, flat_options, selectable_groups, 0, 0) {
    Some(cur) if has_any_enabled =>
      {
        message,
        flat_options,
        rows,
        selected,
        cursor: cur,
        all_disabled: false,
        required,
        max_items,
        selectable_groups,
        group_spacing: if group_spacing > 0 {
          group_spacing
        } else {
          0
        },
        show_instructions,
        phase: Initial,
        with_guide,
      }
    _ =>
      {
        message,
        flat_options,
        rows,
        selected,
        cursor: 0,
        all_disabled: true,
        required,
        max_items,
        selectable_groups,
        group_spacing: if group_spacing > 0 {
          group_spacing
        } else {
          0
        },
        show_instructions,
        phase: Error("No selectable options available"),
        with_guide,
      }
  }
}

///|
pub fn[T : Eq] GroupMultiSelectModel::from_initial_values(
  message : String,
  groups : Array[GroupOption[T]],
  initial_values~ : Array[T] = [],
  required~ : Bool = true,
  max_items? : Int32,
  selectable_groups~ : Bool = true,
  group_spacing~ : Int32 = 0,
  show_instructions~ : Bool = true,
  with_guide~ : Bool = true,
) -> GroupMultiSelectModel[T] {
  let initial_indices : Array[Int32] = []
  let mut flat_idx : Int32 = 0
  for grp in groups {
    for opt in grp.options {
      if initial_values.contains(opt.value) {
        initial_indices.push(flat_idx)
      }
      flat_idx += 1
    }
  }
  GroupMultiSelectModel(
    message,
    groups,
    initial_indices~,
    required~,
    max_items?,
    selectable_groups~,
    group_spacing~,
    show_instructions~,
    with_guide~,
  )
}

///|
pub fn[T] GroupMultiSelectModel::cursor(
  self : GroupMultiSelectModel[T],
) -> Int32 {
  self.cursor
}

///|
pub fn[T] GroupMultiSelectModel::selected_indices(
  self : GroupMultiSelectModel[T],
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
fn[T] GroupMultiSelectModel::toggle_current(
  self : GroupMultiSelectModel[T],
) -> Unit {
  if self.all_disabled || self.rows.is_empty() {
    return
  }
  match self.rows[self.cursor] {
    GroupHeaderRow(members~, ..) => {
      if !self.selectable_groups {
        return
      }
      let mut enabled_count : Int32 = 0
      let mut selected_count : Int32 = 0
      for idx in members {
        if !self.flat_options[idx].disabled {
          enabled_count += 1
          if self.selected[idx] {
            selected_count += 1
          }
        }
      }
      let target = selected_count < enabled_count
      for idx in members {
        if !self.flat_options[idx].disabled {
          self.selected[idx] = target
        }
      }
    }
    GroupItemRow(flat_idx~, ..) =>
      if !self.flat_options[flat_idx].disabled {
        self.selected[flat_idx] = !self.selected[flat_idx]
      }
  }
}

///|
fn[T] GroupMultiSelectModel::toggle_all(
  self : GroupMultiSelectModel[T],
) -> Unit {
  let mut enabled_count : Int32 = 0
  let mut selected_count : Int32 = 0
  for i in 0..<self.flat_options.length() {
    if !self.flat_options[i].disabled {
      enabled_count += 1
      if self.selected[i] {
        selected_count += 1
      }
    }
  }
  let target = selected_count < enabled_count
  for i in 0..<self.flat_options.length() {
    if !self.flat_options[i].disabled {
      self.selected[i] = target
    }
  }
}

///|
fn[T] GroupMultiSelectModel::toggle_invert(
  self : GroupMultiSelectModel[T],
) -> Unit {
  for i in 0..<self.flat_options.length() {
    if !self.flat_options[i].disabled {
      self.selected[i] = !self.selected[i]
    }
  }
}

///|
pub fn[T] GroupMultiSelectModel::on_key(
  self : GroupMultiSelectModel[T],
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
      match
        find_group_cursor(
          self.rows,
          self.flat_options,
          self.selectable_groups,
          self.cursor,
          -1,
        ) {
        Some(next) => self.cursor = next
        None => ()
      }
    Down | Right =>
      match
        find_group_cursor(
          self.rows,
          self.flat_options,
          self.selectable_groups,
          self.cursor,
          1,
        ) {
        Some(next) => self.cursor = next
        None => ()
      }
    Char('k') | Char('h') =>
      if !event.ctrl && !event.alt {
        match
          find_group_cursor(
            self.rows,
            self.flat_options,
            self.selectable_groups,
            self.cursor,
            -1,
          ) {
          Some(next) => self.cursor = next
          None => ()
        }
      }
    Char('j') | Char('l') =>
      if !event.ctrl && !event.alt {
        match
          find_group_cursor(
            self.rows,
            self.flat_options,
            self.selectable_groups,
            self.cursor,
            1,
          ) {
          Some(next) => self.cursor = next
          None => ()
        }
      }
    Home =>
      match
        find_group_cursor(
          self.rows,
          self.flat_options,
          self.selectable_groups,
          0,
          0,
        ) {
        Some(first) => self.cursor = first
        None => ()
      }
    End =>
      match
        find_group_cursor(
          self.rows,
          self.flat_options,
          self.selectable_groups,
          self.rows.length() - 1,
          0,
        ) {
        Some(last) => self.cursor = last
        None => ()
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
      for i in 0..<self.flat_options.length() {
        if self.selected[i] {
          chosen.push(self.flat_options[i].value)
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
pub fn[T] GroupMultiSelectModel::view(
  self : GroupMultiSelectModel[T],
) -> FrameSpec {
  let active_group_idx : Int32? = if !self.all_disabled &&
    self.cursor >= 0 &&
    self.cursor < self.rows.length() {
    match self.rows[self.cursor] {
      GroupHeaderRow(group_idx~, ..) => Some(group_idx)
      GroupItemRow(..) => None
    }
  } else {
    None
  }
  let view_rows : Array[GroupRowView] = []
  for r in 0..<self.rows.length() {
    let is_cur = !self.all_disabled && r == self.cursor
    match self.rows[r] {
      GroupHeaderRow(group_idx~, label~, members~) => {
        let mut enabled_cnt : Int32 = 0
        let mut sel_cnt : Int32 = 0
        for idx in members {
          if !self.flat_options[idx].disabled {
            enabled_cnt += 1
            if self.selected[idx] {
              sel_cnt += 1
            }
          }
        }
        let all_selected = enabled_cnt > 0 && sel_cnt == enabled_cnt
        let partial_selected = sel_cnt > 0 && sel_cnt < enabled_cnt
        let group_active = match active_group_idx {
          Some(ag) => ag == group_idx
          None => false
        }
        view_rows.push(
          Header(
            label~,
            is_cursor=is_cur,
            all_selected~,
            partial_selected~,
            group_active~,
            selectable=self.selectable_groups,
          ),
        )
      }
      GroupItemRow(group_idx~, flat_idx~, is_last~) => {
        let opt = self.flat_options[flat_idx]
        let in_active_group = !is_cur &&
          (match active_group_idx {
            Some(ag) => ag == group_idx
            None => false
          })
        view_rows.push(
          Item(
            row={
              label: opt.label,
              hint: opt.hint,
              is_cursor: is_cur,
              is_selected: self.selected[flat_idx],
              is_disabled: opt.disabled,
              is_multi: true,
            },
            is_last_in_group=is_last,
            in_active_group~,
            selectable_groups=self.selectable_groups,
          ),
        )
      }
    }
  }
  let chosen_labels : Array[String] = []
  for i in 0..<self.flat_options.length() {
    if self.selected[i] {
      chosen_labels.push(self.flat_options[i].label)
    }
  }
  let summary : String? = match self.phase {
    Submitted | Cancelled => Some(chosen_labels.join(", "))
    _ => None
  }
  {
    phase: self.phase,
    message: self.message,
    body: GroupOptionList(
      rows=view_rows,
      cursor=self.cursor,
      max_items=self.max_items,
      total_count=view_rows.length(),
      selectable_groups=self.selectable_groups,
      group_spacing=self.group_spacing,
      show_instructions=self.show_instructions,
    ),
    submitted_summary: summary,
    with_guide: self.with_guide,
    max_rows: None,
  }
}

///|
pub fn[T] GroupMultiSelectModel::as_adapter(
  self : GroupMultiSelectModel[T],
) -> PromptAdapter[Array[T]] {
  PromptAdapter(on_key=fn(ev, allow_back) { self.on_key(ev, allow_back~) }, view=fn() {
    self.view()
  })
}
