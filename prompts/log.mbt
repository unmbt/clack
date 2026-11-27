///|
pub async fn intro(
  title : StringView,
  session? : Session,
) -> Unit raise @term.TermError {
  let s = resolve_session(session)
  let rendered = s.theme.render_intro(title, s.styler)
  s.term.write_str(rendered + "\n")
}

///|
pub async fn outro(
  message : StringView,
  session? : Session,
) -> Unit raise @term.TermError {
  let s = resolve_session(session)
  let rendered = s.theme.render_outro(message, s.styler)
  s.term.write_str(rendered + "\n")
}

///|
/// Render cancellation closing message. When `message` is omitted, defaults to
/// `session.cancel_message` ("Canceled") matching upstream Clack #643.
pub async fn cancel(
  message? : StringView,
  session? : Session,
) -> Unit raise @term.TermError {
  let s = resolve_session(session)
  let msg : StringView = match message {
    Some(m) => m
    None => s.cancel_message
  }
  let rendered = s.theme.render_cancel(msg, s.styler)
  s.term.write_str(rendered + "\n")
}

///|
/// Render a rounded note box with terminal-width wrapping and optional per-line `format`.
pub async fn note(
  title : StringView,
  body : StringView,
  format? : (String) -> String,
  session? : Session,
) -> Unit raise @term.TermError {
  let s = resolve_session(session)
  let (raw_cols, _) = s.term.size()
  let cols = if raw_cols > 0 { raw_cols } else { 80 }
  let rendered = if s.with_guide {
    let clack = @core.ClackTheme(unicode=s.unicode, with_guide=s.with_guide)
    clack.render_note_formatted(title, body, s.styler, cols~, format?)
  } else {
    let formatted_body = match format {
      Some(fmt) => {
        let lines : Array[String] = []
        for part in body.to_owned().split("\n") {
          lines.push(fmt(part.to_owned()))
        }
        lines.join("\n")
      }
      None => body.to_owned()
    }
    s.theme.render_note(title, formatted_body, s.styler)
  }
  s.term.write_str(rendered + "\n")
}

///|
async fn write_log_with_options(
  kind : StringView,
  message : StringView,
  spacing : Int32,
  secondary_symbol : StringView?,
  session : Session,
) -> Unit raise @term.TermError {
  let effective_spacing = if spacing >= 0 { spacing } else { 0 }
  if effective_spacing == 1 && secondary_symbol is None {
    session.term.write_str(
      session.theme.render_log(kind, message, session.styler) + "\n",
    )
    return
  }
  let bar_char = if session.unicode { "│" } else { "|" }
  let sec = match secondary_symbol {
    Some(ss) => ss.to_owned()
    None => session.styler.gray(bar_char)
  }
  let k = kind.to_owned()
  let sym = match k {
    "info" => session.styler.blue(if session.unicode { "●" } else { "•" })
    "success" => session.styler.green(if session.unicode { "◆" } else { "*" })
    "step" => session.styler.green(if session.unicode { "◇" } else { "o" })
    "warn" | "warning" =>
      session.styler.yellow(if session.unicode { "▲" } else { "!" })
    "error" => session.styler.red(if session.unicode { "■" } else { "x" })
    "message" | "" => sec
    _ => k
  }
  let parts : Array[String] = []
  for _ in 0..<effective_spacing {
    parts.push(if session.with_guide { sec } else { "" })
  }
  let msg_lines = message.to_owned().split("\n").collect()
  for i in 0..<msg_lines.length() {
    let ln = msg_lines[i].to_owned()
    if i == 0 {
      if session.with_guide {
        parts.push(if ln == "" { sym } else { sym + "  " + ln })
      } else {
        parts.push(ln)
      }
    } else if session.with_guide {
      parts.push(if ln == "" { sec } else { sec + "  " + ln })
    } else {
      parts.push(ln)
    }
  }
  session.term.write_str(parts.join("\n") + "\n")
}

///|
pub async fn log_info(
  message : StringView,
  spacing~ : Int32 = 1,
  secondary_symbol? : StringView,
  session? : Session,
) -> Unit raise @term.TermError {
  write_log_with_options(
    "info",
    message,
    spacing,
    secondary_symbol,
    resolve_session(session),
  )
}

///|
pub async fn log_step(
  message : StringView,
  spacing~ : Int32 = 1,
  secondary_symbol? : StringView,
  session? : Session,
) -> Unit raise @term.TermError {
  write_log_with_options(
    "step",
    message,
    spacing,
    secondary_symbol,
    resolve_session(session),
  )
}

///|
pub async fn log_success(
  message : StringView,
  spacing~ : Int32 = 1,
  secondary_symbol? : StringView,
  session? : Session,
) -> Unit raise @term.TermError {
  write_log_with_options(
    "success",
    message,
    spacing,
    secondary_symbol,
    resolve_session(session),
  )
}

///|
pub async fn log_warn(
  message : StringView,
  spacing~ : Int32 = 1,
  secondary_symbol? : StringView,
  session? : Session,
) -> Unit raise @term.TermError {
  write_log_with_options(
    "warn",
    message,
    spacing,
    secondary_symbol,
    resolve_session(session),
  )
}

///|
/// Alias for `log_warn` matching upstream Clack `log.warning()`.
pub async fn log_warning(
  message : StringView,
  spacing~ : Int32 = 1,
  secondary_symbol? : StringView,
  session? : Session,
) -> Unit raise @term.TermError {
  log_warn(message, spacing~, secondary_symbol?, session?)
}

///|
pub async fn log_error(
  message : StringView,
  spacing~ : Int32 = 1,
  secondary_symbol? : StringView,
  session? : Session,
) -> Unit raise @term.TermError {
  write_log_with_options(
    "error",
    message,
    spacing,
    secondary_symbol,
    resolve_session(session),
  )
}

///|
pub async fn log_message(
  message : StringView,
  symbol~ : StringView = "message",
  spacing~ : Int32 = 1,
  secondary_symbol? : StringView,
  session? : Session,
) -> Unit raise @term.TermError {
  write_log_with_options(
    symbol,
    message,
    spacing,
    secondary_symbol,
    resolve_session(session),
  )
}
