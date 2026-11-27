///|
/// Sequential task item executed by `tasks()` (1:1 upstream `@clack/prompts` `tasks`).
pub struct Task {
  title : String
  enabled : Bool
  run : async (Spinner) -> String?
}

///|
pub fn Task::Task(
  title : String,
  enabled~ : Bool = true,
  run : async (Spinner) -> String?,
) -> Task {
  { title, enabled, run, }
}

///|
/// Execute an array of tasks sequentially, wrapping each enabled task with a `Spinner`.
pub async fn tasks(items : Array[Task], session? : Session) -> Unit {
  let s = resolve_session(session)
  for item in items {
    if !item.enabled {
      continue
    }
    let spin = Spinner(session=s)
    spin.start(item.title)
    let mut done_ok = false
    defer (if !done_ok {
      if @async.is_being_cancelled() {
        spin.cancel()
      } else {
        spin.fail()
      }
    })
    let custom_msg = (item.run)(spin)
    done_ok = true
    let final_msg : StringView = match custom_msg {
      Some(m) if m != "" => m
      _ => item.title
    }
    spin.stop(message=final_msg)
  }
}
