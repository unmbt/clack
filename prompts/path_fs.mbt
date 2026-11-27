///|
async fn platform_exists(p : String) -> Bool {
  @fs.exists(p) catch {
    _ => false
  }
}

///|
async fn platform_is_dir(p : String) -> Bool {
  try @fs.kind(p, follow_symlink=false) == Directory catch {
    _ => false
  }
}

///|
async fn platform_list_dir(dir : String) -> Array[PathEntry] {
  let out : Array[PathEntry] = []
  try {
    let handle = @fs.opendir(dir)
    defer handle.close()
    for ;; {
      match handle.next(include_hidden=true) {
        Some(entry) => {
          let full = path_join(dir, entry.name)
          out.push(PathEntry(full, entry.is_dir))
        }
        None => break
      }
    }
  } catch {
    _ => ()
  }
  out.sort_by(fn(a, b) { a.path.compare(b.path) })
  out
}
