///|
pub fn SimpleDate::SimpleDate(
  year : Int32,
  month : Int32,
  day : Int32,
) -> SimpleDate {
  { year, month, day, }
}

///|
fn is_leap_year(year : Int32) -> Bool {
  (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

///|
pub fn days_in_month(year : Int32, month : Int32) -> Int32 {
  match month {
    1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
    4 | 6 | 9 | 11 => 30
    2 => if is_leap_year(year) { 29 } else { 28 }
    _ => 31
  }
}

///|
fn pad_digits(n : Int32, width : Int32) -> String {
  let s = n.to_string()
  let len = s.length()
  if len >= width {
    s
  } else {
    repeat_str("0", width - len) + s
  }
}

///|
pub fn SimpleDate::to_iso_string(self : SimpleDate) -> String {
  pad_digits(self.year, 4) +
  "-" +
  pad_digits(self.month, 2) +
  "-" +
  pad_digits(self.day, 2)
}

///|
pub fn SimpleDate::compare(self : SimpleDate, other : SimpleDate) -> Int32 {
  if self.year != other.year {
    return if self.year < other.year { -1 } else { 1 }
  }
  if self.month != other.month {
    return if self.month < other.month { -1 } else { 1 }
  }
  if self.day != other.day {
    return if self.day < other.day { -1 } else { 1 }
  }
  0
}

///|
priv enum DateSegmentKind {
  Year
  Month
  Day
}

///|
fn format_segment_order(fmt : DateFormat) -> Array[DateSegmentKind] {
  match fmt {
    Ymd => [Year, Month, Day]
    Mdy => [Month, Day, Year]
    Dmy => [Day, Month, Year]
  }
}

///|
fn segment_width(kind : DateSegmentKind) -> Int32 {
  match kind {
    Year => 4
    Month | Day => 2
  }
}

///|
fn segment_label(kind : DateSegmentKind) -> String {
  match kind {
    Year => "yyyy"
    Month => "mm"
    Day => "dd"
  }
}

///|
fn parse_digits_opt(s : String) -> Int32? {
  if s == "" {
    return None
  }
  let mut acc : Int32 = 0
  for ch in s.to_array() {
    if ch < '0' || ch > '9' {
      return None
    }
    acc = acc * 10 + (ch.to_int() - '0'.to_int())
  }
  Some(acc)
}

///|
/// Headless segmented date picker state machine (1:1 upstream `@clack/prompts` `date`).
pub struct DateModel {
  priv message : String
  priv separator : String
  priv segments : Array[DateSegmentKind]
  priv mut year_buf : String
  priv mut month_buf : String
  priv mut day_buf : String
  priv mut seg_index : Int32
  priv default_value : SimpleDate?
  priv min_date : SimpleDate?
  priv max_date : SimpleDate?
  priv validate : ((SimpleDate) -> String?)?
  priv mut inline_error : String?
  priv mut phase : PromptPhase
  priv with_guide : Bool
  priv mut final_date : SimpleDate?
}

///|
pub fn DateModel::DateModel(
  message : String,
  format~ : DateFormat = Ymd,
  separator~ : String = "/",
  initial_value? : SimpleDate,
  default_value? : SimpleDate,
  min_date? : SimpleDate,
  max_date? : SimpleDate,
  validate? : (SimpleDate) -> String?,
  with_guide~ : Bool = true,
) -> DateModel {
  let (yb, mb, db) = match initial_value {
    Some(d) =>
      (pad_digits(d.year, 4), pad_digits(d.month, 2), pad_digits(d.day, 2))
    None => ("", "", "")
  }
  {
    message,
    separator,
    segments: format_segment_order(format),
    year_buf: yb,
    month_buf: mb,
    day_buf: db,
    seg_index: 0,
    default_value,
    min_date,
    max_date,
    validate,
    inline_error: None,
    phase: Initial,
    with_guide,
    final_date: None,
  }
}

///|
fn DateModel::get_buf(self : DateModel, kind : DateSegmentKind) -> String {
  match kind {
    Year => self.year_buf
    Month => self.month_buf
    Day => self.day_buf
  }
}

///|
fn DateModel::set_buf(
  self : DateModel,
  kind : DateSegmentKind,
  val : String,
) -> Unit {
  match kind {
    Year => self.year_buf = val
    Month => self.month_buf = val
    Day => self.day_buf = val
  }
}

///|
pub fn DateModel::formatted_value(self : DateModel) -> String {
  let parts : Array[String] = []
  for seg in self.segments {
    let raw = self.get_buf(seg)
    parts.push(if raw == "" { segment_label(seg) } else { raw })
  }
  parts.join(self.separator)
}

///|
fn DateModel::format_simple_date(self : DateModel, d : SimpleDate) -> String {
  let parts : Array[String] = []
  for seg in self.segments {
    match seg {
      Year => parts.push(pad_digits(d.year, 4))
      Month => parts.push(pad_digits(d.month, 2))
      Day => parts.push(pad_digits(d.day, 2))
    }
  }
  parts.join(self.separator)
}

///|
fn DateModel::step_segment(self : DateModel, delta : Int32) -> Unit {
  let kind = self.segments[self.seg_index]
  match kind {
    Year => {
      let cur = match parse_digits_opt(self.year_buf) {
        Some(v) => v
        None => 2026
      }
      let next = if cur + delta < 1 {
        9999
      } else if cur + delta > 9999 {
        1
      } else {
        cur + delta
      }
      self.year_buf = pad_digits(next, 4)
    }
    Month => {
      let cur = match parse_digits_opt(self.month_buf) {
        Some(v) if v >= 1 && v <= 12 => v
        _ => if delta > 0 { 0 } else { 2 }
      }
      let next = (cur - 1 + delta + 12) % 12 + 1
      self.month_buf = pad_digits(next, 2)
    }
    Day => {
      let y = match parse_digits_opt(self.year_buf) {
        Some(v) if v > 0 => v
        _ => 2026
      }
      let m = match parse_digits_opt(self.month_buf) {
        Some(v) if v >= 1 && v <= 12 => v
        _ => 1
      }
      let max_d = days_in_month(y, m)
      let cur = match parse_digits_opt(self.day_buf) {
        Some(v) if v >= 1 && v <= max_d => v
        _ => if delta > 0 { 0 } else { 2 }
      }
      let next = (cur - 1 + delta + max_d) % max_d + 1
      self.day_buf = pad_digits(next, 2)
    }
  }
}

///|
fn DateModel::validate_and_build(
  self : DateModel,
) -> Result[SimpleDate, String] {
  if self.year_buf == "" && self.month_buf == "" && self.day_buf == "" {
    match self.default_value {
      Some(d) => return Ok(d)
      None => return Err("Please enter a valid date")
    }
  }
  let y = match parse_digits_opt(self.year_buf) {
    Some(v) if v >= 1 && v <= 9999 => v
    _ => return Err("Please enter a valid date")
  }
  let m = match parse_digits_opt(self.month_buf) {
    Some(v) if v >= 1 && v <= 12 => v
    Some(v) if v > 12 => return Err("There are only 12 months in a year")
    _ => return Err("Please enter a valid date")
  }
  let max_d = days_in_month(y, m)
  let d = match parse_digits_opt(self.day_buf) {
    Some(v) if v >= 1 && v <= max_d => v
    Some(v) if v > max_d =>
      return Err("There are only \{max_d} days in month \{m}")
    _ => return Err("Please enter a valid date")
  }
  let date = SimpleDate(y, m, d)
  match self.min_date {
    Some(min_d) if date.compare(min_d) < 0 =>
      return Err("Date must be on or after \{min_d.to_iso_string()}")
    _ => ()
  }
  match self.max_date {
    Some(max_d) if date.compare(max_d) > 0 =>
      return Err("Date must be on or before \{max_d.to_iso_string()}")
    _ => ()
  }
  match self.validate {
    Some(vfn) =>
      match vfn(date) {
        Some(err) => return Err(err)
        None => ()
      }
    None => ()
  }
  Ok(date)
}

///|
pub fn DateModel::on_key(
  self : DateModel,
  event : KeyEvent,
  allow_back~ : Bool = false,
) -> PromptOutcome[SimpleDate]? {
  if is_cancel_event(event) {
    self.phase = Cancelled
    return Some(Cancelled)
  }
  if is_back_event(event, allow_back) {
    self.phase = Reverted
    return Some(StepBack)
  }
  if event.code == Escape {
    self.phase = Cancelled
    return Some(Cancelled)
  }
  if self.phase is (Initial | Warning(_) | Error(_)) {
    self.phase = Active
  }
  self.inline_error = None
  match event.code {
    Left => if self.seg_index > 0 { self.seg_index -= 1 }
    Right | Tab =>
      if self.seg_index + 1 < self.segments.length() {
        self.seg_index += 1
      }
    Up => self.step_segment(1)
    Down => self.step_segment(-1)
    Backspace => {
      let kind = self.segments[self.seg_index]
      let cur = self.get_buf(kind)
      if cur == "" {
        if self.seg_index > 0 {
          self.seg_index -= 1
        }
      } else {
        let chars = cur.to_array()
        self.set_buf(
          kind,
          String::from_array(chars[:chars.length() - 1].to_owned()),
        )
      }
    }
    Char(ch) if !event.ctrl && !event.alt && ch >= '0' && ch <= '9' => {
      let kind = self.segments[self.seg_index]
      let max_w = segment_width(kind)
      let cur = self.get_buf(kind)
      let next = if cur.length() >= max_w {
        ch.to_string()
      } else {
        cur + ch.to_string()
      }
      self.set_buf(kind, next)
      if next.length() == max_w && self.seg_index + 1 < self.segments.length() {
        self.seg_index += 1
      }
    }
    Enter =>
      match self.validate_and_build() {
        Ok(date) => {
          self.final_date = Some(date)
          self.phase = Submitted
          return Some(Submitted(date))
        }
        Err(msg) => {
          self.phase = Error(msg)
          return None
        }
      }
    _ => ()
  }
  None
}

///|
pub fn DateModel::view(self : DateModel) -> FrameSpec {
  let seg_views : Array[DateSegmentView] = []
  for i in 0..<self.segments.length() {
    let kind = self.segments[i]
    seg_views.push({
      text: self.get_buf(kind),
      label: segment_label(kind),
      is_active: i == self.seg_index,
    })
  }
  let summary : String? = match self.phase {
    Submitted =>
      match self.final_date {
        Some(d) => Some(self.format_simple_date(d))
        None => Some(self.formatted_value())
      }
    Cancelled => Some(self.formatted_value())
    _ => None
  }
  {
    phase: self.phase,
    message: self.message,
    body: DateInput(
      segments=seg_views,
      separator=self.separator,
      inline_error=self.inline_error,
    ),
    submitted_summary: summary,
    with_guide: self.with_guide,
    max_rows: None,
  }
}

///|
pub fn DateModel::as_adapter(self : DateModel) -> PromptAdapter[SimpleDate] {
  PromptAdapter(on_key=fn(ev, allow_back) { self.on_key(ev, allow_back~) }, view=fn() {
    self.view()
  })
}
