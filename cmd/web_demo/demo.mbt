///|
priv struct WebWizardState {
  name : String
  target : String
}

///|
/// Run the full interactive Clack demo on any `CallbackTerminal` (used by both
/// `--target js` `xterm.js` browser embeds and `--target wasm` host integrations).
pub async fn run_demo_on_callback(
  term : @clack.CallbackTerminal,
  minimal~ : Bool = false,
) -> Unit {
  let session = if minimal {
    @clack.Session(
      term~,
      theme=@clack.MinimalTheme(),
      color_level=TrueColor,
      with_guide=false,
    )
  } else {
    @clack.Session(
      term~,
      theme=@clack.ClackTheme(),
      color_level=TrueColor,
      with_guide=true,
    )
  }
  try {
    @clack.intro("unmbt/clack · xterm.js Live Demo", session~)
    let init : WebWizardState = { name: "", target: "native", }
    let steps : Array[@clack.Step[WebWizardState]] = [
      @clack.Step("name", (st, s, allow_back) => {
        match
          @clack.text(
            "Package name",
            placeholder="my-clack-cli",
            default_value="my-clack-cli",
            initial_value=st.name,
            allow_back~,
            session=s,
          ) {
          Submitted(name) => Submitted({ ..st, name, })
          Cancelled => Cancelled
          StepBack => StepBack
        }
      }),
      @clack.Step("target", (st, s, allow_back) => {
        match
          @clack.select(
            "Pick target (Shift+Tab to go back)",
            [
              @clack.SelectOption(
                "native",
                "Native",
                hint="zero-dependency binary",
              ),
              @clack.SelectOption("js", "JavaScript", hint="Node / xterm.js"),
              @clack.SelectOption("wasm", "WebAssembly", hint="WASI"),
            ],
            allow_back~,
            session=s,
          ) {
          Submitted(target) => Submitted({ ..st, target, })
          Cancelled => Cancelled
          StepBack => StepBack
        }
      }),
    ]
    match @clack.run_wizard(init, steps, session~) {
      Submitted(cfg) => {
        let _ = @clack.with_spinner(
          "Preparing \{cfg.name}",
          _ => @async.sleep(300),
          done_message="Ready (\{cfg.target})",
          session~,
        )
        @clack.outro("Demo complete!", session~)
      }
      Cancelled | StepBack => @clack.cancel(session~)
    }
  } catch {
    _ => ()
  }
}
