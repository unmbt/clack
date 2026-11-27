///|
/// Terminal color capability level inferred from TTY status and environment variables.
#derive(Debug, Eq, Hash)
pub(all) enum ColorLevel {
  None
  Ansi16
  Ansi256
  TrueColor
}

///|
/// Zero-global-state ANSI SGR styler bound to a specific `ColorLevel`.
#derive(Debug, Eq)
pub struct Styler {
  level : ColorLevel
}

///|
declare pub fn detect_color_level(
  is_tty~ : Bool,
  env_lookup~ : (String) -> String?,
) -> ColorLevel

///|
declare pub fn Styler::Styler(level? : ColorLevel) -> Styler

///|
declare pub fn Styler::enabled(self : Styler) -> Bool

///|
declare pub fn Styler::bold(self : Styler, text : StringView) -> String

///|
declare pub fn Styler::dim(self : Styler, text : StringView) -> String

///|
declare pub fn Styler::italic(self : Styler, text : StringView) -> String

///|
declare pub fn Styler::underline(self : Styler, text : StringView) -> String

///|
declare pub fn Styler::inverse(self : Styler, text : StringView) -> String

///|
declare pub fn Styler::hidden(self : Styler, text : StringView) -> String

///|
declare pub fn Styler::strikethrough(self : Styler, text : StringView) -> String

///|
declare pub fn Styler::cyan(self : Styler, text : StringView) -> String

///|
declare pub fn Styler::green(self : Styler, text : StringView) -> String

///|
declare pub fn Styler::yellow(self : Styler, text : StringView) -> String

///|
declare pub fn Styler::red(self : Styler, text : StringView) -> String

///|
declare pub fn Styler::magenta(self : Styler, text : StringView) -> String

///|
declare pub fn Styler::blue(self : Styler, text : StringView) -> String

///|
declare pub fn Styler::gray(self : Styler, text : StringView) -> String

///|
declare pub fn Styler::white(self : Styler, text : StringView) -> String

///|
declare pub fn Styler::bg_white(self : Styler, text : StringView) -> String

///|
declare pub fn Styler::bg_cyan(self : Styler, text : StringView) -> String

///|
/// Strip all CSI / OSC ANSI escape sequences and return plain visible text.
declare pub fn strip_ansi(input : StringView) -> String

///|
/// Strip destructive cursor-movement, erase, and scroll CSI sequences while
/// preserving SGR color/style sequences (matching upstream Clack `task-log.ts`).
declare pub fn strip_destructive_ansi(input : StringView) -> String

///|
/// Compute terminal display column width after stripping ANSI escape sequences.
declare pub fn display_width(input : StringView) -> Int32

///|
/// Compute physical terminal rows occupied by a single line under `cols` (clamped to >= 1).
declare pub fn wrapped_line_count(line : StringView, cols : Int32) -> Int32

///|
/// Wrap text to `max_cols` visual columns while preserving active ANSI SGR styles.
declare pub fn wrap_ansi(text : StringView, max_cols : Int32) -> Array[String]

///|
/// Wrap text with per-line prefixes (matching upstream Clack `wrapTextWithPrefix`).
declare pub fn wrap_text_with_prefix(
  text : StringView,
  cols : Int32,
  prefix : StringView,
  first_prefix? : StringView,
  end_prefix? : StringView,
) -> Array[String]
