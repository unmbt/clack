///|
/// Active browser `xterm.js` demo session handle (JS target ES Module bridge).
pub struct WebDemoHandle {
  priv term : @clack.CallbackTerminal
  priv controller : @js_async.AbortController
  priv done : @js_async.Promise[Unit]
}

///|
/// Start a full async Clack demo session bound to `xterm.js` callbacks.
/// Returns a `WebDemoHandle` whose input, resize, and cancellation can be driven
/// directly from `term.onData`, `term.onResize`, and React unmount hooks.
#export_name("start_web_demo")
pub fn start_web_demo(
  on_write : (String) -> Unit,
  cols : Int32,
  rows : Int32,
  minimal : Bool,
) -> WebDemoHandle {
  let term = @clack.CallbackTerminal(
    on_write=fn(sv) { on_write(sv.to_owned()) },
    cols~,
    rows~,
    tty=true,
  )
  let controller = @js_async.AbortController()
  let done = @js_async.Promise::from_async(
    () => run_demo_on_callback(term, minimal~),
    abort_signal=controller.signal(),
  )
  { term, controller, done, }
}

///|
#export_name("push_web_input")
pub fn push_web_input(handle : WebDemoHandle, data : String) -> Unit {
  handle.term.push_text(data)
}

///|
#export_name("resize_web_demo")
pub fn resize_web_demo(
  handle : WebDemoHandle,
  cols : Int32,
  rows : Int32,
) -> Unit {
  handle.term.set_size(cols, rows)
}

///|
#export_name("cancel_web_demo")
pub fn cancel_web_demo(handle : WebDemoHandle) -> Unit {
  handle.term.close()
  handle.controller.abort()
  let _ = handle.done
}
