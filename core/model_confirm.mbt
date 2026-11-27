///|
/// Headless boolean confirm prompt state machine (1:1 upstream Clack ConfirmPrompt).
pub struct ConfirmModel {
  priv message : String
  priv mut value : Bool
  priv active_label : String
  priv inactive_label : String
  priv vertical : Bool
  priv mut phase : PromptPhase
  priv with_guide : Bool
}

///|
pub fn ConfirmModel::ConfirmModel(
  message : String,
  initial_value~ : Bool = true,
  active_label~ : String = "Yes",
  inactive_label~ : String = "No",
  vertical~ : Bool = false,
  with_guide~ : Bool = true,
) -> ConfirmModel {
  {
    message,
    value: initial_value,
    active_label,
    inactive_label,
    vertical,
    phase: Initial,
    with_guide,
  }
}

///|
pub fn ConfirmModel::value(self : ConfirmModel) -> Bool {
  self.value
}

///|
pub fn ConfirmModel::on_key(
  self : ConfirmModel,
  event : KeyEvent,
  allow_back~ : Bool = false,
) -> PromptOutcome[Bool]? {
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
  if self.phase is Initial {
    self.phase = Active
  }
  match event.code {
    // 1:1 upstream Clack: y/Y/n/N immediately confirm & submit
    Char('y') | Char('Y') =>
      if !event.ctrl && !event.alt {
        self.value = true
        self.phase = Submitted
        return Some(Submitted(true))
      }
    Char('n') | Char('N') =>
      if !event.ctrl && !event.alt {
        self.value = false
        self.phase = Submitted
        return Some(Submitted(false))
      }
    Left | Right | Up | Down | Space | Tab => self.value = !self.value
    Char('h') | Char('l') | Char('j') | Char('k') =>
      if !event.ctrl && !event.alt {
        self.value = !self.value
      }
    Enter => {
      self.phase = Submitted
      return Some(Submitted(self.value))
    }
    Paste(_) => ()
    _ => ()
  }
  None
}

///|
pub fn ConfirmModel::view(self : ConfirmModel) -> FrameSpec {
  let chosen = if self.value { self.active_label } else { self.inactive_label }
  let summary = match self.phase {
    Submitted | Cancelled => Some(chosen)
    _ => None
  }
  {
    phase: self.phase,
    message: self.message,
    body: ConfirmToggle(
      active_yes=self.value,
      yes_label=self.active_label,
      no_label=self.inactive_label,
      vertical=self.vertical,
    ),
    submitted_summary: summary,
    with_guide: self.with_guide,
    max_rows: None,
  }
}

///|
pub fn ConfirmModel::as_adapter(self : ConfirmModel) -> PromptAdapter[Bool] {
  PromptAdapter(on_key=fn(ev, allow_back) { self.on_key(ev, allow_back~) }, view=fn() {
    self.view()
  })
}
