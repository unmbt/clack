///|
async fn simulated_prompt_session(
  term : &@term.Terminal,
) -> String raise @term.TermError {
  term.enter_raw_mode()
  term.write_str("\u{001b}[?25l\u{001b}[?2004h")
  defer (try {
    term.write_final("\u{001b}[?2004l\u{001b}[?25h\u{001b}[?2026l")
    term.leave_raw_mode()
  } catch {
    _ => ()
  })
  let dec = @core.KeyDecoder()
  for ;; {
    let chunk_opt : Bytes? = if dec.has_pending_escape() {
      let waited : Bytes?? = @async.with_timeout_opt(20, () => term.read_bytes()) catch {
        @term.TermError::IoFailure(msg) => raise IoFailure(msg)
        @term.TermError::NotInteractive(msg) => raise NotInteractive(msg)
        @term.TermError::EndOfInput => raise EndOfInput
        err => raise IoFailure("\{Repr(err)}")
      }
      match waited {
        Some(res) => res
        None =>
          match dec.flush_escape() {
            Some(ev) if ev.code == Escape => return "escaped"
            _ => continue
          }
      }
    } else {
      term.read_bytes()
    }
    match chunk_opt {
      None => return "eof"
      Some(bytes) => {
        let events = dec.feed(bytes[:])
        for ev in events {
          if ev.ctrl && ev.code == Char('c') {
            return "cancelled"
          }
          if ev.code == Enter {
            return "submitted"
          }
          if ev.code == Up {
            return "up"
          }
        }
      }
    }
  }
}

///|
async test "VirtualTerminal: normal submit & Ctrl+C restore raw mode and emit cleanup sequence" {
  let vt1 = @term.VirtualTerminal([b"hello", b"\r"])
  let r1 = simulated_prompt_session(vt1)
  inspect(r1, content="submitted")
  inspect(vt1.in_raw_mode(), content="false")
  let frames1 = vt1.frames()
  inspect(
    frames1[frames1.length() - 1],
    content="\u{001b}[?2004l\u{001b}[?25h\u{001b}[?2026l",
  )

  let vt2 = @term.VirtualTerminal([b"\x03"])
  let r2 = simulated_prompt_session(vt2)
  inspect(r2, content="cancelled")
  inspect(vt2.in_raw_mode(), content="false")
  let frames2 = vt2.frames()
  inspect(
    frames2[frames2.length() - 1],
    content="\u{001b}[?2004l\u{001b}[?25h\u{001b}[?2026l",
  )
}

///|
async test "CallbackTerminal: push_text, set_size, Esc 20ms disambiguation, and with_timeout cancellation cleanup" {
  let captured : Array[String] = []
  let ct = @term.CallbackTerminal(
    on_write=fn(s) { captured.push(s.to_owned()) },
    cols=100,
    rows=30,
  )
  debug_inspect(ct.size(), content="(100, 30)")
  ct.set_size(60, 18)
  debug_inspect(ct.size(), content="(60, 18)")

  // 1. Bare ESC times out after 20ms -> flushed as Escape
  ct.push_text("\u{001b}")
  let res_esc = simulated_prompt_session(ct)
  inspect(res_esc, content="escaped")
  inspect(ct.in_raw_mode(), content="false")

  // 2. External with_timeout cancellation while awaiting read_bytes() must run defer + nocancel cleanup
  captured.clear()
  let timed_out = @async.with_timeout_opt(25, () => simulated_prompt_session(ct))
  debug_inspect(timed_out, content="None")
  inspect(ct.in_raw_mode(), content="false")
  inspect(
    captured[captured.length() - 1],
    content="\u{001b}[?2004l\u{001b}[?25h\u{001b}[?2026l",
  )
}
