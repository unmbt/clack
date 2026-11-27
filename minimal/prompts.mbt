///|
pub fn minimal_session(
  term? : &@term.Terminal,
  color_level? : @ansi.ColorLevel,
  non_interactive~ : @term.NonInteractivePolicy = UseDefaults,
  unicode~ : Bool = true,
  accessible? : Bool,
  cancel_message~ : String = "Canceled",
) -> @prompts.Session {
  @prompts.Session(
    term?,
    theme=@core.MinimalTheme(unicode~),
    color_level?,
    non_interactive~,
    with_guide=false,
    unicode~,
    accessible?,
    cancel_message~,
  )
}

///|
fn resolve_minimal_session(session : @prompts.Session?) -> @prompts.Session {
  match session {
    Some(s) => s
    None => minimal_session()
  }
}

///|
pub async fn intro(
  title : StringView,
  session? : @prompts.Session,
) -> Unit raise @term.TermError {
  @prompts.intro(title, session=resolve_minimal_session(session))
}

///|
pub async fn outro(
  message : StringView,
  session? : @prompts.Session,
) -> Unit raise @term.TermError {
  @prompts.outro(message, session=resolve_minimal_session(session))
}

///|
pub async fn cancel(
  message? : StringView,
  session? : @prompts.Session,
) -> Unit raise @term.TermError {
  @prompts.cancel(message?, session=resolve_minimal_session(session))
}

///|
pub async fn note(
  title : StringView,
  body : StringView,
  format? : (String) -> String,
  session? : @prompts.Session,
) -> Unit raise @term.TermError {
  @prompts.note(title, body, format?, session=resolve_minimal_session(session))
}

///|
pub async fn box(
  message : StringView,
  title~ : StringView = "",
  content_align~ : @core.BoxAlign = Left,
  title_align~ : @core.BoxAlign = Left,
  width~ : @core.BoxWidth = Auto,
  title_padding~ : Int32 = 1,
  content_padding~ : Int32 = 2,
  rounded~ : Bool = false,
  format_border? : (String) -> String,
  session? : @prompts.Session,
) -> Unit raise @term.TermError {
  @prompts.box(
    message,
    title~,
    content_align~,
    title_align~,
    width~,
    title_padding~,
    content_padding~,
    rounded~,
    format_border?,
    session=resolve_minimal_session(session),
  )
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
  session? : @prompts.Session,
) -> @core.PromptOutcome[String] raise @term.TermError {
  @prompts.text(
    message,
    placeholder?,
    default_value?,
    initial_value~,
    validate?,
    validate_async?,
    allow_back~,
    session=resolve_minimal_session(session),
  )
}

///|
pub async fn password(
  message : String,
  mask~ : Char? = Some('*'),
  clear_on_error~ : Bool = false,
  validate? : (String) -> String?,
  validate_async? : async (String) -> String?,
  allow_back~ : Bool = false,
  session? : @prompts.Session,
) -> @core.PromptOutcome[String] raise @term.TermError {
  @prompts.password(
    message,
    mask~,
    clear_on_error~,
    validate?,
    validate_async?,
    allow_back~,
    session=resolve_minimal_session(session),
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
  session? : @prompts.Session,
) -> @core.PromptOutcome[Bool] raise @term.TermError {
  @prompts.confirm(
    message,
    initial_value~,
    active_label~,
    inactive_label~,
    vertical~,
    allow_back~,
    session=resolve_minimal_session(session),
  )
}

///|
pub async fn[T] select(
  message : String,
  options : Array[@core.SelectOption[T]],
  initial_index~ : Int32 = 0,
  max_items? : Int32,
  allow_back~ : Bool = false,
  session? : @prompts.Session,
) -> @core.PromptOutcome[T] raise @term.TermError {
  @prompts.select(
    message,
    options,
    initial_index~,
    max_items?,
    allow_back~,
    session=resolve_minimal_session(session),
  )
}

///|
pub async fn[T] select_key(
  message : String,
  options : Array[@core.SelectKeyOption[T]],
  initial_index~ : Int32 = 0,
  case_sensitive~ : Bool = false,
  allow_back~ : Bool = false,
  session? : @prompts.Session,
) -> @core.PromptOutcome[T] raise @term.TermError {
  @prompts.select_key(
    message,
    options,
    initial_index~,
    case_sensitive~,
    allow_back~,
    session=resolve_minimal_session(session),
  )
}

///|
pub async fn[T] multiselect(
  message : String,
  options : Array[@core.SelectOption[T]],
  initial_indices~ : Array[Int32] = [],
  required~ : Bool = true,
  max_items? : Int32,
  allow_back~ : Bool = false,
  session? : @prompts.Session,
) -> @core.PromptOutcome[Array[T]] raise @term.TermError {
  @prompts.multiselect(
    message,
    options,
    initial_indices~,
    required~,
    max_items?,
    allow_back~,
    session=resolve_minimal_session(session),
  )
}

///|
pub async fn[T : Eq] group_multiselect(
  message : String,
  groups : Array[@core.GroupOption[T]],
  initial_values~ : Array[T] = [],
  required~ : Bool = true,
  max_items? : Int32,
  allow_back~ : Bool = false,
  session? : @prompts.Session,
) -> @core.PromptOutcome[Array[T]] raise @term.TermError {
  @prompts.group_multiselect(
    message,
    groups,
    initial_values~,
    required~,
    max_items?,
    allow_back~,
    session=resolve_minimal_session(session),
  )
}

///|
pub async fn[T] autocomplete(
  message : String,
  options : Array[@core.SelectOption[T]],
  placeholder? : String,
  max_items? : Int32,
  filter? : (String, @core.SelectOption[T]) -> Bool,
  options_fn? : (String) -> Array[@core.SelectOption[T]],
  validate? : (T) -> String?,
  validate_async? : async (T) -> String?,
  allow_back~ : Bool = false,
  session? : @prompts.Session,
) -> @core.PromptOutcome[T] raise @term.TermError {
  @prompts.autocomplete(
    message,
    options,
    placeholder?,
    max_items?,
    filter?,
    options_fn?,
    validate?,
    validate_async?,
    allow_back~,
    session=resolve_minimal_session(session),
  )
}

///|
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
  session? : @prompts.Session,
) -> @core.PromptOutcome[Array[T]] raise @term.TermError {
  @prompts.autocomplete_multiselect(
    message,
    options,
    initial_indices~,
    placeholder?,
    required~,
    max_items?,
    filter?,
    validate?,
    allow_back~,
    session=resolve_minimal_session(session),
  )
}

///|
pub async fn multiline(
  message : String,
  placeholder? : String,
  default_value? : String,
  initial_value~ : String = "",
  show_submit~ : Bool = false,
  validate? : (String) -> String?,
  validate_async? : async (String) -> String?,
  allow_back~ : Bool = false,
  session? : @prompts.Session,
) -> @core.PromptOutcome[String] raise @term.TermError {
  @prompts.multiline(
    message,
    placeholder?,
    default_value?,
    initial_value~,
    show_submit~,
    validate?,
    validate_async?,
    allow_back~,
    session=resolve_minimal_session(session),
  )
}

///|
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
  session? : @prompts.Session,
) -> @core.PromptOutcome[@core.SimpleDate] raise @term.TermError {
  @prompts.date(
    message,
    format~,
    separator~,
    initial_value?,
    default_value?,
    min_date?,
    max_date?,
    validate?,
    allow_back~,
    session=resolve_minimal_session(session),
  )
}

///|
pub async fn tasks(
  items : Array[@prompts.Task],
  session? : @prompts.Session,
) -> Unit {
  @prompts.tasks(items, session=resolve_minimal_session(session))
}
