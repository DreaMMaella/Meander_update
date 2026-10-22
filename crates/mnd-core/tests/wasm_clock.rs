//! Страховка веб-сборки: ядро не должно трогать часы std напрямую.

use std::fs;
use std::path::{Path, PathBuf};

/// На `wasm32-unknown-unknown` `SystemTime::now()` не возвращает ошибку, а
/// паникует («time not implemented on this platform»), и веб-плеер умирал на
/// первом же входе в ноду. Поэтому время берётся только через `crate::time`
/// (там для wasm — `Date.now()`), а std-часы живут ровно в одном файле.
#[test]
fn no_direct_systemtime_calls_in_core() {
    let src = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    let allowed = src.join("time.rs");
    let mut offenders = Vec::new();

    fn walk(dir: &Path, out: &mut Vec<PathBuf>) {
        for entry in fs::read_dir(dir).expect("каталог src должен существовать")
        {
            let path = entry.expect("запись каталога").path();
            if path.is_dir() {
                walk(&path, out);
            } else if path.extension().is_some_and(|e| e == "rs") {
                out.push(path);
            }
        }
    }

    let mut files = Vec::new();
    walk(&src, &mut files);
    assert!(files.len() > 20, "обход src должен найти исходники ядра");

    for file in files {
        if file == allowed {
            continue;
        }
        let text = fs::read_to_string(&file).expect("исходник читается");
        for (no, line) in text.lines().enumerate() {
            if line.contains("SystemTime::now") || line.contains("UNIX_EPOCH") {
                offenders.push(format!("{}:{}", file.display(), no + 1));
            }
        }
    }

    assert!(
        offenders.is_empty(),
        "прямые вызовы std-часов ломают wasm-сборку (они там паникуют); \
         используйте crate::time::unix_now_secs()/unix_now_nanos(): {offenders:?}"
    );
}
