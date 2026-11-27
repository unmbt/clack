///|
fn ev(code : @core.KeyCode) -> @core.KeyEvent {
  { code, ctrl: false, alt: false, shift: false, }
}

///|
fn ctrl_c() -> @core.KeyEvent {
  { code: Char('c'), ctrl: true, alt: false, shift: false, }
}

///|
test "KeyDecoder: arrows, Shift+Tab, Ctrl+C, Esc 20ms disambiguation" {
  let dec = @core.KeyDecoder()
  // Arrows + Shift+Tab + Ctrl+C
  let seq = dec.feed(b"\x1b[A\x1b[B\x1b[C\x1b[D\x1b[Z\x03")
  debug_inspect(
    seq.map(e => (e.code, e.ctrl, e.shift)),
    content=(
      #|[
      #|  (Up, false, false),
      #|  (Down, false, false),
      #|  (Right, false, false),
      #|  (Left, false, false),
      #|  (BackTab, false, true),
      #|  (Char('c'), true, false),
      #|]
    ),
  )

  // Bare ESC held pending until next chunk arrives -> CSI Up
  let e1 = dec.feed(b"\x1b")
  inspect(e1.length(), content="0")
  inspect(dec.has_pending_escape(), content="true")
  let e2 = dec.feed(b"[A")
  inspect(dec.has_pending_escape(), content="false")
  debug_inspect(e2.map(e => e.code), content="[Up]")

  // Bare ESC held pending then flushed via flush_escape() -> Escape
  let e3 = dec.feed(b"\x1b")
  inspect(e3.length(), content="0")
  inspect(dec.has_pending_escape(), content="true")
  debug_inspect(dec.flush_escape().map(e => e.code), content="Some(Escape)")
  inspect(dec.has_pending_escape(), content="false")
  debug_inspect(dec.flush_escape(), content="None")
}

///|
test "KeyDecoder: split multi-byte UTF-8 Chinese and Bracketed Paste" {
  let dec = @core.KeyDecoder()
  // "脚手架" UTF-8 bytes: E8 84 9A | E6 89 8B | E6 9E B6 (9 bytes), split into 2-byte chunks
  let full = b"\xe8\x84\x9a\xe6\x89\x8b\xe6\x9e\xb6"
  let out : Array[Char] = []
  let mut i : Int32 = 0
  while i < full.length() {
    let end = if i + 2 < full.length() { i + 2 } else { full.length() }
    for e in dec.feed(full[i:end]) {
      match e.code {
        Char(c) => out.push(c)
        _ => ()
      }
    }
    i = end
  }
  inspect(String::from_array(out), content="脚手架")

  // Bracketed Paste across chunks must yield ONE Paste event and ZERO Enter events
  let p1 = dec.feed(b"\x1b[200~my-app\r\n")
  inspect(p1.length(), content="0")
  let p2 = dec.feed(b"yes\r\n\x1b[201~")
  debug_inspect(
    p2.map(e => e.code),
    content="[Paste(\"my-app\\r\\nyes\\r\\n\")]",
  )

  // Unclosed Bracketed Paste safety escape on Ctrl+C (0x03)
  let u1 = dec.feed(b"\x1b[200~stuck-paste-without-end")
  inspect(u1.length(), content="0")
  let u2 = dec.feed(b"\x03a")
  debug_inspect(
    u2.map(e => (e.code, e.ctrl)),
    content="[(Char('c'), true), (Char('a'), false)]",
  )
}

///|
test "TextModel & PasswordModel: CJK editing, Paste CRLF sanitization, Tab, StepBack" {
  let tm = @core.TextModel(
    "Project name",
    placeholder="my-app",
    default_value="fallback-app",
    validate=fn(s) { if s.length() < 3 { Some("Too short") } else { None } },
  )
  // Tab fills placeholder when empty
  ignore(tm.on_key(ev(Tab)))
  inspect(tm.value(), content="my-app")
  // Insert Chinese in the middle via cursor movement
  ignore(tm.on_key(ev(Home)))
  ignore(tm.on_key(ev(Right)))
  ignore(tm.on_key(ev(Char('中'))))
  inspect(tm.value(), content="m中y-app")
  ignore(tm.on_key(ev(Backspace)))
  inspect(tm.value(), content="my-app")
  // Paste with CRLF collapses internal newlines to space and trims trailing newline
  ignore(tm.on_key(ev(End)))
  ignore(tm.on_key(ev(Paste("\r\nline2\r\n"))))
  inspect(tm.value(), content="my-app line2")
  debug_inspect(
    tm.on_key(ev(Enter)),
    content="Some(Submitted(\"my-app line2\"))",
  )

  // PasswordModel strips ALL CR/LF from paste and masks output
  let pm = @core.PasswordModel("API Token", clear_on_error=true, validate=fn(
    s,
  ) {
    if s.length() < 4 {
      Some("Min 4 chars")
    } else {
      None
    }
  })
  ignore(pm.on_key(ev(Paste("ab\r\ncd\n"))))
  inspect(pm.masked(), content="▪▪▪▪")
  debug_inspect(pm.on_key(ev(Enter)), content="Some(Submitted(\"abcd\"))")

  // StepBack with allow_back=true
  let tm2 = @core.TextModel("Step 2")
  debug_inspect(
    tm2.on_key(ev(BackTab), allow_back=true),
    content="Some(StepBack)",
  )
  debug_inspect(tm2.view().phase, content="Reverted")
}

///|
test "ConfirmModel: y/n immediate submit, arrow toggle, Paste no-op" {
  let cm = @core.ConfirmModel("Continue?", initial_value=true)
  ignore(cm.on_key(ev(Paste("n\r\n"))))
  inspect(cm.value(), content="true")
  ignore(cm.on_key(ev(Right)))
  inspect(cm.value(), content="false")
  debug_inspect(cm.on_key(ev(Char('y'))), content="Some(Submitted(true))")
}

///|
test "SelectModel: disabled skipping and all-disabled safety" {
  let opts = [
    @core.SelectOption("a", "Alpha", disabled=true),
    @core.SelectOption("b", "Beta", hint="recommended"),
    @core.SelectOption("c", "Gamma", disabled=true),
    @core.SelectOption("d", "Delta"),
  ]
  let sm = @core.SelectModel("Pick one", opts)
  inspect(sm.cursor(), content="1")
  // Down skips disabled index 2 -> lands on 3
  ignore(sm.on_key(ev(Down)))
  inspect(sm.cursor(), content="3")
  // Down wraps around skipping disabled index 0 -> lands on 1
  ignore(sm.on_key(ev(Down)))
  inspect(sm.cursor(), content="1")
  debug_inspect(sm.on_key(ev(Enter)), content="Some(Submitted(\"b\"))")

  // Empty & all-disabled must NOT infinite-loop
  let empty_sm : @core.SelectModel[String] = @core.SelectModel("Empty", [])
  inspect(empty_sm.has_selectable_options(), content="false")
  debug_inspect(empty_sm.on_key(ev(Enter)), content="None")
  debug_inspect(
    empty_sm.view().phase,
    content="Error(\"No selectable options available\")",
  )
}

///|
test "MultiSelectModel & GroupMultiSelectModel: Space, ideographic space, a/i, required, group toggle" {
  let opts = [
    @core.SelectOption("ts", "TypeScript"),
    @core.SelectOption("mbt", "MoonBit"),
    @core.SelectOption("dis", "Disabled", disabled=true),
  ]
  let ms = @core.MultiSelectModel("Pick languages", opts, required=true)
  // Enter with nothing selected -> Warning
  debug_inspect(ms.on_key(ev(Enter)), content="None")
  debug_inspect(
    ms.view().phase,
    content="Warning(\"Please select at least one option.\")",
  )
  // Navigation clears warning; ideographic space toggles selection
  ignore(ms.on_key(ev(Down)))
  debug_inspect(ms.view().phase, content="Active")
  ignore(ms.on_key(ev(Char('\u{3000}'))))
  debug_inspect(ms.selected_indices(), content="[1]")
  // 'i' inverts enabled options (disabled stays unselected)
  ignore(ms.on_key(ev(Char('i'))))
  debug_inspect(ms.selected_indices(), content="[0]")
  // 'a' selects all enabled options
  ignore(ms.on_key(ev(Char('a'))))
  debug_inspect(ms.selected_indices(), content="[0, 1]")
  debug_inspect(
    ms.on_key(ev(Enter)),
    content="Some(Submitted([\"ts\", \"mbt\"]))",
  )

  // GroupMultiSelectModel whole-group toggle on header
  let groups = [
    @core.GroupOption("Changed", [
      @core.SelectOption("pkg-a", "pkg-a"),
      @core.SelectOption("pkg-b", "pkg-b"),
    ]),
    @core.GroupOption("Unchanged", [@core.SelectOption("pkg-c", "pkg-c")]),
  ]
  let gms = @core.GroupMultiSelectModel("Select packages", groups)
  // Cursor starts at row 0 ("Changed" header); Space toggles both pkg-a and pkg-b
  ignore(gms.on_key(ev(Space)))
  debug_inspect(gms.selected_indices(), content="[0, 1]")
  // Second Space unselects whole group
  ignore(gms.on_key(ev(Space)))
  debug_inspect(gms.selected_indices(), content="[]")
  // Select again and submit
  ignore(gms.on_key(ev(Space)))
  debug_inspect(
    gms.on_key(ev(Enter)),
    content="Some(Submitted([\"pkg-a\", \"pkg-b\"]))",
  )
}

///|
test "AutocompleteModel: j/k/a/i/Space type into search without mis-navigating" {
  let opts = [
    @core.SelectOption("js", "JavaScript", hint="dynamic"),
    @core.SelectOption("kt", "Kotlin", hint="jvm"),
    @core.SelectOption("mbt", "MoonBit", hint="fast"),
  ]
  let ac = @core.AutocompleteModel("Search lang", opts, placeholder="MoonBit")
  // Typing 'k' filters to Kotlin instead of moving cursor up
  ignore(ac.on_key(ev(Char('k'))))
  inspect(ac.query(), content="k")
  inspect(ac.filtered_count(), content="1")
  // Typing Space & 'j' appends to search box -> no matches
  ignore(ac.on_key(ev(Space)))
  ignore(ac.on_key(ev(Char('j'))))
  inspect(ac.query(), content="k j")
  inspect(ac.filtered_count(), content="0")
  // Clear via backspaces and use Tab to fill placeholder "MoonBit"
  ignore(ac.on_key(ev(Backspace)))
  ignore(ac.on_key(ev(Backspace)))
  ignore(ac.on_key(ev(Backspace)))
  ignore(ac.on_key(ev(Tab)))
  inspect(ac.query(), content="MoonBit")
  debug_inspect(ac.on_key(ev(Enter)), content="Some(Submitted(\"mbt\"))")
}

///|
test "limit_options: 30 items sliding window & ellipsis" {
  let items : Array[String] = []
  for i in 0..<30 {
    items.push("Option \{i}")
  }
  let top_view = @core.limit_options(items, 0, 80, 24, max_items=6)
  inspect(top_view.length(), content="6")
  inspect(top_view[0], content="Option 0")
  inspect(top_view[5], content="...")

  let mid_view = @core.limit_options(items, 15, 80, 24, max_items=6)
  inspect(mid_view.length(), content="6")
  inspect(mid_view[0], content="...")
  inspect(mid_view[5], content="...")
  inspect(mid_view.contains("Option 15"), content="true")
}

///|
test "ClackTheme 1:1 & MinimalTheme visual snapshots (Unicode and ASCII)" {
  let plain = @ansi.Styler(level=None)
  let clack = @core.ClackTheme()
  let clack_ascii = @core.ClackTheme(unicode=false)
  let minimal = @core.MinimalTheme()

  // Clack intro/outro/cancel/log/note
  inspect(
    clack.render_intro("create-moon-app", plain),
    content="┌  create-moon-app",
  )
  inspect(clack.render_outro("Done!", plain), content="│\n└  Done!\n")
  inspect(
    clack.render_cancel("Operation cancelled.", plain),
    content="└  Operation cancelled.\n",
  )
  inspect(
    clack.render_log("info", "Checking toolchain", plain),
    content="│\n●  Checking toolchain",
  )
  inspect(
    clack.render_note("Next steps", "moon build\nmoon test", plain),
    content="│\n◇  Next steps ─╮\n│              │\n│  moon build  │\n│  moon test   │\n│              │\n├──────────────╯",
  )

  // Clack Select Active & Submitted (Unicode vs ASCII)
  let sm = @core.SelectModel("Pick backend", [
    @core.SelectOption("native", "Native", hint="fast"),
    @core.SelectOption("wasm", "Wasm"),
  ])
  debug_inspect(
    clack.render_frame(sm.view(), plain, 80),
    content=(
      #|[
      #|  "│",
      #|  "◆  Pick backend",
      #|  "│  ● Native (fast)",
      #|  "│  ○ Wasm",
      #|  "│  ↑/↓ to navigate • Enter: confirm",
      #|  "└",
      #|]
    ),
  )
  debug_inspect(
    clack_ascii.render_frame(sm.view(), plain, 80),
    content=(
      #|[
      #|  "|",
      #|  "*  Pick backend",
      #|  "|  > Native (fast)",
      #|  "|    Wasm",
      #|  "|  Up/Down to navigate | Enter: confirm",
      #|  "—",
      #|]
    ),
  )
  ignore(sm.on_key(ev(Enter)))
  debug_inspect(
    clack.render_frame(sm.view(), plain, 80),
    content="[\"│\", \"◇  Pick backend\", \"│  Native\"]",
  )

  // MinimalTheme Active & Submitted
  let cm = @core.ConfirmModel("Deploy?", initial_value=true)
  debug_inspect(
    minimal.render_frame(cm.view(), plain, 80),
    content="[\"? Deploy? › Yes / No\"]",
  )
  ignore(cm.on_key(ev(Enter)))
  debug_inspect(
    minimal.render_frame(cm.view(), plain, 80),
    content="[\"✔ Deploy? · Yes\"]",
  )
}

///|
test "InlineDiffRenderer & InlineDriver: expand/shrink, short-circuit, CJK wrap, push-mode end-to-end" {
  let r = @core.InlineDiffRenderer()
  // Frame 1: 1 line
  let f1 = r.patch(["line1"], 40, sync_output=true)
  inspect(f1, content="\u{001b}[?2026hline1\u{001b}[?2026l")
  // Identical frame short-circuits to empty string
  inspect(r.patch(["line1"], 40, sync_output=true), content="")
  // Expand 1 -> 5 lines (cursor was on row 1, so no up-move needed, just \r\x1b[J)
  let f2 = r.patch(["a", "b", "c", "d", "e"], 40, sync_output=false)
  inspect(f2, content="\r\u{001b}[Ja\r\nb\r\nc\r\nd\r\ne")
  // Shrink 5 -> 2 lines -> moves up 4 rows
  let f3 = r.patch(["x", "y"], 40, sync_output=false)
  inspect(f3, content="\u{001b}[4A\r\u{001b}[Jx\r\ny")
  // Narrow 10-col CJK line wraps to 2 physical rows -> next commit moves up 1 row
  ignore(r.patch(["你好世界你好"], 10, sync_output=false))
  let committed = r.commit(["done"], 10, sync_output=true)
  inspect(
    committed,
    content="\u{001b}[?2026h\u{001b}[1A\r\u{001b}[Jdone\r\n\u{001b}[?2026l",
  )

  // InlineDriver pure-sync push-mode full interaction
  let tm = @core.TextModel("Project", placeholder="demo")
  let driver = @core.InlineDriver(
    tm.as_adapter(),
    theme=@core.ClackTheme(),
    styler=@ansi.Styler(level=None),
    cols=60,
    rows=20,
    sync_output=false,
  )
  let init_frame = driver.start()
  inspect(init_frame.contains("◆  Project"), content="true")
  let (_o1, res1) = driver.feed(b"\x1b[200~hello\r\nworld\r\n\x1b[201~")
  debug_inspect(res1, content="None")
  let (final_frame, res2) = driver.feed(b"\r")
  debug_inspect(res2, content="Some(Submitted(\"hello world\"))")
  inspect(final_frame.contains("◇  Project"), content="true")
  inspect(final_frame.contains("hello world"), content="true")

  // Resize clears and re-renders cleanly on an active driver
  let sm = @core.SelectModel("Choose", [
    @core.SelectOption(1, "One"),
    @core.SelectOption(2, "Two"),
  ])
  let sdriver = @core.InlineDriver(
    sm.as_adapter(),
    styler=@ansi.Styler(level=None),
    sync_output=false,
  )
  ignore(sdriver.start())
  let resized = sdriver.resize(40, 12)
  inspect(resized.has_prefix("\r\u{001b}[2K"), content="true")
  let (_c, cancel_res) = sdriver.feed(b"\x03")
  debug_inspect(cancel_res, content="Some(Cancelled)")
  let _ = ctrl_c()
}

///|
test "ClackTheme 1:1 full widget matrix snapshots (Text, Password, Confirm vertical, MultiSelect, GroupMultiSelect, Autocomplete)" {
  let plain = @ansi.Styler(level=None)
  let color = @ansi.Styler(level=Ansi16)
  let clack = @core.ClackTheme()

  // Text: placeholder cursor (colored inverse first char + dim rest), error, submitted, cancelled
  let tm = @core.TextModel("What is your name?", placeholder="Jane Doe", validate=fn(
    s,
  ) {
    if s == "" {
      Some("Name is required")
    } else {
      None
    }
  })
  let text_colored = clack.render_frame(tm.view(), color, 80)
  // First placeholder char is inverse, rest is dim
  inspect(
    text_colored[2].contains(
      "\u{001b}[7mJ\u{001b}[27m\u{001b}[2mane Doe\u{001b}[22m",
    ),
    content="true",
  )
  ignore(tm.on_key(ev(Enter)))
  debug_inspect(
    clack.render_frame(tm.view(), plain, 80),
    content=(
      #|["│", "▲  What is your name?", "│  Jane Doe", "└  Name is required"]
    ),
  )
  ignore(tm.on_key(ev(Char('A'))))
  ignore(tm.on_key(ctrl_c()))
  let text_cancel_colored = clack.render_frame(tm.view(), color, 80)
  // Cancelled value has strikethrough + dim + trailing gray bar
  inspect(text_cancel_colored[2].contains("\u{001b}[9m"), content="true")
  inspect(text_cancel_colored.length(), content="4")

  // Password: mask vs hidden mode
  let pm = @core.PasswordModel("Secret")
  ignore(pm.on_key(ev(Char('x'))))
  ignore(pm.on_key(ev(Char('y'))))
  debug_inspect(
    clack.render_frame(pm.view(), plain, 80),
    content=(
      #|["│", "◆  Secret", "│  ▪▪_", "└"]
    ),
  )
  let pm_hidden = @core.PasswordModel("Hidden Secret", mask=None)
  ignore(pm_hidden.on_key(ev(Char('x'))))
  inspect(pm_hidden.masked(), content="")

  // Confirm vertical layout
  let cm_v = @core.ConfirmModel("Proceed?", initial_value=false, vertical=true)
  debug_inspect(
    clack.render_frame(cm_v.view(), plain, 80),
    content=(
      #|["│", "◆  Proceed?", "│  ○ Yes", "│  ● No", "└"]
    ),
  )

  // GroupMultiSelect tree rendering (│ and └ prefixes)
  let gms = @core.GroupMultiSelectModel("Select packages", [
    @core.GroupOption("Core", [
      @core.SelectOption("a", "ansi"),
      @core.SelectOption("c", "core"),
    ]),
    @core.GroupOption("Host", [@core.SelectOption("t", "term")]),
  ])
  ignore(gms.on_key(ev(Space)))
  debug_inspect(
    clack.render_frame(gms.view(), plain, 80),
    content=(
      #|[
      #|  "│",
      #|  "◆  Select packages",
      #|  "│  ◼ Core",
      #|  "│  │ ◼ ansi",
      #|  "│  └ ◼ core",
      #|  "│  ◻ Host",
      #|  "│  └ ◻ term",
      #|  "│  ↑/↓ to navigate • Space: select • Enter: confirm",
      #|  "└",
      #|]
    ),
  )

  // Autocomplete search, match badge, and No matches found
  let ac = @core.AutocompleteModel(
    "Search framework",
    [
      @core.SelectOption("mbt", "MoonBit", hint="fast"),
      @core.SelectOption("rs", "Rust", hint="systems"),
    ],
    placeholder="Type to search...",
    complete_on_tab=true,
  )
  ignore(ac.on_key(ev(Char('m'))))
  debug_inspect(
    clack.render_frame(ac.view(), plain, 80),
    content=(
      #|[
      #|  "│",
      #|  "◆  Search framework",
      #|  "│",
      #|  "│  Search: m█",
      #|  "│  ● MoonBit (fast)",
      #|  "│  ○ Rust",
      #|  "│  ↑/↓ to select • Tab: complete • Enter: confirm • Type: to search",
      #|  "└",
      #|]
    ),
  )
  ignore(ac.on_key(ev(Char('z'))))
  debug_inspect(
    clack.render_frame(ac.view(), plain, 80),
    content=(
      #|[
      #|  "│",
      #|  "◆  Search framework",
      #|  "│",
      #|  "│  Search: mz█ (0 matches)",
      #|  "│  No matches found",
      #|  "│  ↑/↓ to select • Tab: complete • Enter: confirm • Type: to search",
      #|  "└",
      #|]
    ),
  )
}

///|
test "PromptOutcome helpers, render_box, SelectKey, AutocompleteMultiSelect, MultiLine, Date" {
  // PromptOutcome ergonomic helpers
  let sub : @core.PromptOutcome[Int32] = Submitted(7)
  inspect(sub.is_submitted(), content="true")
  inspect(sub.is_cancelled(), content="false")
  inspect(sub.unwrap_or(0), content="7")
  let can : @core.PromptOutcome[Int32] = Cancelled
  inspect(can.is_cancelled(), content="true")
  inspect(can.unwrap_or(99), content="99")

  // render_box rounded & centered
  let boxed = @core.render_box(
    "Hello Clack",
    title="Box",
    styler=@ansi.Styler(level=None),
    content_align=Center,
    title_align=Center,
  )
  inspect(boxed.contains("╭"), content="true")
  inspect(boxed.contains("Hello Clack"), content="true")
  inspect(boxed.contains("╯"), content="true")

  // SelectKeyModel instant hotkey submit & disabled skip
  let sk = @core.SelectKeyModel("Quick action", [
    @core.SelectKeyOption("a", "abort", "Abort", disabled=true),
    @core.SelectKeyOption("c", "continue", "Continue", hint="default"),
    @core.SelectKeyOption("q", "quit", "Quit"),
  ])
  inspect(sk.cursor(), content="1")
  // Disabled key 'a' is ignored
  debug_inspect(sk.on_key(ev(Char('a'))), content="None")
  // Case-insensitive 'Q' immediately submits "quit"
  debug_inspect(sk.on_key(ev(Char('Q'))), content="Some(Submitted(\"quit\"))")

  // AutocompleteMultiSelectModel: filter + Tab toggle + navigating Space toggle
  let ams = @core.AutocompleteMultiSelectModel(
    "Pick frameworks",
    [
      @core.SelectOption("mbt", "MoonBit"),
      @core.SelectOption("ts", "TypeScript"),
      @core.SelectOption("rs", "Rust"),
    ],
    required=true,
  )
  debug_inspect(ams.on_key(ev(Enter)), content="None")
  ignore(ams.on_key(ev(Char('m'))))
  ignore(ams.on_key(ev(Tab)))
  ignore(ams.on_key(ev(Backspace)))
  ignore(ams.on_key(ev(Down)))
  ignore(ams.on_key(ev(Space)))
  debug_inspect(
    ams.on_key(ev(Enter)),
    content="Some(Submitted([\"mbt\", \"ts\"]))",
  )

  // MultiLineModel: astral emoji integrity (#641) + double-Enter submit
  let ml = @core.MultiLineModel("Bio")
  ignore(ml.on_key(ev(Char('a'))))
  ignore(ml.on_key(ev(Char('🚀'))))
  ignore(ml.on_key(ev(Enter)))
  ignore(ml.on_key(ev(Char('b'))))
  ignore(ml.on_key(ev(Enter)))
  debug_inspect(ml.on_key(ev(Enter)), content="Some(Submitted(\"a🚀\\nb\"))")

  // DateModel: leap-year validation (2024-02-29 valid, 2025-02-29 rejected) + min_date
  let dm = @core.DateModel(
    "Release date",
    format=Ymd,
    min_date=@core.SimpleDate(2024, 1, 1),
  )
  for ch in "20250229".to_array() {
    ignore(dm.on_key(ev(Char(ch))))
  }
  debug_inspect(dm.on_key(ev(Enter)), content="None")
  // Fix year to leap year 2024
  let dm_ok = @core.DateModel(
    "Release date",
    format=Ymd,
    min_date=@core.SimpleDate(2024, 1, 1),
  )
  for ch in "20240229".to_array() {
    ignore(dm_ok.on_key(ev(Char(ch))))
  }
  debug_inspect(
    dm_ok.on_key(ev(Enter)),
    content="Some(Submitted({ year: 2024, month: 2, day: 29 }))",
  )
}
