///|
async test "minimal: renders compact single-line MinimalTheme output" {
  let vt = @term.VirtualTerminal([b"demo", b"\r", b"\x1b[B", b"\r"])
  let s = @minimal.minimal_session(term=vt, color_level=None)
  let name = @minimal.text("Project", session=s)
  let backend = @minimal.select(
    "Backend",
    [@core.SelectOption("native", "Native"), @core.SelectOption("wasm", "Wasm")],
    session=s,
  )
  debug_inspect(name, content="Submitted(\"demo\")")
  debug_inspect(backend, content="Submitted(\"wasm\")")
  let output = vt.all_output()
  inspect(output.contains("✔ Project · demo"), content="true")
  inspect(output.contains("❯ Wasm"), content="true")
  inspect(output.contains("✔ Backend · Wasm"), content="true")
}

///|
async test "minimal: supports select_key, date, and box" {
  let vt = @term.VirtualTerminal([b"y", b"20261127\r"])
  let s = @minimal.minimal_session(term=vt, color_level=None)
  let action = @minimal.select_key(
    "Proceed",
    [
      @core.SelectKeyOption("y", "yes", "Yes"),
      @core.SelectKeyOption("n", "no", "No"),
    ],
    session=s,
  )
  let dt = @minimal.date("Date", session=s)
  @minimal.box("Minimal box", title="Info", rounded=true, session=s)
  debug_inspect(action, content="Submitted(\"yes\")")
  debug_inspect(dt, content="Submitted({ year: 2026, month: 11, day: 27 })")
  let output = vt.all_output()
  inspect(output.contains("✔ Proceed · Yes"), content="true")
  inspect(output.contains("✔ Date · 2026/11/27"), content="true")
  inspect(output.contains("Minimal box"), content="true")
}
