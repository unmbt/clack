///|
const SEQ_ENTER_INTERACTIVE : String = "\u{001b}[?25l\u{001b}[?2004h"

///|
const SEQ_LEAVE_INTERACTIVE : String = "\u{001b}[?2004l\u{001b}[?25h\u{001b}[?2026l"

///|
async fn read_bytes_with_timeout(
  term : &@term.Terminal,
  timeout_ms : Int32,
) -> Bytes?? raise @term.TermError {
  @async.with_timeout_opt(timeout_ms, () => term.read_bytes()) catch {
    @term.TermError::IoFailure(msg) => raise IoFailure(msg)
    @term.TermError::NotInteractive(msg) => raise NotInteractive(msg)
    @term.TermError::EndOfInput => raise EndOfInput
    err => raise IoFailure("\{Repr(err)}")
  }
}

///|
fn render_spec_lines(
  session : Session,
  spec : @core.FrameSpec,
  cols : Int32,
  rows : Int32,
) -> Array[String] {
  let enriched = {
    ..spec,
    with_guide: session.with_guide && spec.with_guide,
    max_rows: Some(rows),
  }
  session.theme.render_frame(enriched, session.styler, cols)
}

///|
async fn[T] run_async_validator(
  vfn : async (T) -> String?,
  val : T,
) -> String? raise @term.TermError {
  vfn(val) catch {
    @term.TermError::IoFailure(msg) => raise IoFailure(msg)
    @term.TermError::NotInteractive(msg) => raise NotInteractive(msg)
    @term.TermError::EndOfInput => raise EndOfInput
    err => Some("\{Repr(err)}")
  }
}

///|
async fn[T] run_prompt_core(
  adapter : @core.PromptAdapter[T],
  allow_back~ : Bool = false,
  set_phase? : (@core.PromptPhase) -> Unit,
  validate_async? : async (T) -> String?,
  after_key? : async () -> Unit noraise,
  session? : Session,
) -> @core.PromptOutcome[T] raise @term.TermError {
  let s = resolve_session(session)
  let term = s.term
  let sync_out = term.is_tty()
  term.enter_raw_mode()
  term.write_str(SEQ_ENTER_INTERACTIVE)
  defer (try {
    term.write_final(SEQ_LEAVE_INTERACTIVE)
    term.leave_raw_mode()
  } catch {
    _ => ()
  })

  let renderer = @core.InlineDiffRenderer()
  let decoder = @core.KeyDecoder()
  let (init_cols, init_rows) = term.size()
  let mut prev_cols = if init_cols > 0 { init_cols } else { 80 }
  let mut prev_rows = if init_rows > 0 { init_rows } else { 24 }

  let initial_lines = render_spec_lines(
    s,
    (adapter.view)(),
    prev_cols,
    prev_rows,
  )
  let first_patch = renderer.patch(
    initial_lines,
    prev_cols,
    sync_output=sync_out,
  )
  if first_patch != "" {
    term.write_str(first_patch)
  }

  for ;; {
    let events : Array[@core.KeyEvent] = if decoder.has_pending_escape() {
      match read_bytes_with_timeout(term, 20) {
        Some(Some(chunk)) => decoder.feed(chunk[:])
        Some(None) =>
          match decoder.flush_escape() {
            Some(ev) => [ev]
            None => return Cancelled
          }
        None =>
          match decoder.flush_escape() {
            Some(ev) => [ev]
            None => []
          }
      }
    } else {
      match term.read_bytes() {
        Some(chunk) => decoder.feed(chunk[:])
        None =>
          match decoder.flush_escape() {
            Some(ev) => [ev]
            None => return Cancelled
          }
      }
    }

    let (cur_cols_raw, cur_rows_raw) = term.size()
    let cur_cols = if cur_cols_raw > 0 { cur_cols_raw } else { 80 }
    let cur_rows = if cur_rows_raw > 0 { cur_rows_raw } else { 24 }
    let resized = cur_cols != prev_cols
    prev_cols = cur_cols
    prev_rows = cur_rows

    let mut outcome : @core.PromptOutcome[T]? = None
    for ev in events {
      match (adapter.on_key)(ev, allow_back) {
        Some(res) => {
          outcome = Some(res)
          break
        }
        None => ()
      }
    }

    match after_key {
      Some(hook) => hook()
      None => ()
    }

    // Async validation hook on submit
    match (outcome, validate_async) {
      (Some(Submitted(val)), Some(vfn)) => {
        match set_phase {
          Some(sp) => sp(Validating)
          None => ()
        }
        let val_lines = render_spec_lines(
          s,
          (adapter.view)(),
          prev_cols,
          prev_rows,
        )
        let prefix = if resized { renderer.on_resize() } else { "" }
        let val_patch = prefix +
          renderer.patch(val_lines, prev_cols, sync_output=sync_out)
        if val_patch != "" {
          term.write_str(val_patch)
        }
        match run_async_validator(vfn, val) {
          Some(err_msg) => {
            match set_phase {
              Some(sp) => sp(Error(err_msg))
              None => ()
            }
            let err_lines = render_spec_lines(
              s,
              (adapter.view)(),
              prev_cols,
              prev_rows,
            )
            let err_patch = renderer.patch(
              err_lines,
              prev_cols,
              sync_output=sync_out,
            )
            if err_patch != "" {
              term.write_str(err_patch)
            }
            continue
          }
          None =>
            match set_phase {
              Some(sp) => sp(Submitted)
              None => ()
            }
        }
      }
      _ => ()
    }

    let lines = render_spec_lines(s, (adapter.view)(), prev_cols, prev_rows)
    match outcome {
      Some(res) => {
        let prefix = if resized { renderer.on_resize() } else { "" }
        let committed = prefix +
          renderer.commit(lines, prev_cols, sync_output=sync_out)
        term.write_str(committed)
        return res
      }
      None => {
        let prefix = if resized { renderer.on_resize() } else { "" }
        let patched = prefix +
          renderer.patch(lines, prev_cols, sync_output=sync_out)
        if patched != "" {
          term.write_str(patched)
        }
      }
    }
  }
}

///|
/// Core interactive prompt loop:
/// - Enters raw mode, hides physical cursor, enables Bracketed Paste
/// - Guarantees terminal restoration via `defer` + `nocancel` on submit, error, Ctrl+C, or task cancellation
/// - Performs 20ms bare-ESC disambiguation via `KeyDecoder::has_pending_escape` / `flush_escape`
/// - Detects terminal `size()` changes and reflows cleanly via `InlineDiffRenderer::on_resize`
pub async fn[T] run_prompt(
  adapter : @core.PromptAdapter[T],
  allow_back~ : Bool = false,
  session? : Session,
) -> @core.PromptOutcome[T] raise @term.TermError {
  run_prompt_core(adapter, allow_back~, session?)
}

///|
pub async fn text(
  message : String,
  placeholder? : String,
  default_value? : String,
  initial_value~ : String = "",
  validate? : (String) -> String?,
  validate_async? : async (String) -> String?,
  allow_back~ : Bool = false,
  session? : Session,
) -> @core.PromptOutcome[String] raise @term.TermError {
  let s = resolve_session(session)
  if !s.is_interactive() {
    match s.non_interactive {
      Fail =>
        raise NotInteractive(
          "Interactive terminal required for text prompt: \{message}",
        )
      UseDefaults => {
        let candidate : String? = if initial_value != "" {
          Some(initial_value)
        } else {
          default_value
        }
        match candidate {
          Some(val) => {
            match validate {
              Some(vfn) =>
                match vfn(val) {
                  Some(err) =>
                    raise NotInteractive(
                      "Default value failed validation for '\{message}': \{err}",
                    )
                  None => ()
                }
              None => ()
            }
            match validate_async {
              Some(vfn) =>
                match run_async_validator(vfn, val) {
                  Some(err) =>
                    raise NotInteractive(
                      "Default value failed validation for '\{message}': \{err}",
                    )
                  None => ()
                }
              None => ()
            }
            return Submitted(val)
          }
          None =>
            raise NotInteractive(
              "No default value provided for non-interactive text prompt: \{message}",
            )
        }
      }
    }
  }
  let model = @core.TextModel(
    message,
    placeholder?,
    default_value?,
    initial_value~,
    validate?,
    with_guide=s.with_guide,
  )
  run_prompt_core(
    model.as_adapter(),
    allow_back~,
    set_phase=fn(p) { model.set_phase(p) },
    validate_async?,
    session=s,
  )
}

///|
pub async fn password(
  message : String,
  mask~ : Char? = Some('▪'),
  clear_on_error~ : Bool = false,
  validate? : (String) -> String?,
  validate_async? : async (String) -> String?,
  allow_back~ : Bool = false,
  session? : Session,
) -> @core.PromptOutcome[String] raise @term.TermError {
  let s = resolve_session(session)
  if !s.is_interactive() {
    raise NotInteractive(
      "Interactive terminal required for password prompt: \{message}",
    )
  }
  let effective_mask : Char? = match mask {
    Some('▪') if !s.unicode => Some('•')
    other => other
  }
  let model = @core.PasswordModel(
    message,
    mask=effective_mask,
    clear_on_error~,
    validate?,
    with_guide=s.with_guide,
  )
  run_prompt_core(
    model.as_adapter(),
    allow_back~,
    set_phase=fn(p) { model.set_phase(p) },
    validate_async?,
    session=s,
  )
}

///|
pub async fn confirm(
  message : String,
  initial_value~ : Bool = true,
  active_label~ : String = "Yes",
  inactive_label~ : String = "No",
  vertical~ : Bool = false,
  allow_back~ : Bool = false,
  session? : Session,
) -> @core.PromptOutcome[Bool] raise @term.TermError {
  let s = resolve_session(session)
  if !s.is_interactive() {
    match s.non_interactive {
      Fail =>
        raise NotInteractive(
          "Interactive terminal required for confirm prompt: \{message}",
        )
      UseDefaults => return Submitted(initial_value)
    }
  }
  let model = @core.ConfirmModel(
    message,
    initial_value~,
    active_label~,
    inactive_label~,
    vertical~,
    with_guide=s.with_guide,
  )
  run_prompt(model.as_adapter(), allow_back~, session=s)
}

///|
pub async fn[T] select(
  message : String,
  options : Array[@core.SelectOption[T]],
  initial_index~ : Int32 = 0,
  max_items? : Int32,
  show_instructions~ : Bool = true,
  allow_back~ : Bool = false,
  session? : Session,
) -> @core.PromptOutcome[T] raise @term.TermError {
  let s = resolve_session(session)
  if !s.is_interactive() {
    match s.non_interactive {
      Fail =>
        raise NotInteractive(
          "Interactive terminal required for select prompt: \{message}",
        )
      UseDefaults => {
        let len = options.length()
        if len == 0 {
          raise NotInteractive(
            "No selectable options for select prompt: \{message}",
          )
        }
        let start = if initial_index >= 0 && initial_index < len {
          initial_index
        } else {
          0
        }
        for step in 0..<len {
          let idx = (start + step) % len
          if !options[idx].disabled {
            return Submitted(options[idx].value)
          }
        }
        raise NotInteractive(
          "All options disabled for select prompt: \{message}",
        )
      }
    }
  }
  let model = @core.SelectModel(
    message,
    options,
    initial_index~,
    max_items?,
    show_instructions~,
    with_guide=s.with_guide,
  )
  run_prompt(model.as_adapter(), allow_back~, session=s)
}

///|
/// Single-key instant selection prompt (1:1 upstream `@clack/prompts` `selectKey`).
pub async fn[T] select_key(
  message : String,
  options : Array[@core.SelectKeyOption[T]],
  initial_index~ : Int32 = 0,
  case_sensitive~ : Bool = false,
  allow_back~ : Bool = false,
  session? : Session,
) -> @core.PromptOutcome[T] raise @term.TermError {
  let s = resolve_session(session)
  if !s.is_interactive() {
    match s.non_interactive {
      Fail =>
        raise NotInteractive(
          "Interactive terminal required for select_key prompt: \{message}",
        )
      UseDefaults => {
        let len = options.length()
        if len == 0 {
          raise NotInteractive(
            "No selectable options for select_key prompt: \{message}",
          )
        }
        let start = if initial_index >= 0 && initial_index < len {
          initial_index
        } else {
          0
        }
        for step in 0..<len {
          let idx = (start + step) % len
          if !options[idx].disabled {
            return Submitted(options[idx].value)
          }
        }
        raise NotInteractive(
          "All options disabled for select_key prompt: \{message}",
        )
      }
    }
  }
  let model = @core.SelectKeyModel(
    message,
    options,
    initial_index~,
    case_sensitive~,
    with_guide=s.with_guide,
  )
  run_prompt(model.as_adapter(), allow_back~, session=s)
}

///|
pub async fn[T] multiselect(
  message : String,
  options : Array[@core.SelectOption[T]],
  initial_indices~ : Array[Int32] = [],
  required~ : Bool = true,
  max_items? : Int32,
  show_instructions~ : Bool = true,
  allow_back~ : Bool = false,
  session? : Session,
) -> @core.PromptOutcome[Array[T]] raise @term.TermError {
  let s = resolve_session(session)
  if !s.is_interactive() {
    match s.non_interactive {
      Fail =>
        raise NotInteractive(
          "Interactive terminal required for multiselect prompt: \{message}",
        )
      UseDefaults => {
        let chosen : Array[T] = []
        for idx in initial_indices {
          if idx >= 0 && idx < options.length() && !options[idx].disabled {
            chosen.push(options[idx].value)
          }
        }
        if required && chosen.is_empty() {
          raise NotInteractive(
            "No initial selection for required multiselect prompt: \{message}",
          )
        }
        return Submitted(chosen)
      }
    }
  }
  let model = @core.MultiSelectModel(
    message,
    options,
    initial_indices~,
    required~,
    max_items?,
    show_instructions~,
    with_guide=s.with_guide,
  )
  run_prompt(model.as_adapter(), allow_back~, session=s)
}

///|
pub async fn[T : Eq] group_multiselect(
  message : String,
  groups : Array[@core.GroupOption[T]],
  initial_values~ : Array[T] = [],
  required~ : Bool = true,
  max_items? : Int32,
  selectable_groups~ : Bool = true,
  group_spacing~ : Int32 = 0,
  show_instructions~ : Bool = true,
  allow_back~ : Bool = false,
  session? : Session,
) -> @core.PromptOutcome[Array[T]] raise @term.TermError {
  let s = resolve_session(session)
  if !s.is_interactive() {
    match s.non_interactive {
      Fail =>
        raise NotInteractive(
          "Interactive terminal required for group_multiselect prompt: \{message}",
        )
      UseDefaults => {
        let chosen : Array[T] = []
        for grp in groups {
          for opt in grp.options {
            if !opt.disabled && initial_values.contains(opt.value) {
              chosen.push(opt.value)
            }
          }
        }
        if required && chosen.is_empty() {
          raise NotInteractive(
            "No initial selection for required group_multiselect prompt: \{message}",
          )
        }
        return Submitted(chosen)
      }
    }
  }
  let model = @core.GroupMultiSelectModel::from_initial_values(
    message,
    groups,
    initial_values~,
    required~,
    max_items?,
    selectable_groups~,
    group_spacing~,
    show_instructions~,
    with_guide=s.with_guide,
  )
  run_prompt(model.as_adapter(), allow_back~, session=s)
}

///|
pub async fn[T] autocomplete(
  message : String,
  options : Array[@core.SelectOption[T]],
  placeholder? : String,
  initial_user_input~ : String = "",
  max_items? : Int32,
  complete_on_tab~ : Bool = false,
  filter? : (String, @core.SelectOption[T]) -> Bool,
  options_fn? : (String) -> Array[@core.SelectOption[T]],
  validate? : (T) -> String?,
  validate_async? : async (T) -> String?,
  allow_back~ : Bool = false,
  session? : Session,
) -> @core.PromptOutcome[T] raise @term.TermError {
  let s = resolve_session(session)
  if !s.is_interactive() {
    match s.non_interactive {
      Fail =>
        raise NotInteractive(
          "Interactive terminal required for autocomplete prompt: \{message}",
        )
      UseDefaults => {
        let effective_options = match options_fn {
          Some(provider) => provider(initial_user_input)
          None => options
        }
        let model = @core.AutocompleteModel(
          message,
          effective_options,
          placeholder?,
          initial_user_input~,
          max_items?,
          complete_on_tab~,
          filter?,
          validate?,
          with_guide=s.with_guide,
        )
        match model.focused_index() {
          Some(idx) => {
            let val = effective_options[idx].value
            match validate {
              Some(vfn) =>
                match vfn(val) {
                  Some(err) =>
                    raise NotInteractive(
                      "Default value failed validation for '\{message}': \{err}",
                    )
                  None => ()
                }
              None => ()
            }
            match validate_async {
              Some(vfn) =>
                match run_async_validator(vfn, val) {
                  Some(err) =>
                    raise NotInteractive(
                      "Default value failed validation for '\{message}': \{err}",
                    )
                  None => ()
                }
              None => ()
            }
            return Submitted(val)
          }
          None =>
            raise NotInteractive(
              "No matching selectable option for autocomplete prompt: \{message}",
            )
        }
      }
    }
  }
  let model = @core.AutocompleteModel(
    message,
    options,
    placeholder?,
    initial_user_input~,
    max_items?,
    complete_on_tab~,
    filter?,
    options_fn?,
    validate?,
    with_guide=s.with_guide,
  )
  run_prompt_core(
    model.as_adapter(),
    allow_back~,
    set_phase=fn(p) { model.set_phase(p) },
    validate_async?,
    session=s,
  )
}

///|
/// Searchable multi-select prompt (1:1 upstream `@clack/prompts` `autocompleteMultiselect`).
pub async fn[T] autocomplete_multiselect(
  message : String,
  options : Array[@core.SelectOption[T]],
  initial_indices~ : Array[Int32] = [],
  placeholder? : String,
  required~ : Bool = false,
  max_items? : Int32,
  filter? : (String, @core.SelectOption[T]) -> Bool,
  validate? : (Array[T]) -> String?,
  allow_back~ : Bool = false,
  session? : Session,
) -> @core.PromptOutcome[Array[T]] raise @term.TermError {
  let s = resolve_session(session)
  if !s.is_interactive() {
    match s.non_interactive {
      Fail =>
        raise NotInteractive(
          "Interactive terminal required for autocomplete_multiselect prompt: \{message}",
        )
      UseDefaults => {
        let chosen : Array[T] = []
        for idx in initial_indices {
          if idx >= 0 && idx < options.length() && !options[idx].disabled {
            chosen.push(options[idx].value)
          }
        }
        if required && chosen.is_empty() {
          raise NotInteractive(
            "No initial selection for required autocomplete_multiselect prompt: \{message}",
          )
        }
        match validate {
          Some(vfn) =>
            match vfn(chosen) {
              Some(err) =>
                raise NotInteractive(
                  "Default value failed validation for '\{message}': \{err}",
                )
              None => ()
            }
          None => ()
        }
        return Submitted(chosen)
      }
    }
  }
  let model = @core.AutocompleteMultiSelectModel(
    message,
    options,
    initial_indices~,
    placeholder?,
    required~,
    max_items?,
    filter?,
    validate?,
    with_guide=s.with_guide,
  )
  run_prompt(model.as_adapter(), allow_back~, session=s)
}

///|
/// Multi-line text input prompt (1:1 upstream `@clack/prompts` `multiline`).
pub async fn multiline(
  message : String,
  placeholder? : String,
  default_value? : String,
  initial_value~ : String = "",
  show_submit~ : Bool = false,
  validate? : (String) -> String?,
  validate_async? : async (String) -> String?,
  allow_back~ : Bool = false,
  session? : Session,
) -> @core.PromptOutcome[String] raise @term.TermError {
  let s = resolve_session(session)
  if !s.is_interactive() {
    match s.non_interactive {
      Fail =>
        raise NotInteractive(
          "Interactive terminal required for multiline prompt: \{message}",
        )
      UseDefaults => {
        let candidate : String? = if initial_value != "" {
          Some(initial_value)
        } else {
          default_value
        }
        match candidate {
          Some(val) => {
            match validate {
              Some(vfn) =>
                match vfn(val) {
                  Some(err) =>
                    raise NotInteractive(
                      "Default value failed validation for '\{message}': \{err}",
                    )
                  None => ()
                }
              None => ()
            }
            match validate_async {
              Some(vfn) =>
                match run_async_validator(vfn, val) {
                  Some(err) =>
                    raise NotInteractive(
                      "Default value failed validation for '\{message}': \{err}",
                    )
                  None => ()
                }
              None => ()
            }
            return Submitted(val)
          }
          None =>
            raise NotInteractive(
              "No default value provided for non-interactive multiline prompt: \{message}",
            )
        }
      }
    }
  }
  let model = @core.MultiLineModel(
    message,
    placeholder?,
    default_value?,
    initial_value~,
    show_submit~,
    validate?,
    with_guide=s.with_guide,
  )
  run_prompt_core(
    model.as_adapter(),
    allow_back~,
    set_phase=fn(p) { model.set_phase(p) },
    validate_async?,
    session=s,
  )
}

///|
/// Segmented date picker prompt (1:1 upstream `@clack/prompts` `date`).
pub async fn date(
  message : String,
  format~ : @core.DateFormat = Ymd,
  separator~ : String = "/",
  initial_value? : @core.SimpleDate,
  default_value? : @core.SimpleDate,
  min_date? : @core.SimpleDate,
  max_date? : @core.SimpleDate,
  validate? : (@core.SimpleDate) -> String?,
  allow_back~ : Bool = false,
  session? : Session,
) -> @core.PromptOutcome[@core.SimpleDate] raise @term.TermError {
  let s = resolve_session(session)
  if !s.is_interactive() {
    match s.non_interactive {
      Fail =>
        raise NotInteractive(
          "Interactive terminal required for date prompt: \{message}",
        )
      UseDefaults => {
        let candidate = match initial_value {
          Some(d) => Some(d)
          None => default_value
        }
        match candidate {
          Some(d) => {
            match min_date {
              Some(min_d) if d.compare(min_d) < 0 =>
                raise NotInteractive(
                  "Default date before minimum for '\{message}'",
                )
              _ => ()
            }
            match max_date {
              Some(max_d) if d.compare(max_d) > 0 =>
                raise NotInteractive(
                  "Default date after maximum for '\{message}'",
                )
              _ => ()
            }
            match validate {
              Some(vfn) =>
                match vfn(d) {
                  Some(err) =>
                    raise NotInteractive(
                      "Default value failed validation for '\{message}': \{err}",
                    )
                  None => ()
                }
              None => ()
            }
            return Submitted(d)
          }
          None =>
            raise NotInteractive(
              "No default date provided for non-interactive date prompt: \{message}",
            )
        }
      }
    }
  }
  let model = @core.DateModel(
    message,
    format~,
    separator~,
    initial_value?,
    default_value?,
    min_date?,
    max_date?,
    validate?,
    with_guide=s.with_guide,
  )
  run_prompt(model.as_adapter(), allow_back~, session=s)
}
