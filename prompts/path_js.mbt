///|
extern "js" fn js_fs_exists(p : String) -> Bool =
  #| (p) => {
  #|   try {
  #|     const fs = (typeof process !== "undefined" && typeof process.getBuiltinModule === "function")
  #|       ? process.getBuiltinModule("node:fs")
  #|       : (typeof require === "function" ? require("node:fs") : null);
  #|     return !!(fs && fs.existsSync(p));
  #|   } catch (_) { return false; }
  #| }

///|
extern "js" fn js_fs_is_dir(p : String) -> Bool =
  #| (p) => {
  #|   try {
  #|     const fs = (typeof process !== "undefined" && typeof process.getBuiltinModule === "function")
  #|       ? process.getBuiltinModule("node:fs")
  #|       : (typeof require === "function" ? require("node:fs") : null);
  #|     return !!(fs && fs.lstatSync(p).isDirectory());
  #|   } catch (_) { return false; }
  #| }

///|
extern "js" fn js_fs_list_dir(dir : String) -> FixedArray[String] =
  #| (dir) => {
  #|   try {
  #|     const fs = (typeof process !== "undefined" && typeof process.getBuiltinModule === "function")
  #|       ? process.getBuiltinModule("node:fs")
  #|       : (typeof require === "function" ? require("node:fs") : null);
  #|     if (!fs) return [];
  #|     const names = fs.readdirSync(dir).sort();
  #|     const out = [];
  #|     for (const name of names) {
  #|       const full = dir.endsWith("/") || dir.endsWith("\\") ? dir + name : dir + "/" + name;
  #|       let isDir = false;
  #|       try { isDir = fs.lstatSync(full).isDirectory(); } catch (_) {}
  #|       out.push((isDir ? "D:" : "F:") + name);
  #|     }
  #|     return out;
  #|   } catch (_) { return []; }
  #| }

///|
fn platform_exists(p : String) -> Bool {
  js_fs_exists(p)
}

///|
fn platform_is_dir(p : String) -> Bool {
  js_fs_is_dir(p)
}

///|
fn platform_list_dir(dir : String) -> Array[PathEntry] {
  let raw = js_fs_list_dir(dir)
  let out : Array[PathEntry] = []
  for item in raw {
    if item.has_prefix("D:") {
      out.push(PathEntry(path_join(dir, item[2:].to_owned()), true))
    } else if item.has_prefix("F:") {
      out.push(PathEntry(path_join(dir, item[2:].to_owned()), false))
    }
  }
  out
}
