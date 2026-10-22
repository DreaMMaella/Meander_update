//! CLI-валидатор квеста.
//!
//! ```text
//! cargo run -p mnd-core --example quest_check -- <root> <quest_id>
//! ```
//! `root` — каталог, внутри которого лежит `quests/<quest_id>/`.
//! Код выхода: 0 — ок (или только warnings), 1 — есть errors.

use mnd_core::validation::analyze_quest;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let (root, quest_id) = match args.len() {
        3 => (&args[1], &args[2]),
        _ => {
            eprintln!("usage: quest_check <root> <quest_id>");
            std::process::exit(2);
        }
    };
    let report = analyze_quest(quest_id, root);
    println!("stats: {:?}", report.stats);
    for d in &report.diagnostics {
        println!("[{:?}/{:?}] {}", d.severity, d.kind, d.message);
    }
    if report.has_errors() {
        std::process::exit(1);
    }
}
