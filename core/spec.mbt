///|
#derive(Debug, Eq, Hash)
pub(all) enum KeyCode {
  Char(Char)
  Paste(String)
  Enter
  Escape
  Backspace
  Delete
  Tab
  BackTab
  Up
  Down
  Left
  Right
  Home
  End
  PageUp
  PageDown
  Space
}

///|
#derive(Debug, Eq, Hash)
pub(all) struct KeyEvent {
  code : KeyCode
  ctrl : Bool
  alt : Bool
  shift : Bool
}

///|
/// Streaming keyboard & bracketed-paste byte decoder (zero I/O, four-target safe).
pub struct KeyDecoder {
  priv mut in_paste : Bool
  priv paste_buf : StringBuilder
  priv mut paste_bytes : Int32
  priv pending_bytes : Array[Byte]
  priv mut swallow_lf : Bool
}

///|
declare pub fn KeyDecoder::KeyDecoder() -> KeyDecoder

///|
declare pub fn KeyDecoder::feed(
  self : KeyDecoder,
  chunk : BytesView,
) -> Array[KeyEvent]

///|
declare pub fn KeyDecoder::has_pending_escape(self : KeyDecoder) -> Bool

///|
declare pub fn KeyDecoder::flush_escape(self : KeyDecoder) -> KeyEvent?

///|
#derive(Debug, Eq)
pub(all) enum PromptOutcome[T] {
  Submitted(T)
  Cancelled
  StepBack
}

///|
#derive(Debug, Eq)
pub(all) enum PromptPhase {
  Initial
  Active
  Validating
  Warning(String)
  Error(String)
  Submitted
  Cancelled
  Reverted
}

///|
#derive(Debug, Eq)
pub(all) struct SelectOption[T] {
  value : T
  label : String
  hint : String?
  disabled : Bool
}

///|
declare pub fn[T] SelectOption::SelectOption(
  value : T,
  label : String,
  hint? : String,
  disabled? : Bool,
) -> SelectOption[T]

///|
#derive(Debug, Eq)
pub(all) struct GroupOption[T] {
  group : String
  options : Array[SelectOption[T]]
}

///|
declare pub fn[T] GroupOption::GroupOption(
  group : String,
  options : Array[SelectOption[T]],
) -> GroupOption[T]

///|
#derive(Debug, Eq)
pub(all) struct OptionRowView {
  label : String
  hint : String?
  is_cursor : Bool
  is_selected : Bool
  is_disabled : Bool
  is_multi : Bool
}

///|
#derive(Debug, Eq)
pub(all) enum GroupRowView {
  Header(
    label~ : String,
    is_cursor~ : Bool,
    all_selected~ : Bool,
    partial_selected~ : Bool,
    group_active~ : Bool,
    selectable~ : Bool,
  )
  Item(
    row~ : OptionRowView,
    is_last_in_group~ : Bool,
    in_active_group~ : Bool,
    selectable_groups~ : Bool,
  )
}

///|
#derive(Debug, Eq)
pub(all) enum BoxAlign {
  Left
  Center
  Right
}

///|
#derive(Debug, Eq)
pub(all) enum BoxWidth {
  Auto
  Ratio(Double)
}

///|
#derive(Debug, Eq)
pub(all) struct SimpleDate {
  year : Int32
  month : Int32
  day : Int32
}

///|
#derive(Debug, Eq)
pub(all) enum DateFormat {
  Ymd
  Mdy
  Dmy
}

///|
#derive(Debug, Eq)
pub(all) struct SelectKeyOption[T] {
  key : String
  value : T
  label : String
  hint : String?
  disabled : Bool
}

///|
#derive(Debug, Eq)
pub(all) struct SelectKeyRowView {
  key : String
  label : String
  hint : String?
  is_cursor : Bool
  is_disabled : Bool
}

///|
#derive(Debug, Eq)
pub(all) struct DateSegmentView {
  text : String
  label : String
  is_active : Bool
}

///|
#derive(Debug, Eq)
pub(all) enum BodyView {
  TextInput(
    rendered_value~ : String,
    cursor_pos~ : Int32,
    placeholder~ : String?,
    is_empty~ : Bool,
    is_password~ : Bool,
    raw_text~ : String,
  )
  ConfirmToggle(
    active_yes~ : Bool,
    yes_label~ : String,
    no_label~ : String,
    vertical~ : Bool,
  )
  OptionList(
    items~ : Array[OptionRowView],
    cursor~ : Int32,
    max_items~ : Int32?,
    total_count~ : Int32,
    total_unfiltered~ : Int32,
    filter_query~ : String?,
    filter_cursor~ : Int32,
    filter_placeholder~ : String?,
    is_navigating~ : Bool,
    complete_on_tab~ : Bool,
    show_instructions~ : Bool,
    is_multi~ : Bool,
  )
  GroupOptionList(
    rows~ : Array[GroupRowView],
    cursor~ : Int32,
    max_items~ : Int32?,
    total_count~ : Int32,
    selectable_groups~ : Bool,
    group_spacing~ : Int32,
    show_instructions~ : Bool,
  )
  SelectKeyList(items~ : Array[SelectKeyRowView])
  MultiLineInput(
    lines~ : Array[String],
    cursor_line~ : Int32,
    cursor_col~ : Int32,
    placeholder~ : String?,
    is_empty~ : Bool,
    show_submit~ : Bool,
    submit_focused~ : Bool,
  )
  DateInput(
    segments~ : Array[DateSegmentView],
    separator~ : String,
    inline_error~ : String?,
  )
  CustomLines(
    header~ : Array[String],
    lines~ : Array[String],
    cursor_line~ : Int32?,
    footer~ : Array[String],
    clear_on_submit~ : Bool,
  )
}

///|
#derive(Debug, Eq)
pub(all) struct FrameSpec {
  phase : PromptPhase
  message : String
  body : BodyView
  submitted_summary : String?
  with_guide : Bool
  max_rows : Int32?
}

///|
pub(open) trait Theme {
  fn render_frame(Self, spec : FrameSpec, styler : @ansi.Styler, cols : Int32) -> Array[
    String,
  ]
  fn render_intro(Self, title : StringView, styler : @ansi.Styler) -> String
  fn render_outro(Self, message : StringView, styler : @ansi.Styler) -> String
  fn render_cancel(Self, message : StringView, styler : @ansi.Styler) -> String
  fn render_note(
    Self,
    title : StringView,
    body : StringView,
    styler : @ansi.Styler,
  ) -> String
  fn render_log(
    Self,
    kind : StringView,
    message : StringView,
    styler : @ansi.Styler,
  ) -> String
}

///|
pub struct ClackTheme {
  unicode : Bool
  with_guide : Bool
}

///|
declare pub fn ClackTheme::ClackTheme(
  unicode? : Bool,
  with_guide? : Bool,
) -> ClackTheme

///|
declare pub impl Theme for ClackTheme

///|
pub struct MinimalTheme {
  unicode : Bool
}

///|
declare pub fn MinimalTheme::MinimalTheme(unicode? : Bool) -> MinimalTheme

///|
declare pub impl Theme for MinimalTheme

///|
declare pub fn limit_options(
  styled_items : Array[String],
  cursor : Int32,
  cols : Int32,
  rows : Int32,
  max_items? : Int32,
  column_padding? : Int32,
  row_padding? : Int32,
  ellipsis? : String,
) -> Array[String]

///|
declare pub fn slice_viewport_lines(
  lines : Array[String],
  cursor_line : Int32,
  cols : Int32,
  max_rows : Int32,
) -> Array[String]

///|
pub struct PromptAdapter[T] {
  on_key : (KeyEvent, Bool) -> PromptOutcome[T]?
  view : () -> FrameSpec
}

///|
declare pub fn[T] PromptAdapter::PromptAdapter(
  on_key~ : (KeyEvent, Bool) -> PromptOutcome[T]?,
  view~ : () -> FrameSpec,
) -> PromptAdapter[T]

///|
pub struct InlineDiffRenderer {
  priv mut prev_physical_rows : Int32
  priv mut prev_lines : Array[String]
  priv mut prev_cols : Int32
  priv mut has_rendered : Bool
}

///|
declare pub fn InlineDiffRenderer::InlineDiffRenderer() -> InlineDiffRenderer

///|
declare pub fn InlineDiffRenderer::patch(
  self : InlineDiffRenderer,
  lines : Array[String],
  cols : Int32,
  sync_output~ : Bool,
) -> String

///|
declare pub fn InlineDiffRenderer::commit(
  self : InlineDiffRenderer,
  final_lines : Array[String],
  cols : Int32,
  sync_output~ : Bool,
) -> String

///|
declare pub fn InlineDiffRenderer::on_resize(
  self : InlineDiffRenderer,
) -> String

///|
declare pub fn InlineDiffRenderer::reset(self : InlineDiffRenderer) -> Unit

///|
pub struct InlineDriver[T] {
  priv adapter : PromptAdapter[T]
  priv theme : &Theme
  priv styler : @ansi.Styler
  priv renderer : InlineDiffRenderer
  priv decoder : KeyDecoder
  priv allow_back : Bool
  priv sync_output : Bool
  priv mut cols : Int32
  priv mut rows : Int32
  priv mut finished : Bool
}

///|
declare pub fn[T] InlineDriver::InlineDriver(
  adapter : PromptAdapter[T],
  theme? : &Theme,
  styler? : @ansi.Styler,
  cols? : Int32,
  rows? : Int32,
  allow_back? : Bool,
  sync_output? : Bool,
) -> InlineDriver[T]

///|
declare pub fn[T] InlineDriver::start(self : InlineDriver[T]) -> String

///|
declare pub fn[T] InlineDriver::feed(
  self : InlineDriver[T],
  chunk : BytesView,
) -> (String, PromptOutcome[T]?)

///|
declare pub fn[T] InlineDriver::flush_escape(
  self : InlineDriver[T],
) -> (String, PromptOutcome[T]?)

///|
declare pub fn[T] InlineDriver::resize(
  self : InlineDriver[T],
  cols : Int32,
  rows : Int32,
) -> String

///|
declare pub fn[T] InlineDriver::has_pending_escape(
  self : InlineDriver[T],
) -> Bool
