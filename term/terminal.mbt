///|
#derive(Debug, Eq)
pub(all) suberror TermError {
  IoFailure(String)
  NotInteractive(String)
  EndOfInput
}

///|
#derive(Debug, Eq)
pub(all) enum NonInteractivePolicy {
  UseDefaults
  Fail
}

///|
/// Terminal I/O abstraction isolating OS TTY handles, browser `xterm.js` callback
/// hosts, and deterministic in-memory test terminals.
pub(open) trait Terminal {
  fn is_tty(Self) -> Bool
  fn size(Self) -> (Int32, Int32)
  fn env_get(Self, key : String) -> String?
  async fn enter_raw_mode(Self) -> Unit raise TermError
  async fn leave_raw_mode(Self) -> Unit nocancel
  async fn read_bytes(Self) -> Bytes? raise TermError
  async fn write_str(Self, data : StringView) -> Unit raise TermError
  async fn write_final(Self, data : StringView) -> Unit nocancel
}

///|
/// Create the default platform terminal for the current compilation target
/// (`native`, `js`, or `wasm`).
declare pub fn default_terminal() -> &Terminal
