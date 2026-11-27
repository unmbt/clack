///|
/// Declarative wizard step with optional skip predicate `when` and async execution body.
pub struct Step[State] {
  id : String
  when : (State) -> Bool
  run : async (State, @prompts.Session, Bool) -> @core.PromptOutcome[State] raise @term.TermError
}

///|
pub fn[State] Step::Step(
  id : String,
  when~ : (State) -> Bool = fn(_) { true },
  run : async (State, @prompts.Session, Bool) -> @core.PromptOutcome[State] raise @term.TermError,
) -> Step[State] {
  { id, when, run, }
}

///|
/// Run a multi-step wizard maintaining an immutable `(step_index, prior_state)` history stack.
///
/// - Steps where `step.when(state)` returns `false` are automatically skipped.
/// - When any step returns `PromptOutcome::StepBack`, the wizard pops the most recently
///   executed step from the history stack (automatically jumping back over skipped steps)
///   and re-runs it with the preserved `prior_state` snapshot.
pub async fn[State] run_wizard(
  initial : State,
  steps : Array[Step[State]],
  session? : @prompts.Session,
) -> @core.PromptOutcome[State] raise @term.TermError {
  let s = match session {
    Some(sess) => sess
    None => @prompts.Session()
  }
  let history : Array[(Int32, State)] = []
  let mut state = initial
  let mut idx : Int32 = 0
  let total = steps.length()
  while idx < total {
    let step = steps[idx]
    if !(step.when)(state) {
      idx += 1
      continue
    }
    let can_go_back = !history.is_empty()
    let outcome = (step.run)(state, s, can_go_back)
    match outcome {
      Submitted(next_state) => {
        history.push((idx, next_state))
        state = next_state
        idx += 1
      }
      Cancelled => return Cancelled
      StepBack =>
        match history.pop() {
          Some((prev_idx, prev_submitted_state)) => {
            state = prev_submitted_state
            idx = prev_idx
          }
          None => return StepBack
        }
    }
  }
  Submitted(state)
}
