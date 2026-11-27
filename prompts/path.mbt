///|
/// A single filesystem entry returned by a directory listing provider for `path_with`.
#derive(Debug, Eq)
pub struct PathEntry {
  path : String
  is_dir : Bool
}

///|
pub fn PathEntry::PathEntry(path : String, is_dir : Bool) -> PathEntry {
  { path, is_dir, }
}

///|
fn path_has_trailing_sep(p : String) -> Bool {
  p.has_suffix("/") || p.has_suffix("\\")
}

///|
fn path_dirname(p : String) -> String {
  let chars = p.to_array()
  let mut end = chars.length()
  while end > 1 && (chars[end - 1] == '/' || chars[end - 1] == '\\') {
    if end == 3 && chars[1] == ':' {
      break
    }
    end -= 1
  }
  let mut last_sep : Int32 = -1
  for i in 0..<end {
    if chars[i] == '/' || chars[i] == '\\' {
      last_sep = i
    }
  }
  if last_sep < 0 {
    return "."
  }
  if last_sep == 0 {
    return String::from_array([chars[0]])
  }
  if last_sep == 2 && chars[1] == ':' {
    return String::from_array(chars[:3].to_owned())
  }
  String::from_array(chars[:last_sep].to_owned())
}

///|
fn path_join(dir : String, name : String) -> String {
  if dir == "" || dir == "." {
    return name
  }
  if path_has_trailing_sep(dir) {
    return dir + name
  }
  let sep = if dir.contains("\\") { "\\" } else { "/" }
  dir + sep + name
}

///|
async fn compute_path_options(
  user_input : String,
  directory : Bool,
  exists : async (String) -> Bool,
  is_dir : async (String) -> Bool,
  list_dir : async (String) -> Array[PathEntry],
) -> Array[@core.SelectOption[String]] noraise {
  if user_input == "" {
    return []
  }
  try {
    let has_trailing = path_has_trailing_sep(user_input)
    let search_path = if !exists(user_input) {
      path_dirname(user_input)
    } else if is_dir(user_input) && (!directory || has_trailing) {
      user_input
    } else {
      path_dirname(user_input)
    }
    let prefix = if user_input.length() > 1 && has_trailing {
      let chars = user_input.to_array()
      String::from_array(chars[:chars.length() - 1].to_owned())
    } else {
      user_input
    }
    let entries = list_dir(search_path)
    let opts : Array[@core.SelectOption[String]] = []
    for entry in entries {
      if entry.path.has_prefix(prefix) && (entry.is_dir || !directory) {
        opts.push(@core.SelectOption(entry.path, entry.path))
      }
    }
    opts
  } catch {
    _ => []
  }
}

///|
/// File/directory path selector with pluggable async filesystem hooks
/// (useful for deterministic unit tests and browser/virtual filesystems).
pub async fn path_with(
  message : String,
  exists~ : async (String) -> Bool,
  is_dir~ : async (String) -> Bool,
  list_dir~ : async (String) -> Array[PathEntry],
  root? : String,
  directory~ : Bool = false,
  initial_value? : String,
  validate? : (String) -> String?,
  allow_back~ : Bool = false,
  session? : Session,
) -> @core.PromptOutcome[String] raise @term.TermError {
  let s = resolve_session(session)
  let start_input = match initial_value {
    Some(v) => v
    None =>
      match root {
        Some(r) => r
        None => "."
      }
  }
  let combined_validate = fn(v : String) -> String? {
    if v == "" {
      return Some("Please select a path")
    }
    match validate {
      Some(vfn) => vfn(v)
      None => None
    }
  }

  let initial_opts = compute_path_options(
    start_input, directory, exists, is_dir, list_dir,
  )

  if !s.is_interactive() {
    match s.non_interactive {
      Fail =>
        raise NotInteractive(
          "Interactive terminal required for path prompt: \{message}",
        )
      UseDefaults => {
        let candidate = if !initial_opts.is_empty() {
          initial_opts[0].value
        } else {
          start_input
        }
        match combined_validate(candidate) {
          Some(err) =>
            raise NotInteractive(
              "Default path failed validation for '\{message}': \{err}",
            )
          None => return Submitted(candidate)
        }
      }
    }
  }

  let model = @core.AutocompleteModel(
    message,
    initial_opts,
    initial_user_input=start_input,
    max_items=5,
    complete_on_tab=true,
    filter=fn(_q, _opt) { true },
    validate=combined_validate,
    with_guide=s.with_guide,
  )
  let last_query : Ref[String] = Ref(start_input)
  run_prompt_core(
    model.as_adapter(),
    allow_back~,
    after_key=async fn() noraise {
      let cur_q = model.query()
      if cur_q != last_query.val {
        last_query.val = cur_q
        let next_opts = compute_path_options(
          cur_q, directory, exists, is_dir, list_dir,
        )
        model.set_options(next_opts)
      }
    },
    session=s,
  )
}

///|
/// Interactive filesystem path prompt (1:1 upstream `@clack/prompts` `path`).
/// Uses `moonbitlang/core/async/fs` on `native`/`wasm` and Node `node:fs` on `js`
/// (with an empty fallback in browsers).
pub async fn path(
  message : String,
  root? : String,
  directory~ : Bool = false,
  initial_value? : String,
  validate? : (String) -> String?,
  allow_back~ : Bool = false,
  session? : Session,
) -> @core.PromptOutcome[String] raise @term.TermError {
  let effective_root = match root {
    Some(r) => r
    None => @env.current_dir().unwrap_or(".")
  }
  path_with(
    message,
    exists=p => platform_exists(p),
    is_dir=p => platform_is_dir(p),
    list_dir=d => platform_list_dir(d),
    root=effective_root,
    directory~,
    initial_value?,
    validate?,
    allow_back~,
    session?,
  )
}
