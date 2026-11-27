///|
pub fn[T] PromptOutcome::is_submitted(self : PromptOutcome[T]) -> Bool {
  self is Submitted(_)
}

///|
pub fn[T] PromptOutcome::is_cancelled(self : PromptOutcome[T]) -> Bool {
  self is Cancelled
}

///|
pub fn[T] PromptOutcome::is_step_back(self : PromptOutcome[T]) -> Bool {
  self is StepBack
}

///|
pub fn[T] PromptOutcome::to_option(self : PromptOutcome[T]) -> T? {
  match self {
    Submitted(v) => Some(v)
    Cancelled | StepBack => None
  }
}

///|
pub fn[T] PromptOutcome::unwrap_or(self : PromptOutcome[T], default : T) -> T {
  match self {
    Submitted(v) => v
    Cancelled | StepBack => default
  }
}

///|
pub fn[T] SelectOption::SelectOption(
  value : T,
  label : String,
  hint? : String,
  disabled~ : Bool = false,
) -> SelectOption[T] {
  { value, label, hint, disabled, }
}

///|
pub fn[T] GroupOption::GroupOption(
  group : String,
  options : Array[SelectOption[T]],
) -> GroupOption[T] {
  { group, options, }
}

///|
pub fn[T] PromptAdapter::PromptAdapter(
  on_key~ : (KeyEvent, Bool) -> PromptOutcome[T]?,
  view~ : () -> FrameSpec,
) -> PromptAdapter[T] {
  { on_key, view, }
}

///|
fn is_cancel_event(event : KeyEvent) -> Bool {
  event.ctrl && (event.code == Char('c') || event.code == Char('d'))
}

///|
fn is_back_event(event : KeyEvent, allow_back : Bool) -> Bool {
  allow_back && (event.code == Escape || event.code == BackTab)
}

///|
fn is_ideographic_space(ch : Char) -> Bool {
  ch == '\u{3000}'
}

///|
/// Sanitize a Bracketed Paste payload for single-line text / autocomplete inputs:
/// strips C0/C1 control chars (except CR/LF/Tab), trims trailing newlines,
/// and collapses internal newlines / CRLF runs into a single space.
fn sanitize_paste_single_line(raw : String) -> String {
  let chars = raw.to_array()
  let mut end = chars.length()
  while end > 0 && (chars[end - 1] == '\r' || chars[end - 1] == '\n') {
    end -= 1
  }
  let buf = StringBuilder()
  let mut i : Int32 = 0
  let mut prev_was_nl = false
  while i < end {
    let ch = chars[i]
    if ch == '\r' || ch == '\n' {
      if !prev_was_nl {
        buf.write_char(' ')
        prev_was_nl = true
      }
    } else if ch == '\t' {
      prev_was_nl = false
      buf.write_char(' ')
    } else if ch <= '\u{001f}' || (ch >= '\u{007f}' && ch <= '\u{009f}') {
      // Strip control characters
      ()
    } else {
      prev_was_nl = false
      buf.write_char(ch)
    }
    i += 1
  }
  buf.to_string()
}

///|
/// Sanitize a Bracketed Paste payload for password inputs:
/// strips all CR, LF, and C0/C1 control characters completely.
fn sanitize_paste_password(raw : String) -> String {
  let buf = StringBuilder()
  for ch in raw.to_array() {
    if ch == '\r' ||
      ch == '\n' ||
      ch <= '\u{001f}' ||
      (ch >= '\u{007f}' && ch <= '\u{009f}') {
      continue
    }
    buf.write_char(ch)
  }
  buf.to_string()
}
