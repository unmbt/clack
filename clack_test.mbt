///|
#derive(Debug)
priv struct ScaffoldConfig {
  project_name : String
  use_advanced : Bool
  target : String
}

///|
async test "root @clack facade: end-to-end wizard with StepBack, Bracketed Paste, and Clack visual flow" {
  let vt = @clack.VirtualTerminal([
    b"\x1b[200~my-cli\r\nextra\r\n\x1b[201~", b"\r", b"n", b"\x1b[Z", b"y", b"\r",
  ])
  let session = @clack.Session(term=vt, color_level=None)
  @clack.intro("create-moon-app", session~)
  let init : ScaffoldConfig = {
    project_name: "",
    use_advanced: false,
    target: "native",
  }
  let steps : Array[@clack.Step[ScaffoldConfig]] = [
    @clack.Step("name", (st, s, allow_back) => {
      match
        @clack.text(
          "Project name",
          initial_value=st.project_name,
          allow_back~,
          session=s,
        ) {
        Submitted(name) => Submitted({ ..st, project_name: name, })
        Cancelled => Cancelled
        StepBack => StepBack
      }
    }),
    @clack.Step("advanced", (st, s, allow_back) => {
      match
        @clack.confirm(
          "Enable advanced mode?",
          initial_value=st.use_advanced,
          allow_back~,
          session=s,
        ) {
        Submitted(flag) => Submitted({ ..st, use_advanced: flag, })
        Cancelled => Cancelled
        StepBack => StepBack
      }
    }),
    @clack.Step("target", (st, s, allow_back) => {
      match
        @clack.select(
          "Target backend",
          [
            @clack.SelectOption("native", "Native"),
            @clack.SelectOption("js", "JavaScript"),
          ],
          allow_back~,
          session=s,
        ) {
        Submitted(t) => Submitted({ ..st, target: t, })
        Cancelled => Cancelled
        StepBack => StepBack
      }
    }),
  ]
  let outcome = @clack.run_wizard(init, steps, session~)
  debug_inspect(
    outcome,
    content="Submitted({ project_name: \"my-cli extra\", use_advanced: true, target: \"native\" })",
  )
  @clack.outro("All set!", session~)
  let rendered = vt.all_output()
  inspect(rendered.contains("┌  create-moon-app"), content="true")
  inspect(rendered.contains("└  All set!"), content="true")
  inspect(vt.in_raw_mode(), content="false")
}
