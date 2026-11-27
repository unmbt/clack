///|
fn mock_env(pairs : Array[(String, String)]) -> (String) -> String? {
  fn(key : String) -> String? {
    for pair in pairs {
      if pair.0 == key {
        return Some(pair.1)
      }
    }
    None
  }
}

///|
test "detect_color_level: NO_COLOR, FORCE_COLOR, TERM=dumb, TTY" {
  // NO_COLOR non-empty overrides TTY
  debug_inspect(
    @ansi.detect_color_level(
      is_tty=true,
      env_lookup=mock_env([("NO_COLOR", "1")]),
    ),
    content="None",
  )
  // NO_COLOR empty string does NOT disable color (no-color.org)
  debug_inspect(
    @ansi.detect_color_level(
      is_tty=true,
      env_lookup=mock_env([("NO_COLOR", "")]),
    ),
    content="Ansi16",
  )
  // FORCE_COLOR=3 forces TrueColor even when non-TTY
  debug_inspect(
    @ansi.detect_color_level(
      is_tty=false,
      env_lookup=mock_env([("FORCE_COLOR", "3")]),
    ),
    content="TrueColor",
  )
  // FORCE_COLOR=2 -> Ansi256, FORCE_COLOR=0 -> None
  debug_inspect(
    @ansi.detect_color_level(
      is_tty=false,
      env_lookup=mock_env([("FORCE_COLOR", "2")]),
    ),
    content="Ansi256",
  )
  debug_inspect(
    @ansi.detect_color_level(
      is_tty=true,
      env_lookup=mock_env([("FORCE_COLOR", "0")]),
    ),
    content="None",
  )
  // TERM=dumb disables color
  debug_inspect(
    @ansi.detect_color_level(
      is_tty=true,
      env_lookup=mock_env([("TERM", "dumb")]),
    ),
    content="None",
  )
  // Non-TTY without FORCE_COLOR -> None
  debug_inspect(
    @ansi.detect_color_level(is_tty=false, env_lookup=mock_env([])),
    content="None",
  )
  // COLORTERM=truecolor & TERM=xterm-256color
  debug_inspect(
    @ansi.detect_color_level(
      is_tty=true,
      env_lookup=mock_env([("COLORTERM", "truecolor")]),
    ),
    content="TrueColor",
  )
  debug_inspect(
    @ansi.detect_color_level(
      is_tty=true,
      env_lookup=mock_env([("TERM", "xterm-256color")]),
    ),
    content="Ansi256",
  )
}

///|
test "Styler: nested restoration and ColorLevel::None purity" {
  let s = @ansi.Styler(level=Ansi16)
  inspect(s.enabled(), content="true")
  // Outer cyan + inner bold preserves cyan for suffix
  let nested_bold = s.cyan("prefix " + s.bold("inner") + " suffix")
  inspect(
    nested_bold,
    content="\u{001b}[36mprefix \u{001b}[1minner\u{001b}[22m suffix\u{001b}[39m",
  )
  // Outer cyan + inner red restores cyan after red's 39m close
  let nested_color = s.cyan("a " + s.red("b") + " c")
  inspect(
    nested_color,
    content="\u{001b}[36ma \u{001b}[31mb\u{001b}[39m\u{001b}[36m c\u{001b}[39m",
  )
  // Outer bold + inner dim restores bold after shared 22m close
  let nested_weight = s.bold("a " + s.dim("b") + " c")
  inspect(
    nested_weight,
    content="\u{001b}[1ma \u{001b}[2mb\u{001b}[22m\u{001b}[1m c\u{001b}[22m",
  )
  // ColorLevel::None yields zero escape bytes
  let plain = @ansi.Styler(level=None)
  inspect(plain.enabled(), content="false")
  inspect(
    plain.cyan("prefix " + plain.bold("inner") + " suffix"),
    content="prefix inner suffix",
  )
  inspect(plain.strikethrough(plain.dim("cancelled")), content="cancelled")
  inspect(s.cyan(""), content="")
}

///|
test "strip_ansi: CSI, OSC (BEL & ST), and 2-byte escapes" {
  let s = @ansi.Styler()
  let colored = s.cyan("◆  ") + s.bold("Hello")
  inspect(@ansi.strip_ansi(colored), content="◆  Hello")
  let osc_bel = "\u{001b}]8;;https://moonbitlang.com\u{0007}MoonBit\u{001b}]8;;\u{0007}"
  inspect(@ansi.strip_ansi(osc_bel), content="MoonBit")
  let osc_st = "\u{001b}]0;window title\u{001b}\\body"
  inspect(@ansi.strip_ansi(osc_st), content="body")

  // strip_destructive_ansi keeps SGR colors while removing cursor/erase/scroll CSI
  let mixed = s.green("ok") +
    "\u{001b}[2J\u{001b}[1;1H\u{001b}[3A\u{001b}[K\u{001b}[s\u{001b}[u " +
    s.bg_cyan("a")
  inspect(
    @ansi.strip_destructive_ansi(mixed),
    content="\u{001b}[32mok\u{001b}[39m \u{001b}[46ma\u{001b}[49m",
  )
}

///|
test "display_width & wrapped_line_count: CJK, Emoji, ZWJ, narrow symbols, delayed-wrap" {
  // "你好" (4) + " " (1) + "clack" (5) + " " (1) + "🚀" (2) + " " (1) + "✓" (1) + " " (1) + "⚠️" (2) = 18
  inspect(@ansi.display_width("你好 clack 🚀 ✓ ⚠️"), content="18")
  // Narrow clack guide glyphs are 1 column each
  inspect(
    @ansi.display_width("┌│└◆◇■▲●○◼◻▪"),
    content="12",
  )
  // ZWJ emoji sequence counts as 2 cells
  inspect(@ansi.display_width("👨‍👩‍👧"), content="2")
  // Regional indicator flag pair counts as 2 cells
  inspect(@ansi.display_width("🇨🇳"), content="2")
  // Keycap emoji counts as 2 cells
  inspect(@ansi.display_width("1️⃣"), content="2")
  // ANSI sequences contribute 0 width
  let s = @ansi.Styler()
  let styled = s.cyan("◆  ") +
    "你好世界" +
    "\u{001b}]8;;https://a\u{0007}🚀\u{001b}]8;;\u{0007}"
  inspect(@ansi.display_width(styled), content="13")
  // Delayed-wrap boundary: exact fit == 1 row, +1 == 2 rows
  inspect(@ansi.wrapped_line_count("", 10), content="1")
  inspect(@ansi.wrapped_line_count("1234567890", 10), content="1")
  inspect(@ansi.wrapped_line_count("12345678901", 10), content="2")
  inspect(
    @ansi.wrapped_line_count("你好 clack 🚀 ✓ ⚠️", 10),
    content="2",
  )
  inspect(
    @ansi.wrapped_line_count("你好 clack 🚀 ✓ ⚠️", 20),
    content="1",
  )
  inspect(@ansi.wrapped_line_count(styled, 13), content="1")
  inspect(@ansi.wrapped_line_count(styled, 12), content="2")
}

///|
test "wrap_ansi & wrap_text_with_prefix: preserves SGR and prefixes" {
  let s = @ansi.Styler()
  let wrapped = @ansi.wrap_ansi(s.cyan("abcdef"), 4)
  inspect(wrapped.length(), content="2")
  inspect(@ansi.strip_ansi(wrapped[0]), content="abcd")
  inspect(@ansi.strip_ansi(wrapped[1]), content="ef")
  // Second wrapped line re-opens cyan SGR
  inspect(wrapped[1].has_prefix("\u{001b}[36m"), content="true")

  let prefixed = @ansi.wrap_text_with_prefix(
    "abcdefghij",
    8,
    "│  ",
    first_prefix="◆  ",
    end_prefix="└  ",
  )
  debug_inspect(prefixed, content="[\"◆  abcde\", \"└  fghij\"]")
}
