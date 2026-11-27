///|
/// Detect terminal color capability from TTY status and environment variables.
///
/// Precedence:
/// 1. `NO_COLOR` (non-empty) -> `None` (https://no-color.org/)
/// 2. `FORCE_COLOR` (`0`/`false` -> `None`, `1` -> `Ansi16`, `2` -> `Ansi256`, `3` -> `TrueColor`)
/// 3. `TERM=dumb` -> `None`
/// 4. `!is_tty` -> `None`
/// 5. `COLORTERM` / `WT_SESSION` / `TERM_PROGRAM` / `TERM` capability detection
pub fn detect_color_level(
  is_tty~ : Bool,
  env_lookup~ : (String) -> String?,
) -> ColorLevel {
  if env_lookup("NO_COLOR") is Some(v) && v != "" {
    return None
  }
  if env_lookup("FORCE_COLOR") is Some(v) {
    let trimmed = v.trim().to_lower()
    if trimmed == "0" || trimmed == "false" {
      return None
    }
    if trimmed == "1" {
      return Ansi16
    }
    if trimmed == "2" {
      return Ansi256
    }
    if trimmed == "3" {
      return TrueColor
    }
    if trimmed != "" {
      return Ansi16
    }
  }
  let term_lower = match env_lookup("TERM") {
    Some(t) => t.trim().to_lower()
    None => ""
  }
  if term_lower == "dumb" {
    return None
  }
  if !is_tty {
    return None
  }
  if env_lookup("COLORTERM") is Some(ct) {
    let ct_lower = ct.trim().to_lower()
    if ct_lower == "truecolor" || ct_lower == "24bit" {
      return TrueColor
    }
  }
  if env_lookup("WT_SESSION") is Some(wt) && wt != "" {
    return TrueColor
  }
  if env_lookup("TERM_PROGRAM") is Some(tp) {
    let tp_lower = tp.trim().to_lower()
    if tp_lower == "iterm.app" ||
      tp_lower == "wezterm" ||
      tp_lower == "vscode" ||
      tp_lower == "ghostty" {
      return TrueColor
    }
  }
  if term_lower.contains("256color") || term_lower.contains("256") {
    return Ansi256
  }
  if term_lower.contains("truecolor") || term_lower.contains("24bit") {
    return TrueColor
  }
  Ansi16
}
