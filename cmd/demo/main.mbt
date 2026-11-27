///|
priv struct DemoState {
  project_name : String
  configure_packages : Bool
  packages : Array[String]
  target : String
  release_date : @clack.SimpleDate
}

///|
async fn main {
  let base_session = @clack.Session()
  @clack.intro(
    "unmbt/clack — interactive CLI wizard demo",
    session=base_session,
  )

  let theme_choice = @clack.select(
    "Choose visual theme",
    [
      @clack.SelectOption(
        "clack",
        "Clack Guide",
        hint="default @clack/prompts style",
      ),
      @clack.SelectOption(
        "minimal",
        "Minimal",
        hint="compact single-line style",
      ),
    ],
    session=base_session,
  )
  let use_minimal = match theme_choice {
    Submitted("minimal") => true
    Submitted(_) => false
    Cancelled | StepBack => {
      @clack.cancel(session=base_session)
      return
    }
  }

  let session = if use_minimal {
    @clack.Session(
      term=base_session.term,
      theme=@clack.MinimalTheme(unicode=base_session.unicode),
      with_guide=false,
      unicode=base_session.unicode,
    )
  } else {
    base_session
  }

  let init : DemoState = {
    project_name: "",
    configure_packages: true,
    packages: [],
    target: "native",
    release_date: @clack.SimpleDate(2026, 11, 27),
  }

  let steps : Array[@clack.Step[DemoState]] = [
    @clack.Step("name", (st, s, allow_back) => {
      match
        @clack.text(
          "Project name",
          placeholder="my-moon-app",
          default_value="my-moon-app",
          initial_value=st.project_name,
          validate=fn(v) {
            if v.trim() == "" {
              Some("Project name cannot be empty")
            } else {
              None
            }
          },
          allow_back~,
          session=s,
        ) {
        Submitted(name) => Submitted({ ..st, project_name: name, })
        Cancelled => Cancelled
        StepBack => StepBack
      }
    }),
    @clack.Step("configure", (st, s, allow_back) => {
      match
        @clack.confirm(
          "Select workspace packages? (Press Shift+Tab to go back)",
          initial_value=st.configure_packages,
          allow_back~,
          session=s,
        ) {
        Submitted(flag) => Submitted({ ..st, configure_packages: flag, })
        Cancelled => Cancelled
        StepBack => StepBack
      }
    }),
    @clack.Step("packages", when=fn(st) { st.configure_packages }, (
      st,
      s,
      allow_back,
    ) => {
      match
        @clack.group_multiselect(
          "Packages to scaffold",
          [
            @clack.GroupOption("Core", [
              @clack.SelectOption("ansi", "ansi", hint="SGR & width"),
              @clack.SelectOption(
                "core",
                "core",
                hint="headless state machines",
              ),
            ]),
            @clack.GroupOption("Adapters", [
              @clack.SelectOption("cli", "cli", hint="native terminal entry"),
              @clack.SelectOption("web", "web", hint="xterm.js browser demo"),
            ]),
          ],
          initial_values=if st.packages.is_empty() {
            ["ansi", "core"]
          } else {
            st.packages
          },
          allow_back~,
          session=s,
        ) {
        Submitted(pkgs) => Submitted({ ..st, packages: pkgs, })
        Cancelled => Cancelled
        StepBack => StepBack
      }
    }),
    @clack.Step("target", (st, s, allow_back) => {
      match
        @clack.autocomplete(
          "Primary compilation target",
          [
            @clack.SelectOption("native", "Native", hint="single C binary"),
            @clack.SelectOption("js", "JavaScript", hint="Node / browser ESM"),
            @clack.SelectOption("wasm", "WebAssembly", hint="WASI / moonrun"),
            @clack.SelectOption("wasm-gc", "Wasm-GC", hint="pure core target"),
          ],
          placeholder="Type to filter targets...",
          complete_on_tab=true,
          allow_back~,
          session=s,
        ) {
        Submitted(t) => Submitted({ ..st, target: t, })
        Cancelled => Cancelled
        StepBack => StepBack
      }
    }),
    @clack.Step("release_date", (st, s, allow_back) => {
      match
        @clack.date(
          "Target release date",
          initial_value=st.release_date,
          default_value=st.release_date,
          allow_back~,
          session=s,
        ) {
        Submitted(d) => Submitted({ ..st, release_date: d, })
        Cancelled => Cancelled
        StepBack => StepBack
      }
    }),
  ]

  match @clack.run_wizard(init, steps, session~) {
    Submitted(cfg) => {
      let action = @clack.select_key(
        "Proceed with scaffolding?",
        [
          @clack.SelectKeyOption("c", "continue", "Continue"),
          @clack.SelectKeyOption("q", "quit", "Quit"),
        ],
        session~,
      )
      match action {
        Submitted("continue") => ()
        _ => {
          @clack.cancel(session~)
          return
        }
      }

      @clack.tasks(
        [
          @clack.Task("Scaffolding \{cfg.project_name}", async fn(spinner) {
            @async.sleep(150)
            spinner.message("Writing moon.mod for \{cfg.target}")
            @async.sleep(150)
            Some("Workspace scaffolded")
          }),
          @clack.Task("Preparing release \{cfg.release_date.to_iso_string()}", async fn(
            _,
          ) {
            @async.sleep(150)
            Some("Release metadata ready")
          }),
        ],
        session~,
      )

      let bar = @clack.Progress(total=3, width=28, session~)
      bar.start(message="Checking packages")
      @async.sleep(100)
      bar.advance(delta=1, message="Running moon check")
      @async.sleep(100)
      bar.advance(delta=1, message="Running moon test")
      @async.sleep(100)
      bar.stop(message="All checks green")

      let pkg_summary = if cfg.packages.is_empty() {
        "(default)"
      } else {
        cfg.packages.join(", ")
      }
      @clack.box(
        "cd \{cfg.project_name}\nPackages: \{pkg_summary}\nRelease: \{cfg.release_date.to_iso_string()}\nmoon run --target \{cfg.target} cmd/demo",
        title="Next steps",
        rounded=true,
        session~,
      )
      @clack.outro("All set! Happy MoonBit hacking.", session~)
    }
    Cancelled | StepBack => @clack.cancel(session~)
  }
}
