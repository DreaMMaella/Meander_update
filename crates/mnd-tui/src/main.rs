//! Terminal UI player for Meander quests.
//!
//! A minimal frontend over `mnd_core::GameEngine`: reveals node content,
//! renders text/chat/images (images via unicode half-blocks + truecolor),
//! turns buttons into a selectable list, and drives script/node timers.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use crossterm::event::{Event, KeyCode, KeyEventKind, KeyModifiers};
use image::RgbImage;
use image::imageops::FilterType;
use mnd_core::engine::{GameEngine, NextStep, NodeView};
use mnd_core::executor::{DynLogger, ExecutorConfig, configure};
use mnd_core::{ContentItem, Quest};
use ratatui::Frame;
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span, Text};
use ratatui::widgets::{Block, Borders, List, ListItem, ListState, Paragraph, Wrap};

/// Интерактивный выбор: кнопка, которую можно активировать.
#[derive(Clone)]
struct Choice {
    label: String,
    item: ContentItem,
}

/// Таймер ноды (`view.timer`): авто-переход после паузы.
#[derive(Clone)]
struct NodeTimer {
    due: Instant,
    target: String,
}

/// Блок контента сцены (текст или картинка, в порядке раскрытия).
enum ContentBlock {
    Text(String),
    Image(PathBuf),
}

struct App {
    root: PathBuf,
    quest_id: String,
    engine: GameEngine,
    resume: bool,
    node_title: String,
    blocks: Vec<ContentBlock>,
    choices: Vec<Choice>,
    selected: usize,
    status: String,
    node_timer: Option<NodeTimer>,
    /// (script_path, entry) → момент срабатывания следующего тика.
    script_timers: HashMap<(String, String), Instant>,
    /// Строка-отступ скролла сцены (0 = верх).
    scroll: usize,
    /// Декодированные картинки (полный размер), кэш по пути.
    image_cache: HashMap<PathBuf, RgbImage>,
    quitting: bool,
}

const IMAGE_MAX_HEIGHT: u16 = 20;

impl App {
    fn new(root: PathBuf, quest_id: String, engine: GameEngine, resume: bool) -> Self {
        let mut app = App {
            root,
            quest_id,
            engine,
            resume,
            node_title: String::new(),
            blocks: Vec::new(),
            choices: Vec::new(),
            selected: 0,
            status: String::from("запуск…"),
            node_timer: None,
            script_timers: HashMap::new(),
            scroll: 0,
            image_cache: HashMap::new(),
            quitting: false,
        };
        app.start();
        app
    }

    fn start(&mut self) {
        let save = if self.resume {
            self.engine.read_save("_autosave")
        } else {
            None
        };
        let view = match save {
            Some(s) => self.engine.start_from_save(&s),
            None => self.engine.start_new(None),
        };
        match view {
            Some(v) => self.apply_view(v),
            None => self.status = String::from("не удалось начать игру (нет стартовой ноды?)"),
        }
    }

    fn apply_view(&mut self, view: NodeView) {
        self.node_title = if view.title.is_empty() {
            view.node_id.clone()
        } else {
            view.title.clone()
        };

        self.node_timer = view.timer.as_ref().map(|t| NodeTimer {
            due: Instant::now() + Duration::from_secs_f64(t.duration),
            target: t.default_action_node_id.clone(),
        });

        if let Some(next) = view.transition.clone()
            && !next.is_empty()
        {
            self.load_node(&next);
            return;
        }

        self.reveal();
    }

    fn load_node(&mut self, node_id: &str) {
        match self.engine.load_node(node_id) {
            Some(view) => self.apply_view(view),
            None => self.status = format!("нода не найдена: {node_id}"),
        }
    }

    /// Слить накопленные движком очереди и раскрыть все айтемы ноды.
    fn reveal(&mut self) {
        self.engine.drain_delay_steps();
        self.engine.drain_audio_commands();
        self.engine.drain_external_commands();
        self.engine.drain_state_delta();

        self.blocks.clear();
        self.choices.clear();
        self.selected = 0;
        self.scroll = 0;

        loop {
            match self.engine.next_item() {
                NextStep::Item(item) => self.push_item(&item),
                NextStep::Transition(next) => {
                    if !next.is_empty() {
                        self.load_node(&next);
                        return;
                    }
                }
                NextStep::Done => break,
            }
        }

        self.preload_images();
        self.schedule_script_timers();
    }

    fn push_item(&mut self, item: &ContentItem) {
        if item.is_hidden {
            return;
        }
        match item.item_type.as_str() {
            "text" => {
                let text = clean_text(
                    &item
                        .text
                        .clone()
                        .or_else(|| item.content_markdown.clone())
                        .unwrap_or_default(),
                );
                if !text.is_empty() {
                    self.blocks.push(ContentBlock::Text(text));
                }
            }
            "chat" => {
                let name = item.sender_name.clone().unwrap_or_default();
                let text = clean_text(&item.text.clone().unwrap_or_default());
                self.blocks.push(ContentBlock::Text(if name.is_empty() {
                    text
                } else {
                    format!("{name}: {text}")
                }));
            }
            "image" => {
                let path = item
                    .resource_path
                    .clone()
                    .map(|p| self.resolve_asset(&p))
                    .unwrap_or_default();
                if path.is_file() {
                    self.blocks.push(ContentBlock::Image(path));
                } else {
                    self.blocks.push(ContentBlock::Text(format!(
                        "[изображение: {}]",
                        path.display()
                    )));
                }
            }
            "button" => {
                let label = item
                    .text
                    .clone()
                    .or_else(|| item.button_text.clone())
                    .unwrap_or_else(|| "…".to_string());
                self.choices.push(Choice {
                    label,
                    item: item.clone(),
                });
            }
            "input" => {
                let ph = item
                    .placeholder_text
                    .clone()
                    .unwrap_or_else(|| "ввод".to_string());
                self.blocks
                    .push(ContentBlock::Text(format!("[ввод: {ph}]")));
            }
            "hud_panel" | "script" | "plugin" => {}
            _ => {
                if let Some(children) = &item.children {
                    for child in children {
                        self.push_item(child);
                    }
                }
            }
        }
    }

    /// Абсолютный путь ассета квеста (картинки/шрифты) на диске.
    fn resolve_asset(&self, rel: &str) -> PathBuf {
        let prefix = format!("quests/{}/", self.quest_id);
        let rel = rel.trim_start_matches('/');
        let rel = rel.strip_prefix(&prefix).unwrap_or(rel);
        self.root.join("quests").join(&self.quest_id).join(rel)
    }

    fn preload_images(&mut self) {
        for block in &self.blocks {
            if let ContentBlock::Image(path) = block
                && !self.image_cache.contains_key(path)
                && let Ok(img) = image::open(path)
            {
                self.image_cache.insert(path.clone(), img.to_rgb8());
            }
        }
    }

    fn schedule_script_timers(&mut self) {
        let now = Instant::now();
        for t in self.engine.pending_timers() {
            let key = (t.script_path.clone(), t.entry.clone());
            self.script_timers
                .entry(key)
                .or_insert_with(|| now + Duration::from_millis(t.ms.max(0) as u64));
        }
    }

    fn tick_timers(&mut self) {
        let now = Instant::now();

        if let Some(nt) = self.node_timer.clone()
            && now >= nt.due
        {
            self.node_timer = None;
            self.load_node(&nt.target);
            return;
        }

        self.schedule_script_timers();

        let due: Vec<(String, String)> = self
            .script_timers
            .iter()
            .filter(|(_, due)| **due <= now)
            .map(|(k, _)| k.clone())
            .collect();

        for (path, entry) in due {
            self.script_timers.remove(&(path.clone(), entry.clone()));
            if let Some(next) = self.engine.run_scheduled_timer(&path, &entry)
                && !next.is_empty()
            {
                self.load_node(&next);
                return;
            }
        }
    }

    fn move_selection(&mut self, delta: isize) {
        if self.choices.is_empty() {
            return;
        }
        let len = self.choices.len() as isize;
        let next = (self.selected as isize + delta).rem_euclid(len);
        self.selected = next as usize;
    }

    fn scroll_by(&mut self, delta: isize) {
        if delta < 0 {
            self.scroll = self.scroll.saturating_sub((-delta) as usize);
        } else {
            self.scroll = self.scroll.saturating_add(delta as usize);
        }
    }

    fn activate_selected(&mut self) {
        let Some(choice) = self.choices.get(self.selected).cloned() else {
            return;
        };
        let item = choice.item;

        let trigger = item
            .script_triggers
            .as_ref()
            .and_then(|m| m.get("onPress").cloned());

        let mut next = None;
        if let Some(tr) = trigger {
            next = self.engine.handle_interaction(&item, &tr);
        }

        if let Some(node) = next
            && !node.is_empty()
        {
            self.load_node(&node);
            return;
        }

        if let Some(target) = item.target_node_id.clone()
            && let Some(resolved) = self.engine.resolve_target_node_id(&target)
            && !resolved.is_empty()
        {
            self.load_node(&resolved);
            return;
        }

        // Скрипт мог изменить состояние без перехода: слить очереди и таймеры.
        self.engine.drain_delay_steps();
        self.engine.drain_audio_commands();
        self.engine.drain_external_commands();
        self.engine.drain_state_delta();
        self.schedule_script_timers();
        self.status = String::from("ничего не произошло");
    }

    fn autosave(&mut self) {
        self.status = match self.engine.perform_autosave() {
            Some(_) => String::from("автосохранение записано"),
            None => String::from("не удалось сохранить"),
        };
    }

    fn restart(&mut self) {
        self.engine = match GameEngine::from_disk(&self.quest_id, &self.root) {
            Some(e) => e,
            None => {
                self.status = String::from("не удалось пересоздать движок");
                return;
            }
        };
        self.script_timers.clear();
        self.node_timer = None;
        self.start();
    }

    /// Headless-смоук: вывести раскрытую ноду и завершиться без TTY.
    fn probe(&self) {
        println!("node: {}", self.node_title);
        println!("--- content ---");
        for block in &self.blocks {
            match block {
                ContentBlock::Text(t) => println!("{t}"),
                ContentBlock::Image(p) => println!("[image: {}]", p.display()),
            }
        }
        println!("--- choices ---");
        for (i, c) in self.choices.iter().enumerate() {
            println!("{}. {}", i + 1, c.label);
        }
    }

    fn run(&mut self) -> std::io::Result<()> {
        let mut terminal = ratatui::init();
        let result = self.event_loop(&mut terminal);
        ratatui::restore();
        result
    }

    fn event_loop(&mut self, terminal: &mut ratatui::DefaultTerminal) -> std::io::Result<()> {
        while !self.quitting {
            terminal.draw(|f| self.ui(f))?;

            if crossterm::event::poll(Duration::from_millis(100))?
                && let Event::Key(key) = crossterm::event::read()?
                && key.kind == KeyEventKind::Press
            {
                self.handle_key(key.code, key.modifiers);
            }

            self.tick_timers();
        }
        Ok(())
    }

    fn handle_key(&mut self, code: KeyCode, modifiers: KeyModifiers) {
        match code {
            KeyCode::Char('q') | KeyCode::Esc => self.quitting = true,
            KeyCode::Char('c') if modifiers.contains(KeyModifiers::CONTROL) => {
                self.quitting = true;
            }
            KeyCode::Up | KeyCode::Char('k') => self.move_selection(-1),
            KeyCode::Down | KeyCode::Char('j') => self.move_selection(1),
            KeyCode::PageUp => self.scroll_by(-10),
            KeyCode::PageDown => self.scroll_by(10),
            KeyCode::Enter => self.activate_selected(),
            KeyCode::Char('s') => self.autosave(),
            KeyCode::Char('r') => self.restart(),
            _ => {}
        }
    }

    fn ui(&self, f: &mut Frame) {
        let area = f.area();

        let chunks = Layout::vertical([
            Constraint::Length(2), // шапка
            Constraint::Min(4),    // контент
            Constraint::Length(3), // статус + подсказки
        ])
        .split(area);

        let header = Paragraph::new(format!(
            "Meander TUI · {} · {}",
            self.quest_id, self.node_title
        ))
        .block(Block::default().borders(Borders::ALL));
        f.render_widget(header, chunks[0]);

        self.render_content(f, chunks[1]);

        let hint = format!(
            "↑/↓ выбор · Enter — выбрать · PgUp/PgDn — скролл · s — сохранить · r — заново · q — выход\n{}",
            self.status
        );
        f.render_widget(Paragraph::new(hint).wrap(Wrap { trim: true }), chunks[2]);
    }

    fn render_content(&self, f: &mut Frame, area: Rect) {
        let choices_len = self.choices.len().max(1) as u16;
        let [log_area, choices_area] =
            Layout::vertical([Constraint::Min(3), Constraint::Length(choices_len)]).areas(area);

        let lines = self.build_lines(log_area.width);
        let total = lines.len();
        let view = log_area.height.saturating_sub(2) as usize; // рамка сверху/снизу
        let max_scroll = total.saturating_sub(view);
        let scroll = self.scroll.min(max_scroll);
        let visible: Vec<Line> = lines.into_iter().skip(scroll).take(view).collect();

        f.render_widget(
            Paragraph::new(Text::from(visible))
                .block(Block::default().borders(Borders::ALL).title("Сцена")),
            log_area,
        );

        let items: Vec<ListItem> = self
            .choices
            .iter()
            .enumerate()
            .map(|(i, c)| {
                let marker = if i == self.selected { "▶" } else { " " };
                ListItem::new(format!("{marker} {}. {}", i + 1, c.label))
            })
            .collect();

        let list = List::new(items)
            .block(Block::default().borders(Borders::ALL).title("Выбор"))
            .highlight_style(
                Style::default()
                    .fg(Color::Cyan)
                    .add_modifier(Modifier::BOLD),
            )
            .highlight_symbol(">");

        let mut state = ListState::default();
        state.select(Some(self.selected));
        f.render_stateful_widget(list, choices_area, &mut state);
    }

    /// Собрать сцену в плоский `Vec<Line>`: текст с переносом + картинки.
    fn build_lines(&self, width: u16) -> Vec<Line<'_>> {
        let mut lines = Vec::new();
        for block in &self.blocks {
            match block {
                ContentBlock::Text(t) => {
                    for para in t.split('\n') {
                        let para = para.trim_end_matches('\r');
                        if para.trim().is_empty() {
                            lines.push(Line::from(""));
                            continue;
                        }
                        for wrapped in textwrap::wrap(para, width.max(1) as usize) {
                            lines.push(Line::from(wrapped.into_owned()));
                        }
                    }
                }
                ContentBlock::Image(path) => {
                    if let Some(img) = self.image_cache.get(path) {
                        lines.extend(render_image_lines(img, width, IMAGE_MAX_HEIGHT));
                    } else {
                        lines.push(Line::from(format!("[изображение: {}]", path.display())));
                    }
                    lines.push(Line::from(""));
                }
            }
        }
        lines
    }
}

/// Отрендерить картинку как юникод-полублоки `▀` с truecolor (верх/низ пикселя).
/// Никаких внешних бинарников не нужно — работает в любом truecolor-терминале.
fn render_image_lines(img: &RgbImage, max_width: u16, max_height: u16) -> Vec<Line<'_>> {
    let (iw, ih) = (img.width() as f32, img.height() as f32);
    let scale = (max_width as f32 / iw)
        .min((max_height as f32 * 2.0) / ih)
        .min(1.0);
    let tw = (iw * scale).max(1.0) as u32;
    let th = ((ih * scale).max(2.0)) as u32;

    let resized = image::imageops::resize(img, tw, th, FilterType::Triangle);

    let mut lines = Vec::new();
    let mut y = 0;
    while y < th {
        let mut spans = Vec::with_capacity(tw as usize);
        for x in 0..tw {
            let top = resized.get_pixel(x, y);
            let bottom = if y + 1 < th {
                resized.get_pixel(x, y + 1)
            } else {
                top
            };
            spans.push(Span::styled(
                "▀",
                Style::default().fg(rgb(top)).bg(rgb(bottom)),
            ));
        }
        lines.push(Line::from(spans));
        y += 2;
    }
    lines
}

fn rgb(p: &image::Rgb<u8>) -> Color {
    Color::Rgb(p.0[0], p.0[1], p.0[2])
}

/// Куда распаковывать перетащенные `.mnd` (постоянно, чтобы сейвы жили).
fn cache_root() -> PathBuf {
    std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".cache")))
        .unwrap_or_else(std::env::temp_dir)
        .join("mnd-tui")
}

/// Безопасный относительный путь из zip-энтри (отсекаем `..` и абсолютные).
fn safe_rel_path(name: &str) -> Option<PathBuf> {
    let p = Path::new(name);
    if p.is_absolute() {
        return None;
    }
    let mut out = PathBuf::new();
    for c in p.components() {
        match c {
            std::path::Component::Normal(s) => out.push(s),
            std::path::Component::CurDir => {}
            _ => return None,
        }
    }
    Some(out)
}

fn strip_mnd_prefix(data: &[u8]) -> Result<&[u8], String> {
    if data.starts_with(b"MND_ZIP_") {
        Ok(&data[8..])
    } else if data.starts_with(b"PK\x03\x04") {
        Ok(data)
    } else if data.starts_with(b"MND_ENC_") {
        Err("зашифрованный .mnd (MND_ENC_) не поддерживается".to_string())
    } else {
        Err("не похоже на .mnd: нет MND_ZIP_ префикса и не ZIP".to_string())
    }
}

/// Распаковать `.mnd` в `<cache>/quests/<id>/` и вернуть quest_id.
fn unpack_mnd(file: &Path, cache: &Path) -> Result<String, String> {
    let data =
        std::fs::read(file).map_err(|e| format!("не удалось прочитать {}: {e}", file.display()))?;
    let payload = strip_mnd_prefix(&data)?;

    let mut archive = zip::ZipArchive::new(std::io::Cursor::new(payload))
        .map_err(|e| format!("не удалось открыть zip: {e}"))?;

    let mut quest_id: Option<String> = None;
    for i in 0..archive.len() {
        let mut entry = archive.by_index(i).map_err(|e| format!("zip: {e}"))?;
        if entry.name() == "config.json" {
            let mut bytes = Vec::new();
            std::io::copy(&mut entry, &mut bytes).map_err(|e| format!("zip: {e}"))?;
            let value: serde_json::Value =
                serde_json::from_slice(&bytes).map_err(|e| format!("config.json: {e}"))?;
            quest_id = Some(Quest::from_json(&value).id);
            break;
        }
    }
    let quest_id = quest_id.ok_or_else(|| "в архиве нет config.json".to_string())?;
    if quest_id.is_empty() {
        return Err("в config.json нет id".to_string());
    }

    let quest_dir = cache.join("quests").join(&quest_id);
    for i in 0..archive.len() {
        let mut entry = archive.by_index(i).map_err(|e| format!("zip: {e}"))?;
        if entry.is_dir() {
            continue;
        }
        let Some(rel) = safe_rel_path(entry.name()) else {
            continue;
        };
        let out_path = quest_dir.join(rel);
        if let Some(parent) = out_path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| format!("не удалось создать каталог: {e}"))?;
        }
        let mut out = std::fs::File::create(&out_path)
            .map_err(|e| format!("не удалось записать {}: {e}", out_path.display()))?;
        std::io::copy(&mut entry, &mut out).map_err(|e| format!("распаковка: {e}"))?;
    }

    Ok(quest_id)
}

/// Убрать bbcode/markdown-обёртки, чтобы текст был читаем в терминале.
fn clean_text(input: &str) -> String {
    let mut s = input.to_string();
    while let Some(start) = s.find("[color=") {
        if let Some(end) = s[start..].find(']') {
            s.replace_range(start..start + end + 1, "");
        } else {
            break;
        }
    }
    for tag in [
        "[/color]", "[b]", "[/b]", "[i]", "[/i]", "[u]", "[/u]", "**", "__", "`",
    ] {
        s = s.replace(tag, "");
    }
    s
}

fn list_quests(root: &Path) {
    let qroot = root.join("quests");
    let Ok(entries) = std::fs::read_dir(&qroot) else {
        eprintln!("нет каталога {}", qroot.display());
        return;
    };
    for entry in entries.filter_map(Result::ok) {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let config = path.join("config.json");
        if !config.is_file() {
            continue;
        }
        let id = entry.file_name().to_string_lossy().to_string();
        let title = std::fs::read_to_string(&config)
            .ok()
            .and_then(|s| serde_json::from_str::<serde_json::Value>(&s).ok())
            .map(|v| Quest::from_json(&v).title)
            .unwrap_or_default();
        println!("{id}\t{title}");
    }
}

fn print_help() {
    println!(
        "mnd-tui — терминальный плеер квестов Meander\n\
         \n\
         Использование:\n\
           mnd-tui <файл.mnd> [--continue]\n\
           mnd-tui --root <каталог> --quest <id> [--continue]\n\
           mnd-tui --root <каталог> --list\n\
         \n\
         Файл .mnd можно перетащить в терминал после команды.\n\
         \n\
         Опции:\n\
           --continue    продолжить с автосохранения\n\
           --list        показать список квестов\n\
           --probe       без TTY: вывести стартовую ноду и выйти\n\
         \n\
         Клавиши: ↑/↓ — выбор, Enter — выбрать, PgUp/PgDn — скролл,\n\
                  s — сохранить, r — начать заново, q — выход"
    );
}

fn main() {
    // Гасим дебаг-логи движка ([Rust/mnd-core] ...), чтобы они не портили TUI.
    let noop_logger: DynLogger = std::sync::Arc::new(|_msg: &str| {});
    configure(ExecutorConfig {
        logger: Some(noop_logger),
        ..Default::default()
    });

    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut positionals: Vec<String> = Vec::new();
    let mut root: Option<PathBuf> = None;
    let mut quest: Option<String> = None;
    let mut resume = false;
    let mut list = false;
    let mut probe = false;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--root" => {
                if i + 1 < args.len() {
                    root = Some(PathBuf::from(&args[i + 1]));
                    i += 1;
                }
            }
            "--quest" => {
                if i + 1 < args.len() {
                    quest = Some(args[i + 1].clone());
                    i += 1;
                }
            }
            "--continue" => resume = true,
            "--list" => list = true,
            "--probe" => probe = true,
            "--help" | "-h" => {
                print_help();
                return;
            }
            other if other.starts_with('-') => {
                eprintln!("неизвестный аргумент: {other}");
                print_help();
                std::process::exit(2);
            }
            other => positionals.push(other.to_string()),
        }
        i += 1;
    }

    // Перетащенный .mnd: распаковываем в кэш и играем.
    if let Some(file) = positionals.first()
        && file.to_lowercase().ends_with(".mnd")
    {
        let cache = cache_root();
        let quest_id = match unpack_mnd(Path::new(file), &cache) {
            Ok(id) => id,
            Err(e) => {
                eprintln!("{e}");
                std::process::exit(1);
            }
        };
        let Some(engine) = GameEngine::from_disk(&quest_id, &cache) else {
            eprintln!("после распаковки не найден quests/{quest_id}");
            std::process::exit(1);
        };
        let mut app = App::new(cache, quest_id, engine, resume);
        if probe {
            app.probe();
            return;
        }
        if let Err(e) = app.run() {
            eprintln!("ошибка: {e}");
            std::process::exit(1);
        }
        return;
    }

    let root = root.unwrap_or_else(|| {
        let home = std::env::var("HOME").unwrap_or_default();
        PathBuf::from(home).join("Documents")
    });

    if list {
        list_quests(&root);
        return;
    }

    let Some(quest_id) = quest else {
        eprintln!("укажите .mnd файл или --quest <id> (список: mnd-tui --root <dir> --list)");
        std::process::exit(2);
    };

    let Some(engine) = GameEngine::from_disk(&quest_id, &root) else {
        eprintln!("квест не найден: {}/quests/{quest_id}", root.display());
        std::process::exit(1);
    };

    let mut app = App::new(root, quest_id, engine, resume);
    if probe {
        app.probe();
        return;
    }
    if let Err(e) = app.run() {
        eprintln!("ошибка: {e}");
        std::process::exit(1);
    }
}
