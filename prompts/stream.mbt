///|
/// Chunk-by-chunk streaming log writer with guide rail and automatic terminal-width
/// wrapping (1:1 upstream `@clack/prompts` `stream`).
pub struct StreamLog {
  priv session : Session
  priv prefix : String
  priv mut line_width : Int32
  priv mut finished : Bool
}

///|
fn stream_symbol_for_kind(session : Session, kind : StringView) -> String {
  let k = kind.to_owned()
  match k {
    "info" => session.styler.blue(if session.unicode { "●" } else { "•" })
    "success" => session.styler.green(if session.unicode { "◆" } else { "*" })
    "step" => session.styler.green(if session.unicode { "◇" } else { "o" })
    "warn" | "warning" =>
      session.styler.yellow(if session.unicode { "▲" } else { "!" })
    "error" => session.styler.red(if session.unicode { "■" } else { "x" })
    "message" | "" =>
      session.styler.gray(if session.unicode { "│" } else { "|" })
    _ => k
  }
}

///|
pub async fn StreamLog::start(
  kind~ : StringView = "message",
  session? : Session,
) -> StreamLog raise @term.TermError {
  let s = resolve_session(session)
  let bar = s.styler.gray(if s.unicode { "│" } else { "|" })
  let prefix = if s.with_guide { bar + "  " } else { "" }
  let sym = stream_symbol_for_kind(s, kind)
  if s.with_guide {
    s.term.write_str(bar + "\n" + sym + "  ")
  }
  {
    session: s,
    prefix,
    line_width: if s.with_guide {
      3
    } else {
      0
    },
    finished: false,
  }
}

///|
pub async fn StreamLog::write(
  self : StreamLog,
  chunk : StringView,
) -> Unit raise @term.TermError {
  if self.finished {
    return
  }
  let (raw_cols, _) = self.session.term.size()
  let cols = if raw_cols > 4 { raw_cols } else { 80 }
  let text = chunk.to_owned()
  let parts = text.split("\n").collect()
  for i in 0..<parts.length() {
    if i > 0 {
      self.session.term.write_str("\n" + self.prefix)
      self.line_width = @ansi.display_width(self.prefix)
    }
    let seg = parts[i].to_owned()
    let seg_w = @ansi.display_width(seg)
    if self.line_width + seg_w < cols {
      self.line_width += seg_w
      self.session.term.write_str(seg)
    } else {
      let trimmed = seg.trim_start().to_owned()
      self.session.term.write_str("\n" + self.prefix + trimmed)
      self.line_width = @ansi.display_width(self.prefix) +
        @ansi.display_width(trimmed)
    }
  }
}

///|
pub async fn StreamLog::finish(self : StreamLog) -> Unit raise @term.TermError {
  if self.finished {
    return
  }
  self.finished = true
  self.session.term.write_str("\n")
}

///|
async fn stream_chunks(
  kind : StringView,
  chunks : Array[String],
  session : Session?,
) -> Unit raise @term.TermError {
  let writer = StreamLog::start(kind~, session?)
  for chunk in chunks {
    writer.write(chunk)
  }
  writer.finish()
}

///|
pub async fn stream_message(
  chunks : Array[String],
  symbol~ : StringView = "message",
  session? : Session,
) -> Unit raise @term.TermError {
  stream_chunks(symbol, chunks, session)
}

///|
pub async fn stream_info(
  chunks : Array[String],
  session? : Session,
) -> Unit raise @term.TermError {
  stream_chunks("info", chunks, session)
}

///|
pub async fn stream_success(
  chunks : Array[String],
  session? : Session,
) -> Unit raise @term.TermError {
  stream_chunks("success", chunks, session)
}

///|
pub async fn stream_step(
  chunks : Array[String],
  session? : Session,
) -> Unit raise @term.TermError {
  stream_chunks("step", chunks, session)
}

///|
pub async fn stream_warn(
  chunks : Array[String],
  session? : Session,
) -> Unit raise @term.TermError {
  stream_chunks("warn", chunks, session)
}

///|
pub async fn stream_warning(
  chunks : Array[String],
  session? : Session,
) -> Unit raise @term.TermError {
  stream_warn(chunks, session?)
}

///|
pub async fn stream_error(
  chunks : Array[String],
  session? : Session,
) -> Unit raise @term.TermError {
  stream_chunks("error", chunks, session)
}
