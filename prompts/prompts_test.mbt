///|
async test "prompts: Bracketed Paste across text + confirm does not leak 'y' into confirm" {
  let vt = @term.VirtualTerminal([
    b"\x1b[200~demo-pkg\r\ny\r\n\x1b[201~", b"\r", b"n",
  ])
  let session = @prompts.Session(term=vt, color_level=None)
  let r1 = @prompts.text("Project name", session~)
  let r2 = @prompts.confirm("Initialize git?", initial_value=true, session~)
  debug_inspect(r1, content="Submitted(\"demo-pkg y\")")
  debug_inspect(r2, content="Submitted(false)")
  inspect(vt.in_raw_mode(), content="false")
}

///|
async test "prompts: cancel() without message uses session.cancel_message (upstream #643)" {
  let vt = @term.VirtualTerminal([])
  let session = @prompts.Session(term=vt, color_level=None)
  @prompts.cancel(session~)
  inspect(vt.all_output(), content="└  Canceled\n\n")

  let vt2 = @term.VirtualTerminal([])
  let session2 = @prompts.Session(
    term=vt2,
    color_level=None,
    cancel_message="Aborted by user",
  )
  @prompts.cancel(session=session2)
  inspect(vt2.all_output(), content="└  Aborted by user\n\n")
}

///|
async test "prompts: non-interactive CI UseDefaults vs Fail policy" {
  let vt_default = @term.VirtualTerminal([], tty=false)
  let s_def = @prompts.Session(term=vt_default, non_interactive=UseDefaults)
  debug_inspect(
    @prompts.text("Name", default_value="auto-pkg", session=s_def),
    content="Submitted(\"auto-pkg\")",
  )
  debug_inspect(
    @prompts.confirm("Publish?", initial_value=false, session=s_def),
    content="Submitted(false)",
  )
  debug_inspect(
    @prompts.select(
      "Target",
      [
        @core.SelectOption("a", "A", disabled=true),
        @core.SelectOption("b", "B"),
      ],
      session=s_def,
    ),
    content="Submitted(\"b\")",
  )

  // Missing default in UseDefaults raises NotInteractive
  let missing_err = try {
    ignore(@prompts.text("Required without default", session=s_def))
    false
  } catch {
    NotInteractive(_) => true
    _ => false
  }
  inspect(missing_err, content="true")

  // Fail policy raises NotInteractive even with default_value
  let s_fail = @prompts.Session(term=vt_default, non_interactive=Fail)
  let fail_err = try {
    ignore(@prompts.text("Name", default_value="x", session=s_fail))
    false
  } catch {
    NotInteractive(_) => true
    _ => false
  }
  inspect(fail_err, content="true")
}

///|
async test "prompts: group_multiselect whole-group toggle & narrow viewport rows=10" {
  let vt = @term.VirtualTerminal([b" ", b"\r"], cols=60, rows=10)
  let session = @prompts.Session(term=vt, color_level=None)
  let res = @prompts.group_multiselect(
    "Packages to bump",
    [
      @core.GroupOption("Changed", [
        @core.SelectOption("core", "core"),
        @core.SelectOption("cli", "cli"),
      ]),
      @core.GroupOption("Unchanged", [@core.SelectOption("docs", "docs")]),
    ],
    session~,
  )
  debug_inspect(res, content="Submitted([\"core\", \"cli\"])")
}

///|
async test "prompts: Spinner resize reflow (upstream #645), non-TTY fallback, and Progress" {
  // 1. Animated spinner with resize mid-flight (upstream #645)
  let vt = @term.VirtualTerminal([], cols=80, rows=24, tty=true)
  let s = @prompts.Session(term=vt, color_level=None)
  let sp = @prompts.Spinner(session=s)
  sp.start("Downloading toolchain packages for MoonBit")
  vt.set_size(24, 24)
  sp.tick()
  sp.stop(message="Installed")
  let out = vt.all_output()
  // Resize emitted line-clear and final frame committed with ◇  Installed
  inspect(out.contains("\r\u{001b}[2K"), content="true")
  inspect(out.contains("◇  Installed"), content="true")
  inspect(out.contains("\u{001b}[?25h"), content="true")

  // 2. Non-TTY spinner & progress emit static logs with zero background timers
  let vt_ci = @term.VirtualTerminal([], tty=false)
  let s_ci = @prompts.Session(term=vt_ci, color_level=None)
  let val = @prompts.with_spinner(
    "Building",
    fn(spinner) {
      spinner.message("Linking")
      42
    },
    done_message="Built",
    session=s_ci,
  )
  inspect(val, content="42")
  inspect(vt_ci.all_output().contains("◇  Built"), content="true")

  let prog = @prompts.Progress(total=4, width=10, session=s_ci)
  prog.start(message="Uploading")
  prog.advance(delta=2)
  prog.message("Almost done")
  prog.stop(message="Uploaded")
  inspect(vt_ci.all_output().contains("100% Uploaded"), content="true")
}

///|
async test "prompts: with_spinner on TTY CallbackTerminal cancels cleanly and restores terminal" {
  let out : Array[String] = []
  let ct = @term.CallbackTerminal(
    on_write=fn(s) { out.push(s.to_owned()) },
    cols=60,
    rows=20,
    tty=true,
  )
  let s = @prompts.Session(term=ct, color_level=None)
  // Feed stray keypress 'a' that must be silently ignored while spinner runs
  ct.push_text("a")
  let res = @async.with_timeout_opt(40, () => {
    @prompts.with_spinner(
      "Long work",
      _ => {
        @async.sleep(500)
        1
      },
      interval_ms=15,
      session=s,
    )
  })
  debug_inspect(res, content="None")
  inspect(ct.in_raw_mode(), content="false")
  let joined = out.join("")
  inspect(joined.contains("\u{001b}[?25h"), content="true")
  inspect(joined.contains("■  Canceled"), content="true")
}

///|
async test "prompts: async validate renders Validating phase, rejects, then accepts" {
  let vt = @term.VirtualTerminal([b"bad\r", b"\x7f\x7f\x7fok\r"])
  let s = @prompts.Session(term=vt, color_level=None)
  let res = @prompts.text(
    "Package name",
    validate_async=async fn(v) {
      @async.pause()
      if v == "bad" {
        Some("Name already taken")
      } else {
        None
      }
    },
    session=s,
  )
  debug_inspect(res, content="Submitted(\"ok\")")
  let out = vt.all_output()
  inspect(out.contains("Validating..."), content="true")
  inspect(out.contains("Name already taken"), content="true")
}

///|
async test "prompts: select_key, autocomplete_multiselect, multiline, and date" {
  // select_key
  let vt_sk = @term.VirtualTerminal([b"c"])
  let s_sk = @prompts.Session(term=vt_sk, color_level=None)
  let sk = @prompts.select_key(
    "Action",
    [
      @core.SelectKeyOption("c", "continue", "Continue"),
      @core.SelectKeyOption("a", "abort", "Abort"),
    ],
    session=s_sk,
  )
  debug_inspect(sk, content="Submitted(\"continue\")")

  // autocomplete_multiselect: Down + Space to toggle first, Enter to submit
  let vt_am = @term.VirtualTerminal([b"\t\r"])
  let s_am = @prompts.Session(term=vt_am, color_level=None)
  let am = @prompts.autocomplete_multiselect(
    "Pick tags",
    [@core.SelectOption("cli", "CLI"), @core.SelectOption("web", "Web")],
    required=true,
    session=s_am,
  )
  debug_inspect(am, content="Submitted([\"cli\"])")

  // multiline: "hi" + Enter + "ok" + Enter + Enter
  let vt_ml = @term.VirtualTerminal([b"hi\rok\r\r"])
  let s_ml = @prompts.Session(term=vt_ml, color_level=None)
  let ml = @prompts.multiline("Description", session=s_ml)
  debug_inspect(ml, content="Submitted(\"hi\\nok\")")

  // date: type 2026 11 27 + Enter
  let vt_dt = @term.VirtualTerminal([b"20261127\r"])
  let s_dt = @prompts.Session(term=vt_dt, color_level=None)
  let dt = @prompts.date("Release date", session=s_dt)
  debug_inspect(dt, content="Submitted({ year: 2026, month: 11, day: 27 })")
}

///|
async test "prompts: box, note format, log_warning, tasks, task_log, and stream" {
  let vt = @term.VirtualTerminal([], cols=40, tty=false)
  let s = @prompts.Session(term=vt, color_level=None)
  @prompts.box("hello world", title="Notice", rounded=true, session=s)
  @prompts.note("Summary", "a long line", format=fn(l) { "> " + l }, session=s)
  @prompts.log_warning("Heads up", session=s)
  @prompts.tasks(
    [
      @prompts.Task("Step 1", fn(_) { Some("Step 1 done") }),
      @prompts.Task("Skipped", fn(_) { None }, enabled=false),
    ],
    session=s,
  )
  let tl = @prompts.TaskLog(title="Building project", limit=2, session=s)
  tl.message("line 1\u{001b}[2J")
  tl.message("line 2")
  tl.message("line 3")
  let grp = tl.group("Subtask")
  grp.message("sub-line")
  grp.success("Subtask ok")
  tl.success("Build ok", show_log=true)
  @prompts.stream_info(["chunk-1 ", "chunk-2"], session=s)
  let out = vt.all_output()
  inspect(out.contains("╭"), content="true")
  inspect(out.contains("> a long line"), content="true")
  inspect(out.contains("▲  Heads up"), content="true")
  inspect(out.contains("Step 1 done"), content="true")
  inspect(out.contains("Skipped"), content="false")
  inspect(out.contains("Build ok"), content="true")
  inspect(out.contains("\u{001b}[2J"), content="false")
  inspect(out.contains("chunk-1 chunk-2"), content="true")
}

///|
async test "prompts: path_with mocked filesystem completion and directory mode" {
  let vt = @term.VirtualTerminal([b"\r"])
  let s = @prompts.Session(term=vt, color_level=None)
  let res = @prompts.path_with(
    "Select entry",
    root="/app",
    directory=true,
    exists=fn(p) { p == "/app" || p == "/app/src" },
    is_dir=fn(p) { p == "/app" || p == "/app/src" },
    list_dir=fn(d) {
      if d == "/app" {
        [
          @prompts.PathEntry("/app/README.md", false),
          @prompts.PathEntry("/app/src", true),
        ]
      } else {
        [@prompts.PathEntry("/app", true)]
      }
    },
    session=s,
  )
  debug_inspect(res, content="Submitted(\"/app\")")
}

///|
async test "prompts: Spinner::clear and Progress::cancel/clear + accessible mode" {
  let vt = @term.VirtualTerminal([], tty=true)
  let s = @prompts.Session(term=vt, color_level=None, accessible=true)
  let sp = @prompts.Spinner(session=s)
  sp.start("Working")
  sp.clear()
  let prog = @prompts.Progress(total=10, session=s)
  prog.start(message="Copying")
  prog.cancel(message="Aborted")
  inspect(prog.is_cancelled(), content="true")
  prog.clear()
  let out = vt.all_output()
  inspect(out.contains("Working"), content="true")
  inspect(out.contains("■  "), content="true")
  inspect(out.contains("Aborted"), content="true")
}
