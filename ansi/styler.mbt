///|
pub fn Styler::Styler(level~ : ColorLevel = Ansi16) -> Styler {
  { level, }
}

///|
pub fn Styler::enabled(self : Styler) -> Bool {
  self.level != None
}

///|
fn Styler::wrap_sgr(
  self : Styler,
  open_code : String,
  close_code : String,
  text : StringView,
) -> String {
  let raw = text.to_owned()
  if !self.enabled() || raw == "" {
    return raw
  }
  let open_seq = "\u{001b}[\{open_code}m"
  let close_seq = "\u{001b}[\{close_code}m"
  let full_reset = "\u{001b}[0m"
  let restore_close = close_seq + open_seq
  let restore_full = full_reset + open_seq
  let patched = raw
    .replace_all(old=close_seq, new=restore_close)
    .replace_all(old=full_reset, new=restore_full)
  open_seq + patched + close_seq
}

///|
pub fn Styler::bold(self : Styler, text : StringView) -> String {
  self.wrap_sgr("1", "22", text)
}

///|
pub fn Styler::dim(self : Styler, text : StringView) -> String {
  self.wrap_sgr("2", "22", text)
}

///|
pub fn Styler::italic(self : Styler, text : StringView) -> String {
  self.wrap_sgr("3", "23", text)
}

///|
pub fn Styler::underline(self : Styler, text : StringView) -> String {
  self.wrap_sgr("4", "24", text)
}

///|
pub fn Styler::inverse(self : Styler, text : StringView) -> String {
  self.wrap_sgr("7", "27", text)
}

///|
pub fn Styler::hidden(self : Styler, text : StringView) -> String {
  self.wrap_sgr("8", "28", text)
}

///|
pub fn Styler::strikethrough(self : Styler, text : StringView) -> String {
  self.wrap_sgr("9", "29", text)
}

///|
pub fn Styler::red(self : Styler, text : StringView) -> String {
  self.wrap_sgr("31", "39", text)
}

///|
pub fn Styler::green(self : Styler, text : StringView) -> String {
  self.wrap_sgr("32", "39", text)
}

///|
pub fn Styler::yellow(self : Styler, text : StringView) -> String {
  self.wrap_sgr("33", "39", text)
}

///|
pub fn Styler::blue(self : Styler, text : StringView) -> String {
  self.wrap_sgr("34", "39", text)
}

///|
pub fn Styler::magenta(self : Styler, text : StringView) -> String {
  self.wrap_sgr("35", "39", text)
}

///|
pub fn Styler::cyan(self : Styler, text : StringView) -> String {
  self.wrap_sgr("36", "39", text)
}

///|
pub fn Styler::white(self : Styler, text : StringView) -> String {
  self.wrap_sgr("37", "39", text)
}

///|
pub fn Styler::gray(self : Styler, text : StringView) -> String {
  self.wrap_sgr("90", "39", text)
}

///|
pub fn Styler::bg_white(self : Styler, text : StringView) -> String {
  self.wrap_sgr("47", "49", text)
}

///|
pub fn Styler::bg_cyan(self : Styler, text : StringView) -> String {
  self.wrap_sgr("46", "49", text)
}
