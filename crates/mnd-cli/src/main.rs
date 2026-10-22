//! Консольный headless-раннер квестов Meander.
//!
//! Загружает квест с диска через `GameEngine::from_disk()`, исполняет
//! команды из stdin или файла скрипта, выводит раскрытые айтемы,
//! переходы и текущее состояние переменных.
//!
//! ```bash
//! # Просто показать все айтемы стартовой ноды
//! mnd-cli --quest-root ~/quests --quest-id <uuid> reveal
//!
//! # Исполнить скрипт команд
//! mnd-cli --quest-root ~/quests --quest-id <uuid> run commands.txt
//!
//! # Интерактивный режим
//! mnd-cli --quest-root ~/quests --quest-id <uuid> repl
//! ```

use std::io::{BufRead, Write};

use anyhow::{Context, Result, bail};
use clap::{Parser, Subcommand};
use colored::Colorize;
use mnd_core::engine::{GameEngine, NextStep};

/// Консольный раннер квестов Meander.
#[derive(Parser)]
#[command(name = "mnd-cli", version, about)]
struct Cli {
    /// Корень хранилища квестов (папка с `quests/`).
    #[arg(long, default_value = ".")]
    quest_root: String,

    /// ID квеста (uuid-каталог внутри `quests/`).
    #[arg(long)]
    quest_id: String,

    /// Сейв-слот для загрузки (вместо новой игры).
    #[arg(long)]
    save_slot: Option<String>,

    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Раскрыть все айтемы стартовой ноды и выйти.
    Reveal,
    /// Выполнить скрипт команд из файла (одна команда на строку).
    Run {
        /// Путь к файлу скрипта. Без — читает stdin.
        file: Option<String>,
    },
    /// Интерактивный REPL-режим.
    Repl,
}

struct Session {
    engine: GameEngine,
}

impl Session {
    fn new(quest_root: &str, quest_id: &str) -> Result<Self> {
        let engine = GameEngine::from_disk(quest_id, quest_root)
            .with_context(|| format!("квест {quest_id} не найден в {quest_root}/quests/"))?;
        Ok(Self { engine })
    }

    fn start(&mut self, save_slot: Option<&str>) -> Result<()> {
        let view = if let Some(slot_name) = save_slot {
            let saves = self.engine.list_saves();
            let save = saves
                .iter()
                .find(|s| s.slot_name == slot_name)
                .with_context(|| format!("сейв '{slot_name}' не найден"))?;
            self.engine
                .start_from_save(save)
                .context("не удалось загрузить сейв")?
        } else {
            self.engine
                .start_new(None)
                .context("не удалось начать новую игру")?
        };

        println!(
            "{} {}{}{}",
            "▶".green().bold(),
            "Нода: ".dimmed(),
            view.title.bold(),
            format!("  [{}]", view.node_id).dimmed()
        );
        if let Some(bg) = &view.background_image_id {
            println!("  {} {}", "🖼".dimmed(), bg.dimmed());
        }
        if let Some(audio) = &view.background_audio {
            println!(
                "  {} {} (vol: {})",
                "♫".dimmed(),
                audio.audio_id.dimmed(),
                audio.volume
            );
        }
        if let Some(timer) = &view.timer {
            println!(
                "  {} {}s → {}",
                "⏱".dimmed(),
                timer.duration,
                timer.default_action_node_id.dimmed()
            );
        }
        if let Some(t) = view.transition {
            println!("  {} → {}", "↳".yellow(), t.yellow());
        }
        Ok(())
    }

    /// Раскрыть все оставшиеся айтемы, выводя каждый.
    fn reveal_all(&mut self) -> Result<()> {
        loop {
            match self.engine.next_item() {
                NextStep::Item(item) => {
                    let ci = &*item;
                    let type_str = format!("[{}]", ci.item_type).dimmed();
                    let text = ci
                        .text
                        .as_deref()
                        .unwrap_or_else(|| ci.content_markdown.as_deref().unwrap_or(""));
                    let id_str = format!("({})", ci.id).dimmed();
                    println!("  {} {} {}", type_str, text, id_str);
                }
                NextStep::Transition(node_id) => {
                    println!("  {} → {}", "↳".yellow(), node_id.yellow());
                    break;
                }
                NextStep::Done => break,
            }
        }
        Ok(())
    }

    /// Нажать айтем по id или тексту (частичное совпадение).
    fn press(&mut self, _target: &str) -> Result<()> {
        // In headless mode we don't store revealed items explicitly.
        // Use handle_interaction if the item ID is known.
        bail!("press: интерактивный режим пока не реализован")
    }

    fn print_state(&self) {
        let vars = self.engine.all_variables();
        if vars.is_empty() {
            return;
        }
        println!("{}", "Переменные:".dimmed());
        let mut keys: Vec<&str> = vars.keys().map(|s| s.as_str()).collect();
        keys.sort();
        for k in keys {
            if k.starts_with("_internal") || k == "ID" || k == "LastID" {
                continue;
            }
            let v = &vars[k];
            let val_str = if v.is_string() {
                v.as_str().unwrap().to_string()
            } else if v.is_number() {
                v.as_f64()
                    .map(|f| {
                        if f.fract() == 0.0 {
                            format!("{:.0}", f)
                        } else {
                            format!("{f}")
                        }
                    })
                    .unwrap_or_else(|| v.to_string())
            } else if v.is_boolean() {
                v.as_bool().unwrap().to_string()
            } else {
                v.to_string()
            };
            println!("  {} = {}", k, val_str);
        }
    }
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let mut session = Session::new(&cli.quest_root, &cli.quest_id)?;
    session.start(cli.save_slot.as_deref())?;

    match cli.command {
        Command::Reveal => {
            session.reveal_all()?;
            session.print_state();
        }
        Command::Run { file } => {
            let reader: Box<dyn BufRead> = if let Some(path) = file {
                let f = std::fs::File::open(&path)
                    .with_context(|| format!("не могу открыть {path}"))?;
                Box::new(std::io::BufReader::new(f))
            } else {
                Box::new(std::io::BufReader::new(std::io::stdin()))
            };
            run_script(&mut session, reader)?;
            session.print_state();
        }
        Command::Repl => {
            repl(&mut session)?;
        }
    }

    Ok(())
}

fn run_script(session: &mut Session, reader: impl BufRead) -> Result<()> {
    for (line_no, line) in reader.lines().enumerate() {
        let line = line?;
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }

        let (cmd, args) = trimmed
            .split_once(char::is_whitespace)
            .unwrap_or((trimmed, ""));
        let args = args.trim();

        match cmd {
            "reveal" | "r" => {
                session.reveal_all()?;
            }
            "press" | "p" => {
                session.press(args)?;
            }
            "state" | "s" => {
                session.print_state();
            }
            "load" | "l" => {
                let view = session
                    .engine
                    .load_node(args)
                    .with_context(|| format!("нода '{args}' не найдена"))?;
                println!("{} {}", "▶".green().bold(), view.title.bold());
                if let Some(t) = view.transition {
                    println!("  {} → {}", "↳".yellow(), t.yellow());
                }
            }
            "transition" | "t" => {
                let node_id = session
                    .engine
                    .resolve_target_node_id(args)
                    .context("не удалось разрешить переход")?;
                let view = session
                    .engine
                    .load_node(&node_id)
                    .with_context(|| format!("нода '{node_id}' не найдена"))?;
                println!("{} {}", "▶".green().bold(), view.title.bold());
                if let Some(t) = view.transition {
                    println!("  {} → {}", "↳".yellow(), t.yellow());
                }
            }
            unknown => {
                eprintln!(
                    "{}: неизвестная команда '{}' (reveal, press, state, load, transition)",
                    format!("строка {line_no}").red(),
                    unknown
                );
            }
        }
    }
    Ok(())
}

fn repl(session: &mut Session) -> Result<()> {
    let stdin = std::io::stdin();
    let mut stdout = std::io::stdout();

    println!(
        "{}  {}",
        "mnd-cli".green().bold(),
        "reveal | press <id> | state | load <node> | transition <expr> | quit".dimmed()
    );

    loop {
        print!("{} ", ">".bold());
        stdout.flush()?;

        let mut line = String::new();
        if stdin.read_line(&mut line)? == 0 {
            break; // EOF
        }
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if trimmed == "quit" || trimmed == "exit" || trimmed == "q" {
            break;
        }

        let (cmd, args) = trimmed
            .split_once(char::is_whitespace)
            .unwrap_or((trimmed, ""));
        let args = args.trim();

        match cmd {
            "reveal" | "r" => {
                if let Err(e) = session.reveal_all() {
                    eprintln!("{} {e}", "ошибка:".red());
                }
            }
            "press" | "p" => {
                if let Err(e) = session.press(args) {
                    eprintln!("{} {e}", "ошибка:".red());
                }
            }
            "state" | "s" => {
                session.print_state();
            }
            "load" | "l" => match session.engine.load_node(args) {
                Some(view) => {
                    println!("{} {}", "▶".green().bold(), view.title.bold());
                    if let Some(t) = view.transition {
                        println!("  {} → {}", "↳".yellow(), t.yellow());
                    }
                }
                None => eprintln!("{} нода '{args}' не найдена", "ошибка:".red()),
            },
            other => {
                eprintln!("{} неизвестная команда '{other}'", "ошибка:".red());
            }
        }
    }
    Ok(())
}
