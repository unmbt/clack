///|
/// Immutable prompt session holding terminal I/O, theme, color capability,
/// accessibility mode, non-interactive policy, and default messages (zero global mutable state).
pub struct Session {
  term : &@term.Terminal
  theme : &@core.Theme
  styler : @ansi.Styler
  non_interactive : @term.NonInteractivePolicy
  with_guide : Bool
  unicode : Bool
  accessible : Bool
  cancel_message : String
  error_message : String
}

///|
fn detect_accessible_env(term : &@term.Terminal) -> Bool {
  match term.env_get("ACCESSIBLE") {
    Some(v) => {
      let trimmed = v.trim().to_lower()
      trimmed != "" && trimmed != "0" && trimmed != "false"
    }
    None => false
  }
}

///|
pub fn Session::Session(
  term? : &@term.Terminal,
  theme? : &@core.Theme,
  color_level? : @ansi.ColorLevel,
  non_interactive~ : @term.NonInteractivePolicy = UseDefaults,
  with_guide~ : Bool = true,
  unicode~ : Bool = true,
  accessible? : Bool,
  cancel_message~ : String = "Canceled",
  error_message~ : String = "Something went wrong",
) -> Session {
  let resolved_term : &@term.Terminal = match term {
    Some(t) => t
    None => @term.default_terminal()
  }
  let resolved_level : @ansi.ColorLevel = match color_level {
    Some(lvl) => lvl
    None =>
      @ansi.detect_color_level(is_tty=resolved_term.is_tty(), env_lookup=fn(k) {
        resolved_term.env_get(k)
      })
  }
  let resolved_theme : &@core.Theme = match theme {
    Some(th) => th
    None => @core.ClackTheme(unicode~, with_guide~)
  }
  let resolved_accessible = match accessible {
    Some(a) => a
    None => detect_accessible_env(resolved_term)
  }
  {
    term: resolved_term,
    theme: resolved_theme,
    styler: @ansi.Styler(level=resolved_level),
    non_interactive,
    with_guide,
    unicode,
    accessible: resolved_accessible,
    cancel_message,
    error_message,
  }
}

///|
pub fn Session::is_ci(self : Session) -> Bool {
  match self.term.env_get("CI") {
    Some(v) => {
      let trimmed = v.trim().to_lower()
      trimmed == "true" || trimmed == "1"
    }
    None => false
  }
}

///|
pub fn Session::is_interactive(self : Session) -> Bool {
  self.term.is_tty()
}

///|
fn resolve_session(session : Session?) -> Session {
  match session {
    Some(s) => s
    None => Session()
  }
}
