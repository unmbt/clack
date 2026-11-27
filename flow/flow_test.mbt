///|
#derive(Debug)
priv struct WizardState {
  name : String
  need_ts : Bool
  target : String
}

///|
async test "flow::run_wizard: StepBack jumps over skipped conditional step and preserves prior state" {
  // Step 1: type "app1" + Enter -> Step 2 skipped (when=false) ->
  // Step 3: press Shift+Tab (\x1b[Z) -> jumps straight back to Step 1 with initial_value="app1" ->
  // backspace 1 char, type "2" + Enter -> Step 2 still skipped -> Step 3: Down + Enter ("wasm")
  let vt = @term.VirtualTerminal([
    b"app1", b"\r", b"\x1b[Z", b"\x7f", b"2", b"\r", b"\x1b[B", b"\r",
  ])
  let s = @prompts.Session(term=vt, color_level=None)
  let init : WizardState = { name: "", need_ts: false, target: "", }
  let step1_initials : Array[String] = []
  let steps : Array[@flow.Step[WizardState]] = [
    @flow.Step("name", (st, sess, allow_back) => {
      step1_initials.push(st.name)
      match
        @prompts.text(
          "Project name",
          initial_value=st.name,
          allow_back~,
          session=sess,
        ) {
        Submitted(v) => Submitted({ ..st, name: v, })
        Cancelled => Cancelled
        StepBack => StepBack
      }
    }),
    @flow.Step("ts-only", when=fn(st) { st.need_ts }, (st, sess, allow_back) => {
      match @prompts.confirm("Enable strict?", allow_back~, session=sess) {
        Submitted(_) => Submitted(st)
        Cancelled => Cancelled
        StepBack => StepBack
      }
    }),
    @flow.Step("target", (st, sess, allow_back) => {
      match
        @prompts.select(
          "Build target",
          [
            @core.SelectOption("native", "Native"),
            @core.SelectOption("wasm", "Wasm"),
          ],
          allow_back~,
          session=sess,
        ) {
        Submitted(t) => Submitted({ ..st, target: t, })
        Cancelled => Cancelled
        StepBack => StepBack
      }
    }),
  ]
  // On StepBack from Step 3, Step 1 receives prior filled name="app1" as initial_value,
  // backspace deletes '1' -> "app", typing '2' -> "app2"
  let res = @flow.run_wizard(init, steps, session=s)
  debug_inspect(
    res,
    content="Submitted({ name: \"app2\", need_ts: false, target: \"wasm\" })",
  )
  debug_inspect(step1_initials, content="[\"\", \"app1\"]")
}
