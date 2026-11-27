///|
/// Render a customizable bordered box (1:1 upstream `@clack/prompts` `box()`).
pub async fn box(
  message : StringView,
  title~ : StringView = "",
  content_align~ : @core.BoxAlign = Left,
  title_align~ : @core.BoxAlign = Left,
  width~ : @core.BoxWidth = Auto,
  title_padding~ : Int32 = 1,
  content_padding~ : Int32 = 2,
  rounded~ : Bool = true,
  format_border? : (String) -> String,
  session? : Session,
) -> Unit raise @term.TermError {
  let s = resolve_session(session)
  let (raw_cols, _) = s.term.size()
  let cols = if raw_cols > 0 { raw_cols } else { 80 }
  let rendered = @core.render_box(
    message,
    title~,
    cols~,
    styler=s.styler,
    unicode=s.unicode,
    with_guide=s.with_guide,
    content_align~,
    title_align~,
    width~,
    title_padding~,
    content_padding~,
    rounded~,
    format_border?,
  )
  s.term.write_str(rendered + "\n")
}
